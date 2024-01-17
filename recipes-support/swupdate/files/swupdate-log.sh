#!/usr/bin/env bash
#
# Copyright (C) 2019 Witekio
# Author: Dragan Cecavac <dcecavac@witekio.com>
#

log_buffer_file="${log_buffer_file:-$(mktemp)}"
LOG_FILE="${LOG_FILE:-/media/persistent/fcc/swupdate.log}"
LOG_AUTOFLUSH="${LOG_AUTOFLUSH:-true}"
# Specify the maximum size the log file is allowed to reach; at no time should
# the log file ${LOG_FILE} exceed this limit.
LOG_MAX_FILESIZE="${LOG_MAX_FILESIZE:-$((512 * 1024))}" # 512 kiB by default

# $1 : log processing function called with the logs as parameter
function redirect_outputs()
{
    # Here we are redirecting stdout and stderr into a background process that manages logs (using "exec" and process substitution ">(command)" )
    # The side effect is that this background process is asynchrone and could end after the main process
    # To fix that point, we add also a cleanup function to be sure all logs are processed before the end of the main script

    # Backup current stdout and stderr file descriptors
    exec 8>&1 9>&2
    # Using process substitution, redirect stdout and stderr as input of a background logs processing loop (create an anonymous pipe) that calls $1 function to process the logs
    exec 1> >(while IFS= read line; do "$1" "$line"; done ) 2>&1
    # Keep background process PID in order to wait end of log processing at the end of the script execution
    LOG_PID=$!

    # Add a cleanup function called when script exits
    function cleanup()
    {
        # Remove redirection to release one end of the anonymous pipe. Next read will return a EOF to the background process that will exit
        exec 1>&8 2>&9
        # Now, we wait the end of the background process after all the logs have been processed
        wait $LOG_PID
    }
    trap cleanup EXIT
}

function redirect_outputs_to_logs()
{
    redirect_outputs swupdate_log
}

function redirect_outputs_to_logs_buffered()
{
    redirect_outputs buffered_log
}

# print the provided string on the system console
function swupdate_log() {
    logger -- "$1"
    echo "$1" > /dev/ttymxc0
}

# buffered_log writes the log directly to $LOG_FILE if its file system is
# mounted and if LOG_AUTOFLUSH is set to "true".
# Otherwise it stores it to a buffer which will be written in $LOG_FILE at
# a later stage when @flush_log_buffer is called.
#
# In extreme cases persistent partition will not contain fcc directory
# until we untar the persistent archive. To avoid such issues the log
# is temporarily stored in log_buffer.
function buffered_log() {
    local log_message=""

    # Print the date only if the log is not empty, it allows to print empty lines
    if [ -n "$1" ]; then
        log_message="$(date "+%F %T"): $1"
    fi

    # print logs on the console in addition to write them in the file $LOG_FILE
    swupdate_log "$log_message"

    printf "%s\n" "$log_message" >> "$log_buffer_file"

    if "$LOG_AUTOFLUSH"; then
        flush_log_buffer
    fi
}

function flush_log_buffer() {
    if [ -f "${log_buffer_file}" ] && [ -d "$(dirname "${LOG_FILE}")" ]; then
        [ -f "${LOG_FILE}" ] && log_file_size="$(wc -c < "${LOG_FILE}")" || log_file_size=0
        log_buffer_size="$(wc -c < "${log_buffer_file}")"

        if [ "$((log_file_size + log_buffer_size))" -le "${LOG_MAX_FILESIZE}" ]; then
            # The content of the current log file and the log buffer together fits in ${LOG_MAX_FILESIZE} bytes.
            # In this case, the content of the log buffer is first copied at the end of the log file and it is
            # emptied; ":" means no-op.
            #
            # The commands are linked with the "&&" operator to ensure that no logs are lost in case the
            # copy from the log buffer to the log file fails.
            cat "${log_buffer_file}" >> "${LOG_FILE}" && \
                : > "${log_buffer_file}"
        else
            # The content of the current log file and the log buffer together doesn't fit in "${LOG_MAX_FILESIZE} bytes.
            # In this case, we discard just enough logs so that the log file size becomes lower than the half of
            # ${LOG_MAX_FILESIZE} by concatenating ${LOG_FILE} and ${log_buffer_file} together and limitting the output
            # size to (${LOG_MAX_FILESIZE} / 2) with tail.
            # As the first line is likely to be incomplete, it is also discarded with a subsequent tail command.
            # All of this is put in a temporary file before putting it back to ${LOG_FILE}; reading and writing
            # to a file with the same command is not safe. "cat" with shell redirection is used to copy the logs
            # back in ${LOG_FILE} so that it internally remains the same file; i.e. its inode remains the same.
            # The log buffer is finally emptied: ":" means no-op.
            #
            # As above, the commands are linked with the "&&" operator to ensure that in case of a failure in any of
            # them, the commands after the failed one are not run to avoid log loss.
            temp_file="$(mktemp)"

            cat "${LOG_FILE}" "${log_buffer_file}" | tail -c "$((LOG_MAX_FILESIZE / 2))" | tail -n +2 > "${temp_file}" && \
                cat "${temp_file}" > "${LOG_FILE}" && \
                : > "${log_buffer_file}"

            rm -f -- "${temp_file}"
        fi
    fi
}

# If the script is called with an argument, print it on the system console
# This ensures that processes that calls it like '/etc/swupdate_log.sh "log to print"'
# still output their logs properly
if [ -n "$1" ]; then
    swupdate_log "$1"
fi
