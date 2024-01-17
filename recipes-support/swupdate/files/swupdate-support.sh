#!/usr/bin/env bash
#
# Copyright (C) 2020 Hach
# Author: Dragan Cecavac <dcecavac@witekio.com>
#
# this script is installed in the controller in /etc
# and launched each startup
#

source /etc/swupdate-log.sh
redirect_outputs_to_logs

function prepare_hooks_to_bank_a() {
	ln -s /dev/mmcblk0p1 /dev/mmcblk_hook_bfs
	ln -s /dev/mmcblk0p2 /dev/mmcblk_hook_rfs
}

function prepare_hooks_to_bank_b() {
	ln -s /dev/mmcblk0p3 /dev/mmcblk_hook_bfs
	ln -s /dev/mmcblk0p4 /dev/mmcblk_hook_rfs
}

function set_bank_revision() {
	cmdline="$(cat /proc/cmdline)"

	if [[ $cmdline == *root=/dev/mmcblk0p2* ]]; then
		prepare_hooks_to_bank_b
	elif [[ $cmdline == *root=/dev/mmcblk0p4* ]]; then
		prepare_hooks_to_bank_a
	fi

	# Store the value of bank_selection in a file so that the systemd unit
	# file for swupdate.service can determine what system bank is active
	fw_printenv bank_selection > /run/system_bank.env
}

# By default, uboot environment don't have any values to locate bootloader and its environment for recovery
# Here we populate it if needed. Normally only after a tezi install or a SWU update. SWU update is covered by shellscript.sh
function initialize_bootloader_recovery() {
	echo "Initialize uboot environment with bootloader locations"
	/etc/uboot-helper.sh populate-uboot-env
}

function overwrite_secondary_bootloader() {
	success=false

	# Backup U-BOOT and its environment
	/etc/uboot-helper.sh backup-uboot-primary && /etc/uboot-helper.sh backup-ubootenv-primary && success=true
	if "${success}"; then
		echo "Overwrite of the secondary bootloader successful"
	else
		echo "Failed to overwrite the secondary bootloader"
	fi
}

function recover_primary_bootloader() {
	success=false

	/etc/uboot-helper.sh restore-uboot-primary && /etc/uboot-helper.sh restore-ubootenv-primary && success=true
	if "${success}"; then
		echo "Primary bootloader recovery successful"
	else
		echo "Failed to recover the primary bootloader"
	fi
}

# This function checks that the primary and secondary bootloaders, and their
# environments, are identical.
# It is used to detect if the secondary bootloader has been altered in order
# to fix it when it happens.
function bootloaders_synchronized() {

	# Checking that both primary and secondary bootloaders and their respective environments are identical.
	if /etc/uboot-helper.sh is-uboot-synchronized && /etc/uboot-helper.sh is-ubootenv-synchronized ; then
		# The return code "0" is interpreted as "true" in shell; it is the "success" value.
		return 0
	else
		# The return code "1" is interpreted as "false" in shell; it is an "error" value.
		return 1
	fi
}

function ensure_bootloaders_functionality() {
	bank_stable="$(fw_printenv -n bank_stable)"

	if /etc/uboot-helper.sh is-secondary-uboot-used ; then
		echo "Primary bootloader corruption detected, attempting recovery!"
		recover_primary_bootloader
	fi

	if [ "${bank_stable}" != "true" ]; then
		# If this branch is executed, this is the first boot after an update.
		# Since this code can only be run after a successful boot, we mark the current bank as stable.
		echo "First boot after a bootloader update successful: set bank_stable = true"
		/etc/uboot-helper.sh unlock
		fw_setenv bank_stable true
		/etc/uboot-helper.sh lock
	fi

	if ! bootloaders_synchronized; then
		echo "Update bootloader backup"
		overwrite_secondary_bootloader
	fi
}

set_bank_revision
initialize_bootloader_recovery
ensure_bootloaders_functionality
