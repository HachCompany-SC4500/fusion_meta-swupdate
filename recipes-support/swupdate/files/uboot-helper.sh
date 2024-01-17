#!/usr/bin/env bash

BOOT_BLOCK=mmcblk0boot0

# Boot area size in 512B blocks
eMMC_boot_area_size=$(cat /sys/class/block/${BOOT_BLOCK}/size)

# All sizes and offsets are given in blocks (1 block = 512 Bytes)
UBOOT_SIZE=1024
PRIMARY_UBOOT_OFFSET=2
SECONDARY_UBOOT_OFFSET=$((PRIMARY_UBOOT_OFFSET +  UBOOT_SIZE))

UBOOT_BCB_SIZE=1
UBOOT_ENV_SIZE=16
PRIMARY_UBOOTENV_OFFSET=$((eMMC_boot_area_size - UBOOT_BCB_SIZE - UBOOT_ENV_SIZE))
SECONDARY_UBOOTENV_OFFSET=$((eMMC_boot_area_size - UBOOT_BCB_SIZE - 2*UBOOT_ENV_SIZE))

function bootblock_lock() {
    echo "bootblock_lock(): making the eMMC boot area readonly"
    echo 1 > /sys/block/${BOOT_BLOCK}/force_ro
}

function bootblock_unlock() {
    echo "bootblock_unlock(): making the eMMC boot area writable"
    echo 0 > /sys/block/${BOOT_BLOCK}/force_ro
}

function is_secondary_bootloader_used() {
	src_gpr10="$(devmem2 0x30390098 | cut -d " " -f 7 | tail -n 1)"
	secondary_bootloader_mask=1073741824	#0x40000000
	test_secondary_bootloader=$(( src_gpr10 & secondary_bootloader_mask ))

	if [[ "$test_secondary_bootloader" == "$secondary_bootloader_mask" ]]; then
		# The return code "0" is interpreted as "true" in shell; it is the "success" value.
		return 0
	else
		# The return code "1" is interpreted as "false" in shell; it is an "error" value.
		return 1
	fi
}


CMD=${1}

SUCCESS=0

