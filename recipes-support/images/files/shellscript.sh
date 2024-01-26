#!/usr/bin/env bash
#
# Copyright (C) 2020 Hach
# Author: Dragan Cecavac <dcecavac>
#

set -e

trap 'system_recover_on_failure' EXIT

active_persistent_name=persistent
active_persistent_path="/media/$active_persistent_name"
passive_persistent_name=passivePersistentPartition
passive_persistent_path="/media/$passive_persistent_name"

current_version_file=/etc/package_num
new_version_file="${active_persistent_path}/system/expected_package_num"

persistent_version_file=''

# this marker allows to detect a sw update result
# and launch post update actions in "update_finalize.sh"
MARKER=/fcc/pdb/CTPKT_NEXTVERSION

# File in which the systemd services stopped during the update are listed
# This allows to restart them at the end of the update in case of a failure
STOPPED_SERVICES=/run/swu_services_to_restart

export LOG_FILE="${active_persistent_path}/fcc/swupdate.log"

# log_buffer_file is defined and exported here so that it's common to all
# sub-scripts. Otherwise, multiple log buffer could be created and it could
# result in lost logs in some cases.
# Logs are first written into this file, and then moved onto the persistent
# partition to survive the update. In case of update failure, they will remain
# available there.
export log_buffer_file=/var/log/swupdate-fail.log

# Don't write logs directly on the passive persistent partition as long as
# it hasn't been sync with the active one.
# Writing logs directly can lead to lost logs when the passive persistent
# partition is mounted when the update starts (written then erased by the sync).
# The call to flush_log_buffer at the very end of the update ensures that the
# logs are saved on the persistent partition before the update ends.
export LOG_AUTOFLUSH=false

source /tmp/swupdate-log.sh
redirect_outputs_to_logs_buffered

function init() {
    # Output an empty line when the script starts to make the logs more readable
    echo ""

    echo "${0}: init(): making embedded scripts executable"
    chmod +x /tmp/persistent-core.sh
    chmod +x /tmp/persistent-fuse-validate.sh
    chmod +x /tmp/persistent-mount-both.sh
    chmod +x /tmp/persistent-recovery.sh
    chmod +x /tmp/uboot-helper.sh
    chmod +x /tmp/resize2fs
}

# Stop services that are likely to interfere with the update
# This is usually necessary when a service makes use of the persistent partition
# as it would prevent SWUpdate to unmount it
function stop_services() {
    list_services="\
        EElogger_collect.service \
        EElogger_receive.service \
        EElogger_send.service \
        modem_configuration_loader.service \
        cellular_data_supervisor.timer \
        cellular_data_supervisor.service \
        wifi_rssi_monitor.timer \
        wifi_rssi_monitor.service \
        wifi_logger.timer \
        wifi_logger.service \
        connection-sharing.service \
        nebula.service \
        connman.service \
        fcc.service \
    "

    for service in $list_services
    do
        if systemctl --quiet is-active "$service"; then
            echo "${0}: stop_services(): stopping $service"
            systemctl stop "$service"
            printf "%s\n" "$service" >> "${STOPPED_SERVICES}"
        fi
    done
}

function free_persistent_partition() {
    partition="$1"

    # Fatalistic error are disabled here to avoid the update to fail because of
    # a volatile process, e.g. a process using the persistent partition that
    # terminate before reaching the kill command (making kill return an error).
    set +e

    kill_processes="$(lsof -t "${partition}")"

    for pid in ${kill_processes}
    do
        echo "${0}: free_persistent_partition(): '$(cat /proc/"${pid}"/comm)' keeps the persistent partition busy, killing it"
        kill -9 "${pid}"
    done

    # Errors are fatal again
    set -e
}

function unmount_pp() {
    mount_point="$1"
    device_name="$2"

    if grep -qs "$mount_point " /proc/mounts; then
        free_persistent_partition "$mount_point"

        echo "${0}: unmount_pp(): unmounting $mount_point"
        umount "$mount_point"
    fi

    if [ -e "/dev/mapper/$device_name" ]; then
        echo "${0}: unmount_pp(): closing the crypto device /dev/mapper/$device_name"
        cryptsetup luksClose "/dev/mapper/$device_name"
    fi
}

function unmount_active_pp() {
    stop_services

    if grep -qs '/mnt/fcc ' /proc/mounts; then
        free_persistent_partition /mnt/fcc

        echo "${0}: unmount_active_pp(): unmount the bind-mount of /mnt/fcc to $active_persistent_path/fcc"
        umount /mnt/fcc
    fi

    unmount_pp "$active_persistent_path" "$active_persistent_name"
}

function unmount_passive_pp() {
    unmount_pp "$passive_persistent_path" "$passive_persistent_name"
}

