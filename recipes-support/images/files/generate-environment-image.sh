#!/usr/bin/env bash
#
# Copyright (C) 2019 Witekio
# Author: Dragan Cecavac <dcecavac@witekio.com>
#
# Usage:
#       ./generate-environment-image.sh DEPLOY_DIR_IMAGE

function die() {
  printf "ERROR: %s" "$*" >&2
  exit 1
}

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
DEPLOY_DIR_IMAGE=$1
uboot_env_txt="${DEPLOY_DIR_IMAGE}/uEnv.txt"
uboot_env_bank_a_txt="${DEPLOY_DIR_IMAGE}/uEnv-bank-a.txt"
uboot_env_bank_b_txt="${DEPLOY_DIR_IMAGE}/uEnv-bank-b.txt"
uboot_env_bank_a_img="${DEPLOY_DIR_IMAGE}/uEnv-bank-a.img"
uboot_env_bank_b_img="${DEPLOY_DIR_IMAGE}/uEnv-bank-b.img"
uboot_env_size=8192

set -e
[ -f "${uboot_env_txt}" ] || die "U-Boot environment not found at ${uboot_env_txt}"
[ -f "${SCRIPTPATH}/mkenvimage" ] || die "mkenvimage executable not found at ${SCRIPTPATH}/mkenvimage"

# Generate two distinct U-Boot environment images with the variable bank_selection set to "a" and "b" respectively.
# We first set the variable to the right value using the replace command of sed (s/.../.../) on the default U-Boot environment
# in two intermediates U-Boot environment files in text format.
sed -e 's/bank_selection=./bank_selection=a/' "${uboot_env_txt}" > "${uboot_env_bank_a_txt}"
sed -e 's/bank_selection=./bank_selection=b/' "${uboot_env_txt}" > "${uboot_env_bank_b_txt}"

# We now generate a binary image for each version of the U-Boot environment prepared above.
"${SCRIPTPATH}/mkenvimage" -s "${uboot_env_size}" -o "${uboot_env_bank_a_img}" "${uboot_env_bank_a_txt}"
"${SCRIPTPATH}/mkenvimage" -s "${uboot_env_size}" -o "${uboot_env_bank_b_img}" "${uboot_env_bank_b_txt}"
