
FILESEXTRAPATHS_prepend := "${THISDIR}/files:"
SYSTEMD_SERVICE_${PN} += "swupdate-support.service"

SRCREV = "07811c7b570ae8a75d78f39bb75baf840cfad656"

SRC_URI += "\
	file://hwrevision \
	file://public.pem \
	file://swupdate-compatibility.sh \
	file://swupdate-log.sh \
	file://swupdate-preinstall.sh \
	file://swupdate-support.sh \
	file://swupdate-support.service \
	file://swupdate-progress.service \
	file://swupdate-usb.sh \
	file://swupdate-unlock.sh \
	file://uboot-helper.sh \
	file://completion.sh \
	file://uboot-helper.sh_complete.sh \
	file://unlock.conf \
	file://unlock@.service \
	file://HACH_UPDATE_320x240.bmp \
	file://HACH_UPDATE_FAILURE_320x240.bmp \
	file://HACH_UNLOCK_320x240.bmp \
	file://HACH_UNLOCK_FAILURE_320x240.bmp \
	\
	file://0001-Log-update-progress-in-new-lines.patch \
	file://0002-Display-USB-LOCAL-source-when-update-is-initiated-vi.patch \
"


# File that indicates by its existence that a processed SWU file does not perform
# an update, disabling some scripts that are only necessary for system update.
# It is recommended that the location of this flag is specified somewhere only root
# can create it.
# First, it would avoid having in enable by mistake (avoid /tmp!),and second it
# ensures that only root can alter the way an SWU file is processed.
noupdate_flag_path = "/run/swu_is_no_update"

do_configure_append() {
	sed -i -e "s|%NOUPDATE_FLAG%|${noupdate_flag_path}|" ${WORKDIR}/swupdate-preinstall.sh
	sed -i -e "s|%NOUPDATE_FLAG%|${noupdate_flag_path}|" ${WORKDIR}/swupdate-unlock.sh
}

do_install_append () {
	install -m 640 ${WORKDIR}/hwrevision ${D}${sysconfdir}/
	install -m 640 ${WORKDIR}/public.pem ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/swupdate-compatibility.sh ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/swupdate-log.sh ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/swupdate-preinstall.sh ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/swupdate-support.sh ${D}${sysconfdir}/
	install -m 644 ${WORKDIR}/swupdate-support.service ${D}${systemd_unitdir}/system/
	install -m 644 ${WORKDIR}/swupdate-progress.service ${D}${systemd_unitdir}/system/
	install -m 750 ${WORKDIR}/swupdate-usb.sh ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/swupdate-unlock.sh ${D}${sysconfdir}/
	install -m 750 ${WORKDIR}/uboot-helper.sh ${D}${sysconfdir}/
        rm ${D}${systemd_unitdir}/system/swupdate-usb@.service
        rm ${D}${sysconfdir}/udev/rules.d/swupdate-usb.rules	
        echo ${DISTRO_VERSION} > ${D}${sysconfdir}/swversion
	install -d ${D}/home/root/images/
	install -m 0644 ${WORKDIR}/HACH_UPDATE_320x240.bmp ${D}/home/root/images/
	install -m 0644 ${WORKDIR}/HACH_UPDATE_FAILURE_320x240.bmp ${D}/home/root/images/
	install -m 0644 ${WORKDIR}/HACH_UNLOCK_320x240.bmp ${D}/home/root/images/
	install -m 0644 ${WORKDIR}/HACH_UNLOCK_FAILURE_320x240.bmp ${D}/home/root/images/
	install -d ${D}/${sysconfdir}/profile.d
	install -m 0755 ${WORKDIR}/completion.sh ${D}/${sysconfdir}/profile.d
	install -d ${D}/${sysconfdir}/bash_completion.d
	install -m 0644 ${WORKDIR}/uboot-helper.sh_complete.sh ${D}/${sysconfdir}/bash_completion.d

	# Ensure unlock service is started when a a partition is mounted
	install -d ${D}/etc/systemd/system/media-.mount.d/
	install -m 0644 ${WORKDIR}/unlock.conf ${D}/etc/systemd/system/media-.mount.d/
	install -m 0644 ${WORKDIR}/unlock@.service ${D}/etc/systemd/system/
}

FILES_${PN} += " \
	/home/root/images/HACH_UPDATE_320x240.bmp \
	/home/root/images/HACH_UPDATE_FAILURE_320x240.bmp \
	/home/root/images/HACH_UNLOCK_320x240.bmp \
	/home/root/images/HACH_UNLOCK_FAILURE_320x240.bmp \
	${sysconfdir}/profile.d/completion.sh \
	${sysconfdir}/bash_completion.d/uboot-helper.sh_complete.sh \
"

SYSTEMD_SERVICE_${PN} = "swupdate.service swupdate-progress.service swupdate-support.service"
