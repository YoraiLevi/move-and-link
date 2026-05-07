#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd -P)"
echo "shell: bash ${BASH_VERSION}"
SHELL_NAME="bash"
. "$HERE/_assert.sh"
. "$HERE/../shell/mvln.sh"
. "$HERE/_cases.sh"
summary
rc=$?
exit "$rc"