function unmount_both_pp() {
    unmount_active_pp
    unmount_passive_pp
}

function uboot_env_lock() {
    echo "${0}: uboot_env_lock(): making the bootloader environment readonly"
    /tmp/uboot-helper.sh lock
}

function uboot_env_unlock() {
    echo "${0}: uboot_env_unlock(): making the bootloader environment writable"
    /tmp/uboot-helper.sh unlock
}

function overwrite_secondary_bootloader() {
    # This function copies the primary bootloader, which is assumed to work, over the secondary one.
    # This is to ensure that if a faulty bootloader is flashed during an upgrade, we will still be able
    # to boot using the secondary one, switching back to the old and functional system.
    # As part of the modifications from the ticket FCON2-2264, this process of backuping the primary bootloader
    # is moved in /etc/swupdate-support.sh.
    # As result, this process won't be run here if the version of the current system is 1.23 or newer.

    # Converting the package version to an integer; as shell can only handle integer numbers.
    # At this point, @current_version should be define as it is initialized at the very beginning of @do_preinst().
    # Only the first two numbers that are separated by a "." are taken into account and the next ones
    # are discarded; e.g. "X.Y.Z" becomes "X.Y".
    # This is to ensure that versions number like "X.Y.Z" are not considered higher than "X.W.Z" with Y < W.
    #
    # Here, the first substitution, with "#", finds the superfluous part of a version number.
    # The second, with "%", removes the pattern found with the first subtitution.
    superfluous_version_part="${current_version#[0-9]*.[0-9][0-9]}"
    integer_current_version="${current_version%${superfluous_version_part}}"
    # Forgetting about @superfluous_version_part as it is not necessary anymore.
    unset superfluous_version_part

    # Only the first point is removed (there is only one "/" before the replace pattern) as it should be enough
    # to get an integer; at this point, @integer_current_version should match this pattern: "X.Y", "X" and "Y" being integers.
    integer_current_version="${integer_current_version/./}"

    # Checking that @integer_current_version is indeed an integer.
    case "${integer_current_version}" in
    *[!0-9]* | "")
        # @integer_current_version is not an integer, the currently installed package might be a test package.
        # As it is likely that test packages are based on versions 1.23 and newer, the secondary bootloader overwrite
        # process is skipped in this case.
        # This overwriting process was a safety measure in case the primary bootloader breaks during an update, so
        # it test package based on older versions should still be installable without it.
        ;;
    *)
        # @integer_current_version is an integer.
        if [ "${integer_current_version}" -lt 123 ]; then
            # Backup U-BOOT
            echo "${0}: overwrite_secondary_bootloader(): backing up the current booloader on the secondary bootloader space"
            /tmp/uboot-helper.sh backup-uboot-primary
            # Backup U-BOOT environment
            echo "${0}: overwrite_secondary_bootloader(): backing up the current booloader environment on the secondary bootloader environment space"
            /tmp/uboot-helper.sh backup-ubootenv-primary
        fi
        ;;
    esac
}

function do_persistent_partition_recovery()
{
    unmount_both_pp

    # If the update with corrupted persistent partition is called
    # shortly after the boot, then the service might interfere with the
    # recovery procedure and mount the partition at unexpected point.
    echo "${0}: do_persistent_partition_recovery(): stopping the swupdate-support service (can interfere during an update)"
    systemctl stop swupdate-support.service

    echo "${0}: do_persistent_partition_recovery(): run the script persistent-recovery.sh"
    /tmp/persistent-recovery.sh
}

function do_persistent_partition_sync()
{
    # WARNING: Hardware fuse state validation must be done before we try to
    # determine if persistent partition recovery process is necessary!
    # This is because when a persistent partition recovery process is started
    # with unaccessible fuses, it will unnecessarily destroy all data on the
    # persistent partition.
    echo "${0}: do_persistent_partition_sync(): checking the fuses state"
    /tmp/persistent-fuse-validate.sh

    if ! grep -qs '/media/persistent ' /proc/mounts; then
        echo "${0}: do_persistent_partition_sync(): the active persistent partition is not mounted, running the persistent partition recovery procedure"
        do_persistent_partition_recovery
        unmount_both_pp
    fi

    # Unmount both persistent partitions to allow the raw block device copy below
    unmount_both_pp

    # byte per byte copy from active to passive persistent partition, then sync
    echo "${0}: do_persistent_partition_sync(): copy the currently active persistent partition on the passive persistent partition space"
    dd if=/dev/mmcblk_active_pp of=/dev/mmcblk_hook_pp
    sync

    # Remount active persistent partition and mount the passive one.
    # Mounting the passive pp is necessary for the update logging features.
    echo "${0}: do_persistent_partition_sync(): persistent partitions sync done, mounting both the active and the passive persistent partition"
    /tmp/persistent-mount-both.sh
}

