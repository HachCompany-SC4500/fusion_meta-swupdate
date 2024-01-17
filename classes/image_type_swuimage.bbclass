LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit swupdate

IMAGE_TYPEDEP_eagle-swupdate += " tar.xz"

DEPENDS += " pseudo-native mtools-native dosfstools-native"
export FAKEROOTENV = "PSEUDO_PREFIX=${STAGING_DIR_NATIVE}${prefix_native} PSEUDO_LOCALSTATEDIR=${PSEUDO_LOCALSTATEDIR} PSEUDO_PASSWD=${PSEUDO_PASSWD} PSEUDO_NOSYMLINKEXP=1 PSEUDO_DISABLED=0"

IMAGE_CMD_swuimage() {
	# Empty placeholder.
	# do_swuimage is auto-triggered, but IMAGE_CMD is still required.
}

SWUPDATE_SIGNING = "RSA"
SWUPDATE_PRIVATE_KEY = "../layers/fusion_meta-swupdate/recipes-support/swupdate/files/priv.pem"
SWUPDATE_PASSWORD_FILE = "../layers/fusion_meta-swupdate/recipes-support/swupdate/files/password"

# images and files that will be included in the .swu image
SWUPDATE_IMAGES = "bootfs.fat.gz"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[bootfs.fat.gz] = "1"

SWUPDATE_IMAGES += "rootfs.ext4.gz"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[rootfs.ext4.gz] = "1"

SWUPDATE_IMAGES += "uEnv-bank-a.img"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[uEnv-bank-a.img] = "1"

SWUPDATE_IMAGES += "uEnv-bank-b.img"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[uEnv-bank-b.img] = "1"

SWUPDATE_IMAGES += "u-boot.imx"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[u-boot.imx] = "1"

SWUPDATE_IMAGES += "u-boot-secondary-header"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[u-boot-secondary-header] = "1"

SWUPDATE_IMAGES += "shellscript.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[shellscript.sh] = "1"

SWUPDATE_IMAGES += "resize2fs"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[resize2fs] = "1"

SWUPDATE_IMAGES += "persistent.tar.xz"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent.tar.xz] = "1"

SWUPDATE_IMAGES += "persistent_init.tar.xz"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent_init.tar.xz] = "1"

SWUPDATE_IMAGES += "persistent-core.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent-core.sh] = "1"

SWUPDATE_IMAGES += "persistent-crypto.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent-crypto.sh] = "1"

SWUPDATE_IMAGES += "persistent-fuse-validate.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent-fuse-validate.sh] = "1"

SWUPDATE_IMAGES += "persistent-mount-both.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent-mount-both.sh] = "1"

SWUPDATE_IMAGES += "persistent-recovery.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[persistent-recovery.sh] = "1"

SWUPDATE_IMAGES += "swupdate-log.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[swupdate-log.sh] = "1"

SWUPDATE_IMAGES += "uboot-helper.sh"
SWUPDATE_IMAGES_NOAPPEND_MACHINE[uboot-helper.sh] = "1"

do_prepare() {
	rm -f ${DEPLOY_DIR_IMAGE}/*.swu
	resource_dir="../layers/fusion_meta-swupdate/recipes-support/images/files"
	swudpate_scripts_dir="../layers/fusion_meta-swupdate/recipes-support/swupdate/files"
	crypto_scripts_dir="../layers/meta-seacloud/recipes-crypto/persistent-crypto/files"

	cp $resource_dir/sw-description ${WORKDIR}

	rootfs_archive_path="$PWD/tmp/work/colibri_imx7_emmc_1370-tdx-linux-gnueabi/${PN}/${PV}*/deploy-${PN}-image-complete/${IMAGE_NAME}.rootfs.tar.xz"
	rootfs_archive=`ls -rt1 ${rootfs_archive_path} | tail -n 1`


	if [ ! -f "${rootfs_archive}" ]; then
		# Fall back to rootfs from DEPLOY_DIR_IMAGE if a more recent one is not available
		rootfs_archive=`ls -rt1 ${DEPLOY_DIR_IMAGE}/*rootfs.tar.xz | tail -n 1`
	fi

	${FAKEROOTENV} pseudo ${resource_dir}/prepare-image-components.sh archive ${rootfs_archive} ${DEPLOY_DIR_IMAGE}
	cp $resource_dir/resize2fs ${DEPLOY_DIR_IMAGE}

	cp $swudpate_scripts_dir/swupdate-log.sh ${DEPLOY_DIR_IMAGE}
	cp $swudpate_scripts_dir/uboot-helper.sh ${DEPLOY_DIR_IMAGE}
	cp $crypto_scripts_dir/persistent-core.sh ${DEPLOY_DIR_IMAGE}
	cp $crypto_scripts_dir/persistent-crypto.sh ${DEPLOY_DIR_IMAGE}
	cp $crypto_scripts_dir/persistent-fuse-validate.sh ${DEPLOY_DIR_IMAGE}
	cp $crypto_scripts_dir/persistent-mount-both.sh ${DEPLOY_DIR_IMAGE}
	cp $crypto_scripts_dir/persistent-recovery.sh ${DEPLOY_DIR_IMAGE}
}

rm_intermediate_images() {
	rm -f ${DEPLOY_DIR_IMAGE}/bootfs.fat.gz
	rm -f ${DEPLOY_DIR_IMAGE}/rootfs.ext4.gz
}

do_swuimage[prefuncs] += "do_prepare"
do_swuimage[postfuncs] += "rm_intermediate_images"
do_swuimage[depends] += "eagle-x11-image:do_image_tar persistent-storage:do_deploy"
