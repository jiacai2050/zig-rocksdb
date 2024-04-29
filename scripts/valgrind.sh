#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT
cleanup() {
 trap - SIGINT SIGTERM ERR EXIT
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

cd "${script_dir}/.."

BINS=("./zig-out/bin/basic" "./zig-out/bin/cf")
for bin in ${BINS[@]}; do
  valgrind --leak-check=full --tool=memcheck \
           --show-leak-kinds=definite,possible --error-exitcode=1 ${bin}
done