# This function updates the passive permanent partition if a newer version
# is delivered in the swu file
function do_persistent_partition_update()
{
    version_non_defined=-1

    # get persistent partition version of the package to install
    persistent_archive=/tmp/persistent.tar.xz
    new_package_persistent_partition_version=${version_non_defined}
    echo "${0}: do_persistent_partition_update(): reading persistent-version.txt from ${persistent_archive}"
    tar -xf ${persistent_archive} -C /tmp ./persistent-version.txt

    persistent_version_file=/tmp/persistent-version.txt
    read_version=$(getPersistentVersion)
    if [ -n "${read_version}" ]; then
        # version has been successfully read
        new_package_persistent_partition_version="${read_version}"
    fi
    echo "${0}: do_persistent_partition_update(): new package persistent version is ${new_package_persistent_partition_version}"

    # get persistent version of the passive partition
    echo "${0}: do_persistent_partition_update(): reading persistent-version.txt from the passive persistent partition"
    passive_persistent_partition_version=${version_non_defined}
    persistent_version_file=${passive_persistent_path}/persistent-version.txt
    read_version=$(getPersistentVersion)
    if [ -n "${read_version}" ]; then
        # version has been successfully read
	    passive_persistent_partition_version="${read_version}"
    fi
    echo "${0}: do_persistent_partition_update(): passive persistent version is ${passive_persistent_partition_version}"
	
    # if version is less or equal 1.28 remove UVAS file which was put into persistent partition by error
    if [ "${passive_persistent_partition_version}" -le "128" ]; then
       rm -f ${passive_persistent_path}/fcc/prognos/PSC_MID00001_IID00106
    fi

    # update if version of installed package is greater than version of the current version
    # if version is equal to non defined, it means that we need to install the version 0.00
    if [ "${passive_persistent_partition_version}" -eq ${version_non_defined} ] || [ "${new_package_persistent_partition_version}" -gt "${passive_persistent_partition_version}" ]; then
        echo "${0}: do_persistent_partition_update(): updating the passive persistent partition to version ${new_package_persistent_partition_version}"
        tar -xvf ${persistent_archive} -C ${passive_persistent_path}
    else
        # Always copy common files (files useful for probe management)
        echo "${0}: updating the passive persistent partition with common files"
        tar -xf ${persistent_archive} -C ${passive_persistent_path} ./fcc/{drv,prognos,pdb}
    fi

    # Remove unused files:
    # - watchdog_disabled_during_test : temporary used to disable watchdog during validation
    rm -f ${passive_persistent_path}/fcc/watchdog_disabled_during_test

    sync
}

# $1 : marker base path
# $2 : marker update value
function add_update_markers()
{
    marker_file=${1}${MARKER}

    if [[ -f ${marker_file} ]]; then
        echo "update=${2}" >> "${marker_file}"
        echo "${0}: Content of ${marker_file}: $(cat "${marker_file}")"
    else
        echo "${0}: No update marker detected (${marker_file}). Update not triggered via Claros, no sequence response will be sent at the end of update."
    fi
}

function flush_logs_on_both_pp()
{
    flush_log_buffer
    cp -u "${active_persistent_path}/fcc/swupdate.log" "${passive_persistent_path}/fcc/swupdate.log"
}

function do_preinst()
{
    [ -f "${current_version_file}" ] && current_version=$(cat "${current_version_file}") || current_version="unknown version"
    [ -f "${new_version_file}" ]     && new_version=$(cat "${new_version_file}")         || new_version="unknown version"
    echo "${0}: Starting update from ${current_version} to ${new_version}"

    echo "${0}: do_preinst..."

    # This function effectively does something only if the version of the current system is 1.22 or lower.
    # If support for those versions is dropped at some point, this call and the function can eventually be removed.
    # However, it would mean that the extra-safety regarding the bootloader flashing process provided by this function
    # would be lost for end-users still running unsupported versions.
    overwrite_secondary_bootloader

    do_persistent_partition_sync

    do_persistent_partition_update

    echo "${0}: Place error marker on current persistent partition..."
    add_update_markers $active_persistent_path 1
    echo "${0}: Place success marker on next persistent partition..."
    add_update_markers $passive_persistent_path 0

    # Make the bootloader partition writable before completing @do_preinst().
    # This is necessary to let SWUpdate flash the bootloader between the execution
    # of @do_preinst() and @do_postinst().
    uboot_env_unlock

    exit 0
}

function do_postinst()
{
    echo "${0}: do_postinst..."

    # Make the bootloader partition read-only again as the bootloader is flashed at this point.
    uboot_env_lock

    # Older software versions do not include resize2fs tool.
    # Because of this, we provide a pre-compiled resize2fs
    # with SWUpdate image and use it.
    echo "${0}: do_postinst(): resizing the root FS of the system being installed"
    /tmp/resize2fs /dev/mmcblk_hook_rfs
    sync
    
    # Timezone and hostname are not saved anymore in persistent partition, but are directly "copied" into new rootfs using the systemd-firstboot command.
    # The goal is to remove those initialization at startup which are tricky to order.
    # It would have to be launched early because all services rely on them, but the systemd commands used to set hostname and timezone depend on DBus which is not available early ... 
    # Setting it before reboot solves this ordering and speed up the boot
    echo "${0}: do_postinst(): configure timezone and hostname in the new rootfs"
    TEMP_RFS=$(mktemp -dt rfs.XXXXXX)
    mount /dev/mmcblk_hook_rfs "${TEMP_RFS}"
    rm -f "${TEMP_RFS}"/etc/{localtime,hostname}
    systemd-firstboot --root="${TEMP_RFS}" --copy-timezone --hostname=$(hostname -s)
    umount "${TEMP_RFS}"
    rm -r "${TEMP_RFS}"

    # switch active and passive rootfs partition
    echo "${0}: do_postinst(): swapping the active and passive systems"
    cmdline=$(cat /proc/cmdline)

    # update active bank
    if [[ $cmdline == *root=/dev/mmcblk0p2* ]]; then
        bank_selection_current_value=a
        bank_selection_next_value=b
    elif [[ $cmdline == *root=/dev/mmcblk0p4* ]]; then
        bank_selection_current_value=b
        bank_selection_next_value=a
    fi

    echo "${0}: do_postinst(): Write new uboot environment for current bank ${bank_selection_current_value}"
    /tmp/uboot-helper.sh write-ubootenv-primary /tmp/uEnv-bank-${bank_selection_current_value}.img

    echo "${0}: do_postinst(): Initialize the uboot and its environments locations"
    /tmp/uboot-helper.sh populate-uboot-env

    uboot_env_unlock
    echo "${0}: do_postinst(): current system bank is now set to '${bank_selection_next_value}'"
    fw_setenv bank_selection ${bank_selection_next_value}

    # reset uboot env vars until validated after reboot
    echo "${0}: do_postinst(): resetting the boot count in the bootloader environment"
    fw_setenv bank_stable false
    fw_setenv bank_boot_attempt_count 0

    uboot_env_lock

    echo "${0}: do_postinst(): rebooting..."

    # Ensure that all logs are written on both persistent partitions
    flush_logs_on_both_pp

    reboot
    exit 0
}

# This function is intended to bring back the system in a consistent state in
# case of failure update. In order to run it only in case of failure, the test
# against $? must be the first thing it does, as running any command or shell
# builtin would modify the value of $?.
function system_recover_on_failure() {
    if [ "$?" -ne 0 ]
    then
        # The use of "|| true" at the end of the command is to allow the script to
        # continue its execution even if lsof fails.
        lsof_output="$(lsof "${active_persistent_path}" || true)"

        echo "${0}: update failure, putting the system back in nominal state"
        [ -n "${lsof_output}" ] && echo "$(printf "%s: list of processes actively using the persistent partition:\n%s" \
            "${0}" "${lsof_output}")"

        # Restart persistent-crypto.service to ensure the active persistent
        # partition is mounted before turning other services back on.
        echo "${0}: system_recover_on_failure(): restarting persistent-crypto.service; checking/remounting the current persistent partition"
        systemctl restart persistent-crypto.service

        # Restart all the services that were stopped during the update attempt.
        # This allows all the system features to function properly after a failed
        # update without requiring a reboot.
        if [ -f "${STOPPED_SERVICES}" ]
        then
            for service in $(cat "${STOPPED_SERVICES}")
            do
                echo "${0}: system_recover_on_failure(): restarting $service"
                systemctl start "${service}"
            done

            rm -rf "${STOPPED_SERVICES}"
        fi

        # Ensure the passive persistent partition is mounted before trying write logs to it
        /tmp/persistent-mount-both.sh
        flush_logs_on_both_pp

        # Unmount the passive persistent partition to put the system back in nominal state.
        unmount_passive_pp
    fi
}

# This function extracts from a persistent version file (variable persistent_version_file) the version.
# Version is returns without decimal dot to facilitate the comparison
# In case of error, an empty string is returned
function getPersistentVersion() {
    version_read=''
    if [ -f "${persistent_version_file}" ]; then
        version_read=$(grep -e "PERSISTENT_VERSION"  "${persistent_version_file}" | cut -f2 -d "=")
        # Remove decimal dot
        version_read=${version_read//./}
    fi
    echo "${version_read}"
}

init

case "$1" in
preinst)
    do_preinst
    ;;
postinst)
    do_postinst
    ;;
*)
    exit 1
    ;;
esac
