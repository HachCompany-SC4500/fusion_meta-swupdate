#!/usr/bin/env bash
#
# Copyright (C) 2019 Witekio
# Author: Dragan Cecavac <dcecavac>
#
# Usage:
#       ./prepare-image-components.sh input_type rootfs_input DEPLOY_DIR_IMAGE
#			input_type may be "directory" or "archive"
#				in case of directory input rootfs_input is the directory containing the rootfs
#				in case of archive input rootfs_input is the archive containing the rootfs

input_type=$1
rootfs_input=$2
DEPLOY_DIR_IMAGE=$3
PATH=$PATH/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

bootfs_elements=("imx7d-colibri-emmc-eval-v3.dtb" "imx7d-colibri-emmc-aster.dtb" "imx7d-colibri-emmc-1370.dtb" "zImage")
bootfs_img=bootfs.fat
rootfs_dir=rootfs-tmp
rootfs_img=rootfs.ext4
uenv=uEnv.txt

function die() {
	echo "ERROR: $@" >&2
	exit 1
}

function check_required_files() {
	for element in "${bootfs_elements[@]}"; do
		[ -L "$element" ] || die "Bootfs image component link \"${element}\" not found"
		[ -e "$element" ] || die "Bootfs image component \"${element}\" is a broken link"
	done

	[ -L "$uenv" ] || die "U-Boot environment link \"${element}\" not found"
	[ -e "$uenv" ] || die "U-Boot environment \"${element}\" is a broken link"

	[ -f "${SCRIPTPATH}/generate-environment-image.sh" ] || die "generate-environment-image.sh script not found at $SCRIPTPATH/"
	[ -f "${SCRIPTPATH}/make_ext4fs" ] || die "make_ext4fs executable not found at $SCRIPTPATH/"
}

function generate_bootfs_image() {
	dd if=/dev/zero of=${bootfs_img} count=16 bs=1M
	mkfs.vfat ${bootfs_img}

	for element in "${bootfs_elements[@]}"; do
		mcopy -i ${bootfs_img} ${element} ::
	done

	gzip -f ${bootfs_img}
}

function generate_rootfs_image_from_dir() {
	${SCRIPTPATH}/make_ext4fs -l 1788M ${rootfs_img} ${rootfs_input} -o
	resize2fs -M ${rootfs_img}
	gzip -f ${rootfs_img}
}

function generate_rootfs_image_from_archive() {
	mkdir -p ${rootfs_dir}
	tar xf ${rootfs_input} -C ${rootfs_dir}

	${SCRIPTPATH}/make_ext4fs -l 1788M ${rootfs_img} ${rootfs_dir} -o
	resize2fs -M ${rootfs_img}
	gzip -f ${rootfs_img}

	rm -rf ${rootfs_dir}
}

function generate_rootfs_image() {
	if [[ ${input_type} == "directory" ]]; then
		generate_rootfs_image_from_dir
	elif [[ ${input_type} == "archive" ]]; then
		generate_rootfs_image_from_archive
	else
		die "input_type should be \"directory\" or \"archive\""
	fi
}

set -e
cd ${DEPLOY_DIR_IMAGE}

check_required_files

cp ${SCRIPTPATH}/shellscript.sh ${DEPLOY_DIR_IMAGE}
${SCRIPTPATH}/generate-environment-image.sh ${DEPLOY_DIR_IMAGE}
generate_bootfs_image
generate_rootfs_image
