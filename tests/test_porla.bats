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

    docker run -v "$TMP_DIR":/recordings --network=host porla "cat /recordings/test.txt | to_bus 37"

    assert_exists "$TMP_DIR"/out.txt

    assert cmp --silent "$TMP_DIR"/test.txt "$TMP_DIR"/out.txt

}
