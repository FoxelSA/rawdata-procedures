#!/bin/bash
#
# rawdata-toolbox.sh - rawdata-downloader library
#
# Copyright (c) 2013-2015 FOXEL SA - http://foxel.ch
# Please read <http://foxel.ch/license> for more information.
#
#
# Author(s):
#
#       Luc Deschenaux <l.deschenaux@foxel.ch>
#
#
# This file is part of the FOXEL project <http://foxel.ch>.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Additional Terms:
#
#       You are required to preserve legal notices and author attributions in
#       that material or in the Appropriate Legal Notices displayed by works
#       containing it.
#
#       You are required to attribute the work as explained in the "Usage and
#       Attribution" section of <http://foxel.ch/license>.


trap "killtree -9 $MYPID yes" SIGINT SIGKILL SIGTERM SIGHUP

# get camera MAC address using BASE_IP and MASTER_IP
get_camera_macaddr() {

  # do nothing if already set
  [ -n "$MACADDR" ] && return

  if ! ping -w 5 -c 1 $BASE_IP.$MASTER_IP > /dev/null ; then
    log ${LINENO} error: unable to ping $BASE_IP.$MASTER_IP
    exit 1
  fi

  MACADDR=$(macaddr $BASE_IP.$MASTER_IP | tr 'a-f' 'A-F')
  if [ -z "$MACADDR" ] ; then
    log ${LINENO} error: "unable to get MAC address for $BASE_IP.$MASTER_IP"
    exit 1
  fi
}

debugmode_update() {
  if [ -n "$DEBUG" ] ; then
    set -x
    set -v
    PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  else
    set +x
    set +v
    PS4='+'
  fi
}

get_modules_list_for_multiplexer() {
  local multiplexer=$1
  local line
  grep -E -e "^[0-9]+ $multiplexer " $MODULES_FILE | while read line; do
    line=($line)
    [ "${line[1]}" == "$multiplexer" ] && echo ${line[0]}
  done
}

# return MAC address for givent IP
macaddr() {
  local _ADDR=$1
  arp -n $_ADDR | awk '/[0-9a-f]+:/{gsub(":","-",$3);print $3}'
}

# kill child processes, and optionally the root process
killtree() {

    # disable ctrl-c
    trap '' SIGINT

    local _pid=$2
    local _sig=$1
    local killroot=$3

    # stop parents children production between child killing and parent killing
    #[ "${_pid}" != "$MYPID" ] && kill -STOP ${_pid}
    for _child in $(ps -o pid --no-headers --ppid ${_pid} 2>/dev/null); do
        killtree ${_sig} ${_child} yes
    done
    [ -n "$killroot" ] && (kill ${_sig} ${_pid} >/dev/null 2>&1 && wait ${_pid} > /dev/null 2>&1) > /dev/null 2>&1
}

# send log message to stderr
log() {
  local _LOG_PREFIX
  local LINE
  local MSGLEVEL

  if [ -n "$LOG_PREFIX" ] ; then
    _LOG_PREFIX="$LOG_PREFIX"
  else
    _LOG_PREFIX="$(basename $0)"
  fi

  # first argument should be line number
  LINE=$1
  shift

  # second argument should be message log level (info:, error:, debug:)
  if [[ "$1" =~ :$ ]] ; then
    MSGLEVEL=$1
    shift
  else
    # log level defaults to debug:
    MSGLEVEL=debug:
  fi

  # only if WHAT begins with "error" or in VERBOSE mode
  shopt -s nocasematch
  [[ -n "$VERBOSE" || "$MSGLEVEL" =~ ^error ]] && echo $(date +%F_%R:%S) $_LOG_PREFIX $BASHPID $LINE $MSGLEVEL $@ >&2
  shopt -u nocasematch
}

