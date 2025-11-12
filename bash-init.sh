#!/usr/bin/env bash

set -euo pipefail

echoerr() { echo "$@" 1>&2; }

echoerr "Porla is starting up..."
echoerr "Executing: $BASH_EXECUTION_STRING"

exit() {
    echoerr "Porla is shutting down..."
}

trap exit SIGINT SIGTERM

function to_bus () {
    bus="$1"

    #Read the argument values
    while [ $# -gt 0 ]
    do
        case "$1" in
            --ttl) ttl="$2"; shift;;
            --) shift;;
        esac
        shift;
    done

    socat STDIN "UDP4-DATAGRAM:239.111.42.$bus:12737,ip-multicast-ttl=${ttl:-0}"
}
export to_bus

function from_bus () {
    socat "UDP4-RECV:12737,bind=239.111.42.$1,reuseaddr,ip-add-membership=239.111.42.$1:0.0.0.0" STDOUT
}
export from_bus

function record () {
    local log_path=""
    local rotate_interval=""
    local rotate_count="7"

    # Parse arguments
    log_path="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --rotate-interval)
                rotate_interval="$2"
                shift 2
                ;;
            --rotate-count)
                rotate_count="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # If rotate_interval is specified, configure logrotate and cronjob
    if [ -n "$rotate_interval" ]; then
        # Validate rotate_interval
        case "$rotate_interval" in
            hourly|daily|weekly|monthly)
                # Valid interval
                ;;
            *)
                echoerr "Error: Invalid rotate interval '$rotate_interval'."
                echoerr "Valid intervals are: hourly, daily, weekly, monthly"
                return 1
                ;;
        esac

        # Ensure cron daemon is running
        if ! pgrep -x cron > /dev/null 2>&1; then
            cron
            echoerr "Started cron daemon for log rotation"
        fi

        # Setup logrotate configuration
        local logrotate_conf
        logrotate_conf="/etc/logrotate.d/porla-$(basename "$log_path")"
        local logrotate_conf_content="$log_path {
    $rotate_interval
    rotate $rotate_count
    compress
    dateext          # Use date instead of number for rotated file suffix
    dateyesterday    # Use yesterday's date for the rotated file name
    missingok
    notifempty
    copytruncate     # Copy and truncate original file to avoid breaking open file handles
}"

        # Try to write to /etc/logrotate.d/, fallback to user directory if no permissions
        if [ -w /etc/logrotate.d/ ] 2>/dev/null; then
            echo "$logrotate_conf_content" > "$logrotate_conf"
            echoerr "Logrotate configuration created at $logrotate_conf"
        else
            # Fallback to home directory or /tmp
            local config_dir="${HOME}/.porla/logrotate.d"
            mkdir -p "$config_dir"
            logrotate_conf="$config_dir/porla-$(basename "$log_path")"
            echo "$logrotate_conf_content" > "$logrotate_conf"
            echoerr "Logrotate configuration created at $logrotate_conf (no permissions for /etc/logrotate.d/)"
        fi

        # Setup cronjob - determine schedule based on validated interval
        local cron_schedule=""
        case "$rotate_interval" in
            hourly)
                cron_schedule="0 * * * *"
                ;;
            daily)
                cron_schedule="0 0 * * *"
                ;;
            weekly)
                cron_schedule="0 0 * * 0"
                ;;
            monthly)
                cron_schedule="0 0 1 * *"
                ;;
        esac

        # Check if cron entry already exists
        local cron_cmd="logrotate -f $logrotate_conf"
        if ! crontab -l 2>/dev/null | grep -qF "$cron_cmd"; then
            # Add the cronjob
            (crontab -l 2>/dev/null; echo "$cron_schedule $cron_cmd") | crontab -
            echoerr "Cronjob added: $cron_schedule $cron_cmd"
        else
            echoerr "Cronjob already exists for $log_path"
        fi
    fi

    # Execute the tee command
    tee -a "$log_path" > /dev/null
}
export record
