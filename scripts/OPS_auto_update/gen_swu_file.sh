#!/bin/sh

set -eu

AUTO_UPDATE_SCRIPT_PATH="${AUTO_UPDATE_SCRIPT_PATH:-gen_ops_autoupdate.sh}"
IMAGES_PATH="${IMAGES_PATH:-images}"
signkey_file="../../recipes-support/swupdate/files/priv.pem"
passkey_file="../../recipes-support/swupdate/files/password"

clean() {
    if [ -d "${tmpdir}" ]
    then
        rm -rf "${tmpdir}"
    fi
}

prepare_tmpdir() {
    tmpdir=$(mktemp -d)
    cp "${AUTO_UPDATE_SCRIPT_PATH}" "${tmpdir}/"
    cp -R ${IMAGES_PATH}/* "${tmpdir}/"
}

gen_sw_description() {
    script_name="$(basename "${AUTO_UPDATE_SCRIPT_PATH}")"
    cat << EOF > "${tmpdir}/sw-description"
software =
{
        description = "unlock-key";
        version = "9999.99";
        hardware-compatibility: ["1.0"];

        scripts: (
            {
                    filename = "${script_name}";
                    type = "preinstall";
                    sha256 = "$(sha256sum "${tmpdir}/${script_name}" | \
                        cut -f 1 -d ' ')";
            }
        );
        files: (
            {
                    filename = "HACH_UPDATE_FILE_COPYING_320x240.bmp";
                    sha256 = "$(sha256sum "${tmpdir}/HACH_UPDATE_FILE_COPYING_320x240.bmp" | \
                            cut -f 1 -d ' ')";
                    path = "/tmp/HACH_UPDATE_FILE_COPYING_320x240.bmp";
            },
            {
                    filename = "HACH_USB_UPDATE_320x240.bmp";
                    sha256 = "$(sha256sum "${tmpdir}/HACH_USB_UPDATE_320x240.bmp" | \
                            cut -f 1 -d ' ')";
                    path = "/tmp/HACH_USB_UPDATE_320x240.bmp";
            },
            {
                    filename = "HACH_UP_TO_DATE_320x240.bmp";
                    sha256 = "$(sha256sum "${tmpdir}/HACH_UP_TO_DATE_320x240.bmp" | \
                            cut -f 1 -d ' ')";
                    path = "/tmp/HACH_UP_TO_DATE_320x240.bmp";
            }
        );
}     
EOF
}

gen_auto_update_file() {
    prepare_tmpdir
    gen_sw_description

    if [ -f "${passkey_file}" ]
    then
        openssl dgst -sha256 -sign "${signkey_file}" \
            -passin file:"${passkey_file}" \
            -out "${tmpdir}/sw-description.sig" "${tmpdir}/sw-description"
    else
        openssl dgst -sha256 -sign "${signkey_file}" \
            -out "${tmpdir}/sw-description.sig" "${tmpdir}/sw-description"
    fi

    script_name="$(basename "${AUTO_UPDATE_SCRIPT_PATH}")"
    FILES="sw-description sw-description.sig ${script_name} HACH_UPDATE_FILE_COPYING_320x240.bmp HACH_USB_UPDATE_320x240.bmp HACH_UP_TO_DATE_320x240.bmp"
    cd ${tmpdir}
    for i in $FILES;do
        echo $i;done | \
        cpio -ov -H crc > "${tmpdir}/unlock.swu" 
    cd -
}

new_auto_update_file() {
    gen_auto_update_file
    auto_update_name="${auto_update_name:-auto_update.swu}"
    if [ -d "${auto_update_name}" ]
    then
        auto_update_name="${auto_update_name}/auto_update.swu"
    fi
    auto_update_name="${auto_update_name%.swu}.swu"
    mv -i "${tmpdir}/unlock.swu" "${auto_update_name}"
    clean
    printf "New auto_update file generated: %s\n" "${auto_update_name}"
}

new_auto_update_file "$@"