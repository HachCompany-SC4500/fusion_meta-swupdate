#!/usr/bin/env bash
#
# Copyright (C) 2019 Witekio
# Author: Dragan Cecavac <dcecavac@witekio.com>
#

function report_update_ongoing() {
	echo swupdate-client update is ongoing
	# Display update image waiting for eagle to reboot on top
	# -size 320x240 : force fullscreen
	# -backdrop : centered fullscreen
	display -size 320x240 -backdrop /home/root/images/HACH_UPDATE_320x240.bmp &
	DISPLAY_ONGOING_PID=$!
}

function report_update_failure() {
	echo swupdate-client is stopped, the controller is not rebooted, so update fails

	# Display failure image for 10 seconds on top
	# -size 320x240 : force fullscreen
	# -backdrop : centered fullscreen
	display -size 320x240 -backdrop /home/root/images/HACH_UPDATE_FAILURE_320x240.bmp &
	DISPLAY_FAILURE_PID=$!
	sleep 10
	kill -9 ${DISPLAY_ONGOING_PID}
	kill -9 ${DISPLAY_FAILURE_PID}
}

# Ensure that the update is triggered only after the actual USB stick plug-in
# and not if the controller has been started with the flash drive already
# plugged in.
function ensure_usb_plug_action() {
	usb_dir=`dirname $1`
	usb_base_name=`basename $usb_dir`
	usb_dev=`mount | grep $usb_base_name | cut -d ' ' -f 1`
	usb_dev_timestamp=`date -r $usb_dev +%s`

	rootfs_dev=`mount | grep ' / ' | cut -d ' ' -f 1`
	rootfs_dev_timestamp=`date -r $rootfs_dev +%s`

	timestamp_diff=$(( $usb_dev_timestamp - $rootfs_dev_timestamp ))
	# Compare the creation times of usb_dev (e.g. /dev/sda1) and rootfs_dev (e.g. /dev/mmcblk0p2)
	# Usually they should have roughly the same timestamp
	# and the usb_dev may even have a lower timestamp thus the timestamp_diff may be negative.
	# Based on that, 10 seconds should be more than enough, as timestamp_diff is ~12 seconds
	# at the point of providing user login and ~18 seconds at the point of frontend initialization.
	if [ $timestamp_diff -lt 10 ]; then
		/etc/swupdate-log.sh "Skipping SWUpdate update procedure due to an early detection of USB drive"
		exit 0
	fi
}

bank_stable=`fw_printenv -n bank_stable`
if [[ $bank_stable == "true" ]]; then
	most_recent_swu_image=`ls -rt /media/$1/*swu | tail -n 1`
	swupdate_progress=`systemctl show -p SubState swupdate-progress | cut -d "=" -f 2`
	if [[ -f $most_recent_swu_image ]] && [[ $swupdate_progress == "running" ]]; then
		ensure_usb_plug_action $most_recent_swu_image

		# Restart the progress process to get rid of logs from any previously update which failed.
		# In case that the last log from a previous update was "FAILURE", it would be shown again,
		# which might confuse the user into thinking that the current update has also failed.
		systemctl restart swupdate-progress

		/etc/swupdate-log.sh "####################################################"
		/etc/swupdate-log.sh "# SWUpdate initiated, do not power off the device! #"
		/etc/swupdate-log.sh "####################################################"

		export DISPLAY=:0
		report_update_ongoing
		{ swupdate-client "$most_recent_swu_image" ; renice 0 -p $BASHPID ; report_update_failure ; } &
		sleep 1
		pid=`pgrep -fin swupdate-client`
		if [[ -n "$pid" ]] ; then
			renice -19 -p $pid
		else
			/etc/swupdate-log.sh "Problem detecting swupdate-client pid. Trying to still continue update."
			report_update_failure
			exit 0
		fi
	fi
fi
