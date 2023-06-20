#!/bin/bash

# Install python dependencies
pip3 install --user -r requirements_dev.txt

# Install bats helpers
[ -d tests/bats-helpers ] && rm -rf tests/bats-helpers && mkdir -p tests/bats-helpers

git clone --depth 1 https://github.com/bats-core/bats-support.git tests/bats-helpers/bats-support || true
git clone --depth 1 https://github.com/bats-core/bats-assert.git tests/bats-helpers/bats-assert || true
git clone --depth 1 https://github.com/bats-core/bats-file.git tests/bats-helpers/bats-file || true