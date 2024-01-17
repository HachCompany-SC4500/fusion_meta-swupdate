#!/bin/sh

set -eu

# if no value for SESAME_SCRIPT_PATH is defined in the environment, defaults
# to 'sesame_scripts/grant_access.sh'
SESAME_SCRIPT_PATH="${SESAME_SCRIPT_PATH:-sesame_scripts/grant_access.sh}"

clean() {
    if [ -d "${tmpdir}" ]
    then
        rm -rf "${tmpdir}"
    fi
}

usage() {
    retval="$1"
    message="${2:-}"

    if [ "${retval}" -eq 0 ]
    then
        exec 3>&1
    else
        exec 3>&2
    fi

    command_name="$(basename "$0")"
    printf "\
Usage: %s -t SOM_SERIAL -e EXPIRY_DATE [-u USER] [-p PUBKEY_FILE]
           [-s SIGNKEY_FILE] [-S PASSWORD_FILE] [-o SESAME_NAME]
       %s -h

Order of arguments does not matter.
The arguments shown above between brackets are optional.

  -t SOM_SERIAL    serial number of the SoM installed in the targeted controller
                   The sesame key will work only on the controller for which its
                   SoM matches SOM_SERIAL
  -e EXPIRY_DATE   date after which the key is not expected to have any effect
                   The recommended date format is the following: YYYY-MM-DD
                   (e.g. 2020-08-13). The inputs '1 week[s]', '6 month[s]' and
                   '2 year[s]' might be accepted though
  -u USER          system user on the controller for which access will be opened
                   through the serial console, as well as over SSH if a public
                   key PUBKEY_FILE is provided
                   defaults to the user 'root'
  -p PUBKEY_FILE   if specified, the owner of the SSH public key PUBKEY_FILE will
                   be allowed to access the controller system over SSH, as USER
  -s SIGNKEY_FILE  private key used to sign the generated swu image file
                   currently defaults to the path of the key in this Yocto
                   recipe: ../../recipes-support/swupdate/files/priv.pem
  -S PASSWORD_FILE if SIGNKEY_FILE is encrypted: file containing the password
                   needed to decrypt it
                   If no password file is provided and yet SIGNKEY_FILE is
                   encrypted, a prompt will demand to input the password
                   currently defaults to the path of the key password in this
                   Yocto recipe: ../../recipes-support/swupdate/files/password
  -o SESAME_NAME   name of the generated Sesame key or directory in which it
                   must be created
  -h               display this help message

An exemple of usage: ./gen_sesame_key.sh -t 06475998 -u root -p /home/sandrine/id_rsa.pub -e '2 month' -s ../../recipes-support/swupdate/files/priv.pem -S ../../recipes-support/swupdate/files/password -o Sandrine-device

" "${command_name}" "${command_name}" >&3

    if [ -n "${message}" ]
    then
        printf "\ninput error: %s\n" "${message}" >&3
    fi

    exit "${retval}"
}

check_args() {
    [ -f "${SESAME_SCRIPT_PATH}" ] || usage 1 "cannot find Sesame script"

    # Setting default values for the private key and its password according to
    # their current location in the Yocto recipe
    # WARNING: they are supposed to be replaced and stored in a secure location
    # when Eagle devices will be launch for production
    if [ ! -n "${signkey_file:+x}" ]
    then
        signkey_file="../../recipes-support/swupdate/files/priv.pem"
        passkey_file="../../recipes-support/swupdate/files/password"
    fi

    [ -n "${som_serial:+x}" ]    || usage 1 "SOM_SERIAL not specified"
    [ -n "${signkey_file:+x}" ]  || usage 1 "SIGNKEY_FILE not specified"
    [ -f "${signkey_file}" ]     || usage 1 "'${signkey_file}' does not exist"
    [ -n "${user:+x}" ]          || usage 1 "USER not specified"
    [ -n "${expiry_date:+x}" ]   || usage 1 "EXPIRY_DATE not specified"

    if [ -n "${pubkey_file}" ] && [ ! -f "${pubkey_file}" ]
    then
        usage 1 "'${pubkey_file}' does not exist"
    fi

    if [ -n "${passkey_file}" ] && [ ! -f "${passkey_file}" ]
    then
        usage 1 "'${passkey_file}' does not exist"
    fi
}

parse_args() {
    # optional arguments get default value
    passkey_file=""
    pubkey_file=""
    user="root"

    while getopts he:o:p:s:S:t:u: arg
    do
        case "${arg}" in
        "h" ) usage 0;;
        "e" ) expiry_date="$(date --date="${OPTARG}" +%Y%m%d)";;
        "o" ) sesame_name="${OPTARG}";;
        "p" ) pubkey_file="${OPTARG}";;
        "s" ) signkey_file="${OPTARG}";;
        "S" ) passkey_file="${OPTARG}";;
        "t" ) som_serial="${OPTARG}";;
        "u" ) user="${OPTARG}";;
         *  ) usage 1;;
        esac
    done

    check_args
}

prepare_tmpdir() {
    tmpdir=$(mktemp -d)
    cp "${SESAME_SCRIPT_PATH}" "${tmpdir}/"

    if [ -n "${pubkey_file}" ]
    then
        cp "${pubkey_file}" "${tmpdir}/ssh_key.pub"
    fi
}

gen_sw_description() {
    script_name="$(basename "${SESAME_SCRIPT_PATH}")"
    script_parameters="'${som_serial}' '${user}' '${expiry_date}'"

    if [ -n "${pubkey_file}" ]
    then
        keyname_tmpsuffix="$(hexdump -e '"%02x"' -n 8 /dev/urandom)"
        pubkey_on_device="/tmp/ssh_key-${keyname_tmpsuffix}.pub"
        script_parameters="${script_parameters} '${pubkey_on_device}'"
    fi

    cat << EOF > "${tmpdir}/sw-description"
software =
{
        description = "unlock-key";
        version = "9999.99";
        hardware-compatibility: ["1.0"];

        scripts: (
                {
                        filename = "${script_name}";
                        type = "postinstall";
                        sha256 = "$(sha256sum "${tmpdir}/${script_name}" | \
                            cut -f 1 -d ' ')";
                        data = "${script_parameters}";
                }
        );
EOF

    if [ -n "${pubkey_file}" ]
    then
        cat << EOF >> "${tmpdir}/sw-description"

        files: (
                {
                        filename = "ssh_key.pub";
                        sha256 = "$(sha256sum "${pubkey_file}" | \
                            cut -f 1 -d ' ')";
                        path = "${pubkey_on_device}";
                }
        );
EOF
    fi

    echo "}" >> "${tmpdir}/sw-description"
}

gen_sesame_file() {
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


    script_name="$(basename "${SESAME_SCRIPT_PATH}")"
    cd ${tmpdir}
    printf "sw-description\nsw-description.sig\n%s\n%s" \
        "${script_name}" "${pubkey_file:+ssh_key.pub}" | \
        cpio -ov -H crc > "${tmpdir}/unlock.swu" 
    cd -
}

new_sesame_file() {
    parse_args "$@"

    gen_sesame_file

    sesame_name="${sesame_name:-unlock_${user}_for_${som_serial}_usebefore_${expiry_date}.swu}"
    if [ -d "${sesame_name}" ]
    then
        sesame_name="${sesame_name}/unlock_${user}_for_${som_serial}_usebefore_${expiry_date}.swu"
    fi
    sesame_name="${sesame_name%.swu}.swu"

    mv -i "${tmpdir}/unlock.swu" "${sesame_name}"
    clean

    printf "New Sesame file generated: %s\n" "${sesame_name}"
}

new_sesame_file "$@"
