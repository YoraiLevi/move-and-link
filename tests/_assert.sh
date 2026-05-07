# Tiny assertion helpers shared by the bash and zsh test runners.
# Sourced, not executed. Works in bash 3.2+ and zsh 5+ under their default options.

_pass=0
_fail=0

it()   { printf '  %s ... ' "$1"; }
ok()   { _pass=$((_pass + 1)); printf 'ok\n'; }
fail() { _fail=$((_fail + 1)); printf 'FAIL\n  reason: %s\n' "$1"; }

# Run a function/command, swallow its output, print its exit code.
catch() { "$@" >/dev/null 2>&1; printf '%s' "$?"; }

summary() {
  printf '\n%d passed, %d failed\n' "$_pass" "$_fail"
  [ "$_fail" -eq 0 ]
}
