#!/usr/bin/env bash

set -euo pipefail

function to_bus () {
    socat STDIN "UDP4-DATAGRAM:239.111.42.$1:12737"
}
export to_bus

function from_bus () {
    socat "UDP4-RECV:12737,reuseaddr,ip-add-membership=239.111.42.$1:0.0.0.0" STDOUT
}
export from_bus

function record () {
    tee -a "$1" > /dev/null
}
export record
