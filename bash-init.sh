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
    local rotate_at=""
    local rotate_count="7"
    local date_format="-%Y%m%d"

    # Parse arguments
    log_path="$1"
    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --rotate-at)
                rotate_at="$2"
                shift 2
                ;;
            --rotate-count)
                rotate_count="$2"
                shift 2
                ;;
            --date-format)
                date_format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # If rotate_at is specified, configure logrotate and cronjob
    if [ -n "$rotate_at" ]; then
        # Basic validation of cron expression (should have 5 fields)
        local field_count
        field_count=$(echo "$rotate_at" | awk '{print NF}')
        if [ "$field_count" -ne 5 ]; then
            echoerr "Error: Invalid cron expression '$rotate_at'."
            echoerr "Cron expression must have exactly 5 fields: minute hour day month weekday"
            echoerr "Examples:"
            echoerr "  '0 * * * *'     - Every hour at minute 0"
            echoerr "  '0 0 * * *'     - Daily at midnight"
            echoerr "  '0 0 * * 0'     - Weekly on Sunday at midnight"
            echoerr "  '0 0 1 * *'     - Monthly on the 1st at midnight"
            echoerr "  '*/15 * * * *'  - Every 15 minutes"
            return 1
        fi

        # Validate date format contains at least one % character
        if [[ ! "$date_format" =~ % ]]; then
            echoerr "Error: Invalid date format '$date_format'."
            echoerr "Date format must contain at least one % directive (strftime format)"
            echoerr "Examples:"
            echoerr "  '-%Y%m%d'        - Default: -20251118"
            echoerr "  '-%Y-%m-%d'      - With dashes: -2025-11-18"
            echoerr "  '-%Y%m%d-%H%M%S' - With time: -20251118-143025"
            return 1
        fi

        # Ensure cron daemon is running
        if ! pgrep -x cron > /dev/null 2>&1; then
            # Create necessary directories for cron
            mkdir -p /var/run
            mkdir -p /var/spool/cron/crontabs
            chmod 1730 /var/spool/cron/crontabs 2>/dev/null || true

            # Create pid file if it doesn't exist
            touch /var/run/crond.pid 2>/dev/null || true

            # Start cron daemon
            if cron 2>/dev/null; then
                # Give cron a moment to initialize
                sleep 0.5
                if pgrep -x cron > /dev/null 2>&1; then
                    echoerr "Started cron daemon for log rotation"
                else
                    echoerr "Warning: Cron daemon started but may not be running properly"
                fi
            else
                echoerr "Warning: Failed to start cron daemon. Log rotation will not be automated."
            fi
        fi

        # Setup logrotate configuration
        local logrotate_conf
        logrotate_conf="/etc/logrotate.d/porla-$(basename "$log_path")"

        # Extract file extension for preservation
        local filename
        filename=$(basename "$log_path")
        local extension=""
        if [[ "$filename" == *.* ]]; then
            extension=".${filename##*.}"
        fi

        local logrotate_conf_content="$log_path {
    su root root
    olddir historic
    createolddir 755 root root"

        # Add extension directive if file has an extension
        if [ -n "$extension" ]; then
            logrotate_conf_content="$logrotate_conf_content
    extension $extension"
        fi

        logrotate_conf_content="$logrotate_conf_content
    dateformat $date_format
    rotate $rotate_count
    compress
    dateext
    dateyesterday
    missingok
    notifempty
    copytruncate
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

        # Setup cronjob - only if cron daemon is running
        if pgrep -x cron > /dev/null 2>&1; then
            local cron_cmd="/usr/sbin/logrotate -f $logrotate_conf"
            local crontab_file="/var/spool/cron/crontabs/root"
            local cron_entry="$rotate_at $cron_cmd"

            # Check if cron entry already exists
            if [ -f "$crontab_file" ] && grep -qF "$cron_cmd" "$crontab_file" 2>/dev/null; then
                echoerr "Cronjob already exists for $log_path"
            else
                # Add the cronjob by writing directly to crontab file
                mkdir -p "$(dirname "$crontab_file")"
                echo "$cron_entry" >> "$crontab_file"
                chmod 0600 "$crontab_file"
                echoerr "Cronjob added: $cron_entry"

                # Restart cron daemon to pick up the new crontab
                # HUP signal is not sufficient when cron is started before crontab file exists
                if pkill cron 2>/dev/null && sleep 0.5 && cron 2>/dev/null; then
                    echoerr "Cron daemon restarted to apply new configuration"
                else
                    echoerr "Warning: Could not restart cron daemon. Changes may not take effect until container restart."
                fi
            fi
        else
            echoerr "Warning: Cron daemon not running. Log rotation will not be automated."
            echoerr "You can manually rotate logs with: logrotate -f $logrotate_conf"
        fi
    fi

    # Execute the tee command
    tee -a "$log_path" > /dev/null
}
export record
