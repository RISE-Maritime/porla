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
    rm -rf "$TMP_DIR"
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

@test "Record function with invalid rotate_interval" {
    bats_require_minimum_version 1.5.0

    run docker run -v "$TMP_DIR":/recordings --network=host porla "echo 'test' | record /recordings/out.txt --rotate-interval invalid"

    assert_equal "$status" 1  # Should have failed
    assert_output --partial 'Error: Invalid rotate interval'
    assert_output --partial 'Valid intervals are: hourly, daily, weekly, monthly'
}

@test "Record function with valid rotate_interval creates logrotate config and cronjob" {
    bats_require_minimum_version 1.5.0

    # Run record with rotation, then check the generated config and crontab in the same container
    run docker run -v "$TMP_DIR":/recordings --network=host porla \
        "echo 'test' | record /recordings/test.log --rotate-interval daily --rotate-count 10 && \
         echo '=== LOGROTATE CONFIG ===' && \
         cat /root/.porla/logrotate.d/porla-test.log && \
         echo '=== CRONTAB ===' && \
         crontab -l"

    assert_success

    # Check logrotate config content
    assert_output --partial 'daily'
    assert_output --partial 'rotate 10'
    assert_output --partial 'compress'
    assert_output --partial 'dateext'
    assert_output --partial 'dateyesterday'
    assert_output --partial 'copytruncate'

    # Check cronjob was added
    assert_output --partial 'logrotate -f'
    assert_output --partial 'porla-test.log'
    assert_output --partial '0 0 * * *'  # Daily cron schedule
}

@test "Record function without rotate_interval works normally" {
    bats_require_minimum_version 1.5.0

    docker run -d -v "$TMP_DIR":/recordings --network=host porla "from_bus 38 | record /recordings/normal.txt"

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 38 --ttl 1"

    assert_exists "$TMP_DIR"/normal.txt
    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/normal.txt
}
