#!/usr/bin/env bash
#
# Copyright (C) 2020 Hach
# Author: Dragan Cecavac <dcecavac@witekio.com>
#

# Function ensure_encryption_support checks if there is a functional
# encryption support provided in the new image.
# The goal is to prevent downgrades such as to BSP 2.8 where encryption
# was not supported.
#
# SWUpdate causes some confusion by calling this a preinstall script,
# because it will not be called at the very start of the update process,
# but after all components with the option "installed-directly = true;"
# have been installed.

# If this flag is set, i.e. this file exists, it means that the SWU file being
# processed does not perform a system update.
# Therefore, update related tasks are not performed and this file is removed in
# order to handle future updates properly.
NOUPDATE_FLAG=%NOUPDATE_FLAG%

function ensure_encryption_support() {
	mount_point=`mktemp -d`
	mount -o ro /dev/mmcblk_hook_rfs $mount_point

	if [ ! -f $mount_point/usr/sbin/cryptsetup ]; then
		umount $mount_point
		/etc/swupdate-log.sh "Error: SWUpdate image does not support encryption."
		exit -1
	fi

	umount $mount_point
}

if [ -e "${NOUPDATE_FLAG}" ]; then
	echo "not an update, skipping swupdate-preinstall.sh"

	rm -rf "${NOUPDATE_FLAG}"
else
	echo "swupdate-preinstall.sh ..."

	ensure_encryption_support

	# swupdate-support.service is responsible of checking the state of the dual-bootloader
	# and repair it in case a problem is detected. Restarting it to ensure that both bootloaders
	# are in a good state at the time of the update.
	systemctl restart swupdate-support.service
fi

# Make sure the directory /tmp/scripts exists and is empty
# The use of an SWU file can fail if it does not exists or if its contained
# files conflicts with files SWUpdate tries to load (by name)
# A clean /tmp/scripts directory must exists not only for update, but also
# for unlock keys as this special kind of SWU file also loads scripts in it
rm -rf /tmp/scripts
mkdir /tmp/scripts

exit 0
