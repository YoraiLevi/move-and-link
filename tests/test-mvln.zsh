#!/usr/bin/env zsh
set -uo pipefail
# Run zsh under its DEFAULT options (no `emulate sh`); mvln itself toggles the bits it
# needs via `setopt localoptions ...`. This audits the function under real zsh defaults.
HERE="$(cd -- "$(dirname -- "$0")" && pwd -P)"
echo "shell: zsh ${ZSH_VERSION}"
SHELL_NAME="zsh"
. "$HERE/_assert.sh"
. "$HERE/../shell/mvln.sh"
. "$HERE/_cases.sh"
summary
rc=$?
exit "$rc"
