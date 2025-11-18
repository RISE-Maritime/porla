#!/usr/bin/env bats

load "bats-helpers/bats-support/load"
load "bats-helpers/bats-assert/load"
load "bats-helpers/bats-file/load"

setup_file() {
    REPO_ROOT="$( cd "$( dirname "$BATS_TEST_FILENAME" )"/.. >/dev/null 2>&1 && pwd )"
    docker build -t porla "$REPO_ROOT"
}

teardown_file() {
    (docker image ls -aq | xargs docker rmi) || :
}

setup() {
    REPO_ROOT="$( cd "$( dirname "$BATS_TEST_FILENAME" )"/.. >/dev/null 2>&1 && pwd )"
    TMP_DIR="$(temp_make)"
    cp "$REPO_ROOT"/tests/test.txt "$TMP_DIR"/
}

teardown() {
    (docker ps -aq | xargs docker stop | xargs docker rm) || :
    # Clean up test directory with sudo if needed (historic dir created by container as root)
    rm -rf "$TMP_DIR" 2>/dev/null || sudo rm -rf "$TMP_DIR" || :
}


@test "Single writer/listener pair on bus" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 37 | record /recordings/out.txt"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 37 --ttl 1"

    assert_exists "$TMP_DIR"/out.txt

    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/out.txt

}

@test "Single writer/listener|writer/listener chain on bus" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 37 | record /recordings/out.txt"

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 36 | to_bus 37"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 36"

    assert_exists "$TMP_DIR"/out.txt

    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/out.txt

}

@test "Single writer/two listeners on bus" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 37 | record /recordings/out1.txt"
    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 37 | record /recordings/out2.txt"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 37"

    assert_exists "$TMP_DIR"/out1.txt
    assert_exists "$TMP_DIR"/out2.txt

    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/out1.txt
    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/out2.txt

}

@test "Two writers/single listener on bus" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 37 | record /recordings/out.txt"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 37"
    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 37"

    assert_exists "$TMP_DIR"/out.txt

    # shellcheck disable=SC2002
    no_of_input_lines=$(cat "$TMP_DIR"/test.txt | wc -l)
    # shellcheck disable=SC2002
    no_of_output_lines=$(cat "$TMP_DIR"/out.txt | wc -l)

    assert_equal $(("$no_of_input_lines"*2)) "$no_of_output_lines"

}

@test "Out-of-range bus numbers" {
    bats_require_minimum_version 1.5.0

    run docker run porla "from_bus -1"

    assert_equal "$status" 1  # Should have failed
    assert_output --partial 'Name or service not known'


    run docker run porla "from_bus 256"

    assert_equal "$status" 1  # Should have failed
    assert_output --partial 'Name or service not known'

}

@test "Record function with invalid cron expression" {
    bats_require_minimum_version 1.5.0

    run docker run -v "$TMP_DIR":/recordings --network=host porla "echo 'test' | record /recordings/out.txt --rotate-at 'invalid'"

    assert_equal "$status" 1  # Should have failed
    assert_output --partial 'Error: Invalid cron expression'
    assert_output --partial 'Cron expression must have exactly 5 fields'
}

@test "Record function with valid cron expression creates logrotate config and cronjob" {
    bats_require_minimum_version 1.5.0

    # Run record with rotation, then check the generated config and crontab in the same container
    run docker run -v "$TMP_DIR":/recordings --network=host porla \
        "echo 'test' | record /recordings/test.log --rotate-at '0 0 * * *' --rotate-count 10 --date-format '-%Y-%m-%d' && \
         echo '=== LOGROTATE CONFIG ===' && \
         (cat /etc/logrotate.d/porla-test.log 2>/dev/null || cat /root/.porla/logrotate.d/porla-test.log 2>/dev/null || cat \$HOME/.porla/logrotate.d/porla-test.log) && \
         echo '=== CRONTAB ===' && \
         crontab -l"

    assert_success

    # Check logrotate config content
    assert_output --partial 'rotate 10'
    assert_output --partial 'compress'
    assert_output --partial 'dateext'
    assert_output --partial 'dateyesterday'
    assert_output --partial 'copytruncate'
    assert_output --partial 'olddir historic'
    assert_output --partial 'createolddir 755 root root'
    assert_output --partial 'extension .log'
    assert_output --partial 'dateformat -%Y-%m-%d'

    # Check cronjob was added with the correct cron expression
    assert_output --partial 'logrotate -f'
    assert_output --partial 'porla-test.log'
    assert_output --partial '0 0 * * *'  # Daily cron schedule
}

@test "Record function without rotation works normally" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 38 | record /recordings/normal.txt"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 38 --ttl 1"

    assert_exists "$TMP_DIR"/normal.txt
    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/normal.txt
}