# format stdout as log messages
logstdout() {
  local _LOG_PREFIX
  local LINE
  local MSGLEVEL

  if [ -n "$LOG_PREFIX" ] ; then
    _LOG_PREFIX="$LOG_PREFIX"
  else
    _LOG_PREFIX="$(basename $0)"
  fi

  # first argument should be line number
  LINE=$1
  shift

  # second argument should be message log level (info:, error:, debug:)
  if [[ "$1" =~ :$ ]] ; then
    MSGLEVEL=$1
    shift
  else
    # log level defaults to debug:
    MSGLEVEL=debug:
  fi

  shopt -s nocasematch
  while read l ; do
    [[ -n "$VERBOSE" || "$MSGLEVEL" =~ ^error ]] && echo $(date +%F_%R:%S) $_LOG_PREFIX $BASHPID $LINE $MSGLEVEL $@ $l >&2
  done
  shopt -u nocasematch
}

# return multiplexer index for given module
get_mux_index() {
  local module=$1
  grep -E -e "^$module " $MODULES_FILE | cut -f 2 -d ' '
}

# remove scsi host (will be added in connect_q_run after requesting connection for next ssd of this mux)
remove_scsi_device() {
  [ -n "$REMOVE_SCSI_DEVICE" ] || return
  if [ -n "$HOTSWAP_USING_SYS" ] ; then
    log ${LINENO} info: set device $DEVICE  offline and delete it
    echo offline | tee /sys/block/$(basename $DEVICE)/device/state 2>&1 | logstdout ${LINENO}
    echo 1 | tee /sys/block/$(basename $DEVICE)/device/delete 2>&1 | logstdout ${LINENO}
  else
    log ${LINENO} info: removing device mux $MUX_INDEX index $REMOTE_SSD_INDEX
    echo "scsi remove-single-device $SCSIHOST" | tee /proc/scsi/scsi 2>&1 | logstdout ${LINENO}
  fi
  echo $SCSIHOST >> $REMOVED_SCSI_TMP
}

# add scsi device, if previously removed
add_scsi_device() {
  [ -n "$REMOVE_SCSI_DEVICE" ] || return
  hbtl=$(get_scsihost $MUX_INDEX)
  if [ -n "$hbtl" ] ; then
    log ${LINENO} info: "adding scsi device using values from cache"
    if [ -n "$HOTSWAP_USING_SYS" ] ; then
      hbtl=($hbtl)
      echo "${hbtl[1]} ${hbtl[2]} ${hbtl[3]}" | tee /sys/class/scsi_host/host${hbtl[0]}/scan 2>&1 | logstdout ${LINENO}
    else
      echo "scsi add-single-device $hbtl" | tee /proc/scsi/scsi 2>&1 | logstdout ${LINENO}
    fi
  fi
}

# add previously removed scsi devices
restore_scsi_devices() {
  local htbl
  if [ -z "$HOTSWAP_USING_SYS" ] ; then
    sort -u $REMOVED_SCSI_TMP | while read hbtl ; do
      log ${LINENO} info: "adding previously removed scsi devices"
      echo "scsi add-single-device $hbtl" | tee /proc/scsi/scsi 2>&1 | logstdout ${LINENO}
      sed -r -i -e "/^$hbtl\$/d" $REMOVED_SCSI_TMP
    done
  fi
}

# assert user is root
assert_root() {
  if [ $UID -ne 0 ] ; then
    echo error: $(basename $0) must be run as root >&2
    exit 1
  fi
}

