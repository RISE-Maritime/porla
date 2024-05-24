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
    tee -a "$1" > /dev/null
}
export record