case ${CMD} in
	get-uboot-primary-offset )
		echo ${PRIMARY_UBOOT_OFFSET}
		;;
	get-uboot-secondary-offset )
		echo ${SECONDARY_UBOOT_OFFSET}
		;;
	get-uboot-size )
		echo ${UBOOT_SIZE}
		;;
	get-ubootenv-primary-offset )
		echo ${PRIMARY_UBOOTENV_OFFSET}
		;;
	get-ubootenv-secondary-offset )
		echo ${SECONDARY_UBOOTENV_OFFSET}
		;;
	get-ubootenv-size )
		echo ${UBOOT_ENV_SIZE}
		;;

	unlock )
		bootblock_unlock
		echo "Boot block unlocked"
		;;
	lock )
		bootblock_lock
		echo "Boot block locked"
		;;
	backup-uboot-primary )
		bootblock_unlock
		dd if=/dev/${BOOT_BLOCK} skip=${PRIMARY_UBOOT_OFFSET} of=/dev/${BOOT_BLOCK} seek=${SECONDARY_UBOOT_OFFSET} count=${UBOOT_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary uboot backuped on secondary" || echo "Fail to backup primary uboot on secondary"
		bootblock_lock
		;;
	backup-ubootenv-primary )
		bootblock_unlock
		dd if=/dev/${BOOT_BLOCK} skip=${PRIMARY_UBOOTENV_OFFSET} of=/dev/${BOOT_BLOCK} seek=${SECONDARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ]  && echo "Primary uboot environment backuped on secondary" || echo "Fail to backup primary uboot environment on secondary"
		bootblock_lock
		;;
	restore-uboot-primary )
		bootblock_unlock
		dd if=/dev/${BOOT_BLOCK} skip=${SECONDARY_UBOOT_OFFSET} of=/dev/${BOOT_BLOCK} seek=${PRIMARY_UBOOT_OFFSET} count=${UBOOT_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary uboot restored from secondary" || echo "Fail to restore primary uboot from secondary"
		bootblock_lock
		;;
	restore-ubootenv-primary )
		bootblock_unlock
		dd if=/dev/${BOOT_BLOCK} skip=${SECONDARY_UBOOTENV_OFFSET} of=/dev/${BOOT_BLOCK} seek=${PRIMARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary uboot environment restored from secondary" || echo "Fail to restore primary uboot environment from secondary"
		bootblock_lock
		;;
	is-uboot-synchronized )
		# Computing sha256 hashes of the primary and secondary uboot images.
		# It is faster that comparing them completely bit-wise.
		primary_uboot_hash=$(dd if=/dev/${BOOT_BLOCK} skip=${PRIMARY_UBOOT_OFFSET} count=${UBOOT_SIZE} 2> /dev/null | sha256sum -b)
		secondary_uboot_hash=$(dd if=/dev/${BOOT_BLOCK} skip=${SECONDARY_UBOOT_OFFSET} count=${UBOOT_SIZE} 2> /dev/null | sha256sum -b)
		[ "$primary_uboot_hash" == "$secondary_uboot_hash" ]
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary and secondary uboot match" || echo "Primary and secondary uboot mismatch !!"
		;;
	is-ubootenv-synchronized )
		# Computing sha256 hashes of the primary and secondary uboot environment images.
		# It is faster that comparing them completely bit-wise.
		primary_ubootenv_hash=$(dd if=/dev/${BOOT_BLOCK} skip=${PRIMARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} 2> /dev/null | sha256sum -b)
		secondary_ubootenv_hash=$(dd if=/dev/${BOOT_BLOCK} skip=${SECONDARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} 2> /dev/null | sha256sum -b)
		[ "$primary_ubootenv_hash" == "$secondary_ubootenv_hash" ]
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary and secondary uboot environments match" || echo "Primary and secondary uboot environments mismatch !!"
		;;
	is-secondary-uboot-used )
		is_secondary_bootloader_used
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Secondary uboot is used" || echo "Primary uboot is used"
		;;
	populate-uboot-env )
		# Populate variables if not already set
		if ! fw_printenv -n bootloader_address_initialized &>/dev/null ; then
			bootblock_unlock
			fw_setenv bootloader_block_count		"$( printf '%#x' ${UBOOT_SIZE} )"
			fw_setenv primary_bootloader_start_block 	"$( printf '%#x' ${PRIMARY_UBOOT_OFFSET} )"
			fw_setenv secondary_bootloader_start_block 	"$( printf '%#x' ${SECONDARY_UBOOT_OFFSET} )"

			fw_setenv environment_block_count		"$( printf '%#x' ${UBOOT_ENV_SIZE} )"
			fw_setenv primary_environment_start_block	"$( printf '%#x' ${PRIMARY_UBOOTENV_OFFSET} )"
			fw_setenv secondary_environment_start_block	"$( printf '%#x' ${SECONDARY_UBOOTENV_OFFSET} )"

			fw_setenv bootloader_address_initialized	"true"
			bootblock_lock
			echo "Uboot environment populated with locations"
		fi
		;;
	write-ubootenv-primary )
		if [ "$#" -eq "2" ]; then
			if [ -f "$2" ]; then
				bootblock_unlock
				dd if="$2" of=/dev/${BOOT_BLOCK} seek=${PRIMARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} && sync
				SUCCESS=$?
				[ $SUCCESS -eq 0 ] && echo "Uboot environment flashed with $2" || echo "Fail to flash uboot environment with $2"
				bootblock_lock
			else
				echo "File '$2' not found to flash uboot environment"
				SUCCESS=1
			fi
		else
			echo "<file> argument missing"
			SUCCESS=1
		fi
		;;

	erase-uboot-primary )
		bootblock_unlock
		dd if=/dev/zero of=/dev/${BOOT_BLOCK} seek=${PRIMARY_UBOOT_OFFSET} count=${UBOOT_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary uboot erased" || echo "Fail to erase primary uboot"
		bootblock_lock
		;;
	erase-uboot-secondary )
		bootblock_unlock
		dd if=/dev/zero of=/dev/${BOOT_BLOCK} seek=${SECONDARY_UBOOT_OFFSET} count=${UBOOT_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Secondary uboot erased" || echo "Fail to erase secondary uboot"
		bootblock_lock
		;;
	erase-ubootenv-primary )
		bootblock_unlock
		dd if=/dev/zero of=/dev/${BOOT_BLOCK} seek=${PRIMARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Primary uboot environment erased" || echo "Fail to erase primary uboot environment"
		bootblock_lock
		;;
	erase-ubootenv-secondary )
		bootblock_unlock
		dd if=/dev/zero of=/dev/${BOOT_BLOCK} seek=${SECONDARY_UBOOTENV_OFFSET} count=${UBOOT_ENV_SIZE} && sync
		SUCCESS=$?
		[ $SUCCESS -eq 0 ] && echo "Secondary uboot environment erased" || echo "Fail to erase secondary uboot environment"
		bootblock_lock
		;;
	* )
		echo "Usage: ${0} <command> [option]"
		echo "<command> can be:"
		echo "Information retrieval commands:"
		echo "get-uboot-primary-offset|get-uboot-secondary-offset: returns the offset of the primary|secondary uboot in blocks of 512Bytes"
		echo "get-uboot-size: returns the size of a uboot in blocks of 512Bytes"
		echo "get-ubootenv-primary-offset|get-ubootenv-secondary-offset: returns the offset of the primary|secondary uboot environment in blocks of 512Bytes"
		echo "get-ubootenv-size: returns the size of a uboot environment in blocks of 512Bytes"
		echo
		echo "Backup/restore commands:"
		echo "lock|unlock: lock|unlock bootblock memory to make it read only|writable respectively"
		echo "backup-uboot-primary|backup-ubootenv-primary: backup primary uboot|environment on secondary"
		echo "restore-uboot-primary|restore-ubootenv-primary: restore primary uboot|environment on secondary"
		echo "is-uboot-synchronized|is-ubootenv-synchronized: check if primary and secondary uboot|environment are synchronized"
		echo "is-secondary-uboot-used: check if the secondary uboot is used"
		echo "populate-uboot-env: populate the uboot environment with primary/secondary uboot and uboot environment locations and size"
		echo "write-ubootenv-primary <file>: write binary image into uboot environment"
		echo
		echo "(WARNING) Test features commands:"
		echo "erase-uboot-primary|erase-uboot-secondary: erase the primary|secondary uboot"
		echo "erase-ubootenv-primary|erase-ubootenv-secondary: erase the primary|secondary uboot environment"
		SUCCESS=1
		;;
esac

exit ${SUCCESS}
