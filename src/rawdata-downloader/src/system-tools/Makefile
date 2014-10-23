SYSTEM_PREFIX=/

all:

install:
	cp -rv sbin ${SYSTEM_PREFIX}
	cp -rv etc ${SYSTEM_PREFIX}
	sed -r -i -e "s#__PREFIX__#${SYSTEM_PREFIX}#g" -e T -e 's#//#/#g' ${SYSTEM_PREFIX}/sbin/scsi-disk-udev-eventhandler ${SYSTEM_PREFIX}/sbin/rawdata-download ${SYSTEM_PREFIX}/sbin/build-modules-file ${SYSTEM_PREFIX}/etc/udev/rules.d/90-rawdata-downloader.rules
