SYSTEM_PREFIX=/

all:

install:
	cp -rv ./usr/sbin ${SYSTEM_PREFIX}/usr
	cp -rv ./etc ./var ${SYSTEM_PREFIX}
	sed -r -i -e "s#__PREFIX__#${SYSTEM_PREFIX}#g" -e T -e 's#//#/#g' ${SYSTEM_PREFIX}/usr/sbin/scsi-disk-udev-eventhandler ${SYSTEM_PREFIX}/usr/sbin/rawdata-download ${SYSTEM_PREFIX}/usr/sbin/build-modules-file ${SYSTEM_PREFIX}/etc/udev/rules.d/90-rawdata-downloader.rules
