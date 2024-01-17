#!/usr/bin/env bash
#
# Copyright (C) 2020 Witekio
# Author: Dragan Cecavac <dcecavac@witekio.com>
#
# /!\ WARNING: This script is FROZEN!
# It should not be modified anymore as it is here only for compatibility
# purposes. It used to be called by shellscript.sh, embedded in SWU packages,
# but it's not the case anymore. So a modification made to this file won't have
# any effect for packages from the version 0.41, and are likely to break
# downgrade to earlier packages (0.40 and older packages).
# Removing this file will for sure break downgrades to packages 0.40 and below
# and even break the system if attempted. Therefore, it should only be removed
# when official support for packages older than 0.41 is dropped.
#
# Script /etc/swupdate-compatibility.sh has been introduced in order to
# avoid tracking the update versions and it focuses on the changes related
# to the persistent partition. SWUpdate will call this script at a later
# stage of the update procedure, just before syncing the state of the currently
# used persistent partition with the persistent partition of the other bank.
#
# Persistent partition is accessed in a different way compared to bootfs
# and rootfs partitions, because partitions of both partition banks
# have to be accessible during the update procedure, which requires unmounting
# of the currently used persistent partition.
# Depending on the way that persistent partition usage is changed, it is
# expected that this script will also be altered in the future.
#

# set -e not needed for these services
# they might not be started depending on the contents of /media/persistent
systemctl stop EElogger_collect.service
systemctl stop EElogger_receive.service
systemctl stop EElogger_send.service

set -e

# Stop connman before running an update as it is using files on the persistent partition
# when it is running, preventing SWUpdate to unmount /mnt/fcc
if systemctl --quiet is-active connman; then
	systemctl stop connman.service
fi

if grep -qs '/mnt/fcc ' /proc/mounts; then
	umount /mnt/fcc
fi

if grep -qs '/media/passivePersistentPartition ' /proc/mounts; then
	umount /media/passivePersistentPartition
fi

if [ -e /dev/mapper/passivePersistentPartition ]; then
	cryptsetup luksClose /dev/mapper/passivePersistentPartition
fi

if  grep -qs '/media/persistent ' /proc/mounts; then
	umount /media/persistent
fi

if [ -e /dev/mapper/persistent ]; then
	cryptsetup luksClose /dev/mapper/persistent
fi

exit 0