@test "Record function with rotation handles container restart" {
    bats_require_minimum_version 1.5.0

    # First run - setup rotation configuration
    run docker run -v "$TMP_DIR":/recordings --network=host porla \
        "echo 'first run' | record /recordings/restart_test.log --rotate-at '0 0 * * 0' --rotate-count 5"

    assert_success

    # Second run - simulate container restart with same configuration
    # This should succeed and not fail due to existing config
    run docker run -v "$TMP_DIR":/recordings --network=host porla \
        "echo 'second run' | record /recordings/restart_test.log --rotate-at '0 0 * * 0' --rotate-count 5"

    assert_success

    # Verify the log file was written to in both runs
    assert_exists "$TMP_DIR"/restart_test.log

    # Check both lines are in the file
    run grep -c "run" "$TMP_DIR"/restart_test.log
    assert_output "2"
}

@test "Record function with invalid date format" {
    bats_require_minimum_version 1.5.0

    run docker run -v "$TMP_DIR":/recordings --network=host porla "echo 'test' | record /recordings/out.txt --rotate-at '0 0 * * *' --date-format 'no-percent-sign'"

    assert_equal "$status" 1  # Should have failed
    assert_output --partial 'Error: Invalid date format'
    assert_output --partial 'Date format must contain at least one % directive'
}

@test "Record function with file without extension" {
    bats_require_minimum_version 1.5.0

    # Run record with rotation on a file without extension
    run docker run -v "$TMP_DIR":/recordings --network=host porla \
        "echo 'test' | record /recordings/logfile --rotate-at '0 0 * * *' --rotate-count 5 && \
         echo '=== LOGROTATE CONFIG ===' && \
         cat /etc/logrotate.d/porla-logfile"

    assert_success

    # Check logrotate config content - should NOT have extension directive
    assert_output --partial 'rotate 5'
    assert_output --partial 'olddir historic'
    refute_output --partial 'extension'  # Should not have extension directive

    # Verify the file was created
    assert_exists "$TMP_DIR"/logfile
}

@test "Log rotation actually executes via cron every minute" {
    bats_require_minimum_version 1.5.0

    # Start a long-running container with every-minute rotation and custom date format
    docker run -d --name rotation_test -v "$TMP_DIR":/recordings --network=host porla \
        "while true; do echo \"Log entry at \$(date +%s)\"; sleep 1; done | record /recordings/rotation_test.log --rotate-at '* * * * *' --rotate-count 3 --date-format '_%Y%m%d_%H%M'"

    # Give time for cron to start and initial log to be written
    sleep 5

    # Verify initial log file exists and has content
    run docker exec rotation_test sh -c 'test -s /recordings/rotation_test.log'
    assert_success

    # Check that no rotated files exist yet
    run docker exec rotation_test sh -c 'ls /recordings/rotation_test.log-* 2>/dev/null | wc -l'
    assert_success
    assert_output "0"

    echo "Waiting 65 seconds for first rotation to occur..."
    sleep 65

    # Verify historic directory was created
    run docker exec rotation_test sh -c 'test -d /recordings/historic'
    assert_success

    # After one minute, a rotated file should exist in historic directory
    run docker exec rotation_test sh -c 'ls -la /recordings/historic/ && ls /recordings/historic/rotation_test*.log.gz 2>/dev/null | wc -l'
    assert_success
    # Should have at least 1 rotated file
    assert [ "${lines[-1]}" -ge 1 ]

    # Verify the main log file still exists and is being written to
    run docker exec rotation_test sh -c 'test -s /recordings/rotation_test.log'
    assert_success

    # Check that rotated files are compressed and have .log.gz extension (extension preserved)
    run docker exec rotation_test sh -c 'ls /recordings/historic/rotation_test*.log.gz 2>/dev/null | wc -l'
    assert_success
    assert [ "${lines[-1]}" -ge 1 ]

    # Verify main log is still being written and growing
    run docker exec rotation_test sh -c 'tail -1 /recordings/rotation_test.log'
    assert_success
    assert_output --regexp 'Log entry at [0-9]+'

    # Verify rotated files have .log.gz extension (original extension preserved)
    run docker exec rotation_test sh -c 'ls /recordings/historic/rotation_test*.log.gz'
    assert_success
    assert_output --partial '.log.gz'

    # Verify custom date format is used in filename (format: _YYYYMMDD_HHMM)
    run docker exec rotation_test sh -c 'ls /recordings/historic/rotation_test_*.log.gz'
    assert_success
    # Should match pattern: rotation_test_20251118_1145.log.gz (underscore, 8 digits, underscore, 4 digits)
    assert_output --regexp 'rotation_test_[0-9]{8}_[0-9]{4}\.log\.gz'

    # Verify we can decompress and read the rotated file
    run docker exec rotation_test sh -c 'zcat /recordings/historic/rotation_test*.log.gz | head -1'
    assert_success
    assert_output --regexp 'Log entry at [0-9]+'

    # Cleanup
    docker stop rotation_test
    docker rm rotation_test
}