# exit if specified commands not in path
assertcommands() {
  while [ $# -ne 0 ] ; do
    local CMD=$1
    shift
    [ -z "$(which $CMD)" ] && echo command $CMD not found && exit 1
  done
}

# exit if modules file not found
assert_modulesfile() {
  if [ ! -f $MODULES_FILE ] ; then
    log ${LINENO} error: file not found: $MODULES_FILE
    log ${LINENO} error: "=> run 'build-modules-file -m <mount_point>' first"
    exit 1
  fi
}

# reset multiplexers
reset_eyesis_ide() {
  log ${LINENO} info: reset eyesis_ide
  local MUXES=($_MUXES)
  for (( i=0 ; $i < ${#MUXES[@]} ; ++i )) do
    log ${LINENO} info: wget http://$BASE_IP.${MUXES[$i]}/eyesis_ide.php
    wget -q http://$BASE_IP.${MUXES[$i]}/eyesis_ide.php -O - > /dev/null || exit 1
  done
}

get_camera_uptime() {
  ssh root@$BASE_IP.$MASTER_IP cat /proc/uptime | cut -f 1 -d '.'
}

# sleep until camera uptime is greater than 180sec
wait_until_camera_awake() {

  log ${LINENO} info: get camera uptime
  CAMERA_UPTIME=$(get_camera_uptime)
  if [ -z "$CAMERA_UPTIME" ] ; then
    log ${LINENO} error: cannot get camera uptime
    exit 1
  fi

  if [ $CAMERA_UPTIME -lt 180 ] ; then
    log ${LINENO} info: "wait $((180-CAMERA_UPTIME)) seconds for camera wake up"
    sleep $((180-CAMERA_UPTIME))
  fi
}

build_sshall_login_list() {
  for (( i=0 ; $i < $MODULES_COUNT ; ++i )) ; do
    echo -n " root@$BASE_IP.$((MASTER_IP + i))"
  done
  set +x
}

# delay script execution or exit if another instance is running yet
# check whether the camera ssh server is functional for SSHALL_HOSTS
# or die
assert_remote_ssh_servers_functional() {

  local FIFO=$(mktemp -u).$$
  mkfifo $FIFO
  HOSTS=$(build_sshall_login_list) sshall true > $FIFO 2>&1 &
  local count=0

  while read l ; do
    msg=($l)
    if [ ${msg[0]} != "sshall:" ] ; then
      log ${LINENO} debug: check_remote_ssh_servers: $l
      continue
    fi
    [ ${msg[2]} = "stderr" ] && log ${LINENO} info: check_remote_ssh_servers: $l
    LOGIN=${msg[1]}
    [ -z "$LOGIN" ] && log ${LINENO} error: check_remote_ssh_servers: $l && killtree -KILL $MYPID
    WHAT=${msg[2]}
    case "$WHAT" in
    status)
      STATUS=${msg[3]}
      if [ "$STATUS" != "0" ] ; then
        log ${LINENO} error: "$l"
        log ${LINENO} error: "ssh failed for camera $IP with exit code $STATUS"
        killtree -KILL $MYPID yes
      else
        ((++count))
      fi
      ;;
    esac
  done < $FIFO

  if [ "$count" == "$MODULES_COUNT" ] ; then
    log ${LINENO} info: "remote ssh server functional on every modules"
  else
    log ${LINENO} error: "assert_remote_ssh_servers_functional failed"
    log ${LINENO} error: "check network cables or reboot the camera"
    killtree -KILL $MYPID yes
  fi

  rm $FIFO
}

# run hdparm on SSHALL_HOSTS (using sshall) for specified device
get_remote_disk_serial() {
  local dev=$1
  HOSTS=$(build_sshall_login_list) sshall /sbin/hdparm -i $dev \| sed -r -n -e "'s/.*SerialNo=([^ ]+).*/\1/p'"
}

# fill SSD_SERIAL and STATUS arrays for logins listed in SSHALL_HOSTS variable
get_camera_ssd_serials() {
  # get camera ssd serials
  log ${LINENO} info: get ssd serials

  STATUS=()
  SSD_SERIAL=()

  local FIFO=$(mktemp -u).$$
  mkfifo $FIFO
  get_remote_disk_serial /dev/hda > $FIFO 2>&1 &
  local PIPE_PID=$!

  local l
  local msg
  local LOGIN
  local INDEX
  local WHAT
  local SERIAL

  while read l ; do
    msg=($l)
    [ ${msg[0]} = "sshall:" ] || continue
    [ ${msg[2]} = "stderr" ] && log ${LINENO} info: get_remote_disk_serial: $l
    LOGIN=${msg[1]}
    [ -z "$LOGIN" ] && log ${LINENO} error: get_remote_disk_serial: $l && killtree -KILL $MYPID
    IP=$(echo $LOGIN | sed -r -n -e 's/.*@[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+).*/\1/p')
    INDEX=$(expr $IP - $MASTER_IP)
    WHAT=${msg[2]}
    case "$WHAT" in
    status)
      STATUS[$INDEX]=${msg[3]}
      [ "${STATUS[$INDEX]}" != "0" ] && log ${LINENO} error: get_remote_serial: $IP && killtree -KILL $MYPID
      ;;
    stdout)
      SERIAL=${msg[3]}
      SSD_SERIAL[$INDEX]=$SERIAL
      ;;
    esac
  done < $FIFO

  kill $PIPE_PID > /dev/null 2>&1
}

# unmount /usr/html/CF for SSHALL_HOSTS
umount_cf() {
  HOSTS=$(build_sshall_login_list) sshall << 'EOF'
if grep -q ' /usr/html/CF ' /proc/mounts ; then
  sync
  umount /usr/html/CF || exit 1
  sync
fi
exit 0
EOF
}

# wrapper for umount_cf
umount_all() {
  umount_cf 2>&1 | tee | while read l ; do
    msg=($l)
    [ ${msg[0]} = "sshall:" ] || continue
    LOGIN=${msg[1]}
    [ -z "$LOGIN" ] && echo error: umount_all: $l && killtree -KILL $MYPID yes
    WHAT=${msg[2]}
    [ "$WHAT" != "status" ] && continue
    IP=$(echo $LOGIN | sed -r -n -e 's/.*@[0-9]+\.[0-9]+\.[0-9]+\.([0-9]+).*/\1/p')
    INDEX=$(expr $IP - $MASTER_IP)
    STATUS=${msg[3]}
    if [ "$STATUS" != "0" ] ; then
      log ${LINENO} error: "could not unmount disk on module $INDEX ($IP)"
      killtree -KILL $MYPID yes
    fi
  done
}

# queue first ssd for each mux, in connect queue
connect_queue_init() {
  local i
  local MUXES=($_MUXES)
  for (( i=0 ; i < ${#MUXES[@]} ; ++i )) ; do
    echo $i 1 >> $CONNECT_Q_TMP
  done
}

# return array index of ssd serial
get_ssd_index() {
  local _SERIAL=$1
  local i
  for (( i=0 ; $i < ${#SSD_SERIAL[@]} ; ++i )) ; do
    if [ "${SSD_SERIAL[$i]}" = "$_SERIAL" ] ; then
      echo $i
      break
    fi
  done
}

# retrun number of seconds since last modification of specified file
modtime() {
  local filename="$1"
  expr $(date +%s) - $(stat -c %Y "$filename")
}

# cache scsi address associated with mux index
save_scsihost() {
  local MUX_INDEX=$1
  shift
  local SCSIHOST=$@
  grep -q $MUX_INDEX $SCSIHOST_TMP || echo $MUX_INDEX $SCSIHOST >> $SCSIHOST_TMP
}

# read cached scsi address associated with mux index
get_scsihost() {
  local MUX_INDEX=$1
  grep $MUX_INDEX $SCSIHOST_TMP | sed -r -e 's/^[0-9]+ (.*)/\1/'
}

# get module number for ssd serial
get_module_index() {
  local SERIAL=$1
  echo $(($(get_ssd_index $SERIAL)+1))
}

# return modules list for given multiplexer
get_modules_list_for_multiplexer() {
  local multiplexer=$1
  local line
  grep -E -e "^[0-9]+ $multiplexer " $MODULES_FILE | while read line; do
    line=($line)
    [ "${line[1]}" == "$multiplexer" ] && echo ${line[0]}
  done
}

# log every line in specified file, until specified regexp is matched
wait_regexp() {

  local TMP_INPUT=$1
  local REGEXP="$2"
  local msg

  local FIFO=$(mktemp -u).$$
  mkfifo $FIFO
  tail -f $TMP_INPUT > $FIFO 2>&1 &
  local TAIL_PID=$!

  while read msg ; do
    echo $msg | logstdout ${LINENO}
    [[ "$msg" =~ "$REGEXP" ]] && break
  done < $FIFO

  kill $TAIL_PID > /dev/null 2>&1

  rm $TMP_INPUT $FIFO
}

no_concurrency() {

  local ACTION=$1
  local PIDFILE="$2"

  local NAME=$(basename $0)

  [ -z "$PIDFILE" ] && PIDFILE=/var/run/$NAME.pid

  # wait for concurrent process exit
  [ -s "$PIDFILE" ] && OLDPID=$(cat $PIDFILE)
  [ -n "$OLDPID" -a "$OLDPID" != "$$" ] && while kill -0 $OLDPID 2>/dev/null && [ "$(grep Name /proc/$OLDPID/status 2>/dev/null | cut -f 2)" == "$NAME" ] ; do
    case $ACTION in
      sleep)
        sleep 1
        OLDPID=$(cat $PIDFILE)
      ;;
      *) killtree -KILL $MYPID yes ;;
    esac
  done

  # lock this process
  echo $$ > $PIDFILE

}

# return scsi address (host bus target lun) from specified UDEVINFO line
get_hbtl() {
  grep DEVPATH= $1 | sed -r -n -e 's#.*/([0-9]:[0-9]:[0-9]:[0-9])/.*#\1#' -e T -e 's/:/ /gp'
}

get_master_timestamp() {

  local DESTINATION=$MOUNTPOINT/rawdata/$MACADDR/master
  if [ -z "$DESTINATION" ] ; then
    log ${LINENO} error: "Destination not specified"
    exit 1
  fi
  log ${LINENO} info: get the oldest MOV file on $PARTITION_MOUNTPOINT
  CAM_OLDEST_MOV=$(basename `find $PARTITION_MOUNTPOINT/ -iname '*.mov' | sort | head -n1` 2>/dev/null)

  if [ -z "$CAM_OLDEST_MOV" ] ; then
    log ${LINENO} error: no MOV file found on $PARTITION_MOUNTPOINT
    killtree -TERM $MYPID yes
  fi

  log ${LINENO} info: extract the master timestamp from file $CAM_OLDEST_MOV
  MASTER_TS=${CAM_OLDEST_MOV%%_*}

  log ${LINENO} info: get the most recent master timestamp directory on $DESTINATION
  DEST_NEWEST_TS=$(basename `find $DESTINATION/ -maxdepth 1 -type d | grep -E -e '^[0-9]+$' | sort | tail -n1` 2>/dev/null)

  # If MOVs older than CAM_OLDEST_MOV were deleted manually on the camera,
  # maybe CAM_OLDEST_MOV is already in the the last segment directory.
  # In that case, reuse this directory. (This should not happend if the camera
  # has been reformatted properly according to the standard procedure)
  if [ -f "$DESTINATION/$DEST_NEWEST_TS/mov/$MODULE_INDEX/$CAM_OLDEST_MOV" ]; then
      log ${LINENO} info: "Reusing existing master $DEST_NEWEST_TS"
      MASTER_TS=$DEST_NEWEST_TS

  else
      log ${LINENO} info: "Allocating new master $MASTER_TS"
  fi

  echo "$MASTER_TS"
}

is_array() {
   local variable_name="$1"
   [[ "$(declare -p $variable_name) 2>/dev/null" =~ "declare -a" ]]
}

get_module_count() {

  local MUX_SSD_COUNT=($_MUX_SSD_COUNT)                         
  local MUXES=($_MUXES)                         
  local TOTAL=0                                 
  local i

  if [ ${#MUX_SSD_COUNT[@]} -ne ${#MUXES[@]} ] ; then
    log ${LINENO} error: "mux list and ssd count list length mismatch"
    killall -KILL $MYPID
  fi

  for (( i=0; i<${#MUX_SSD_COUNT[@]} ; ++i )) ; do    
    ((TOTAL+=${MUX_SSD_COUNT[i]}))
  done                                                                                                                

  echo $TOTAL
}

get_modules_file() {
  MODULES_FILE=$MOUNTPOINT/camera/$MACADDR/rawdata-downloader/modules
  if ! [ -f "$MODULES_FILE" ] ; then
    log ${LINENO} error: "file not found: $MODULES_FILE"
    log ${LINENO} error: "run build-modules-file first or specify the proper mountpoint with -m"
    exit 1
  fi
}

