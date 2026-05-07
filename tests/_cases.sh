# Sourced from test-mvln.bash and test-mvln.zsh. Expects: $HERE, $SHELL_NAME,
# `mvln` defined, _assert.sh sourced.

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t "mvln-${SHELL_NAME}.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

case_dir() { local d="$ROOT/case-$1"; mkdir -p "$d"; printf '%s' "$d"; }

# Best-effort cross-fs sandbox setup on Linux.
XFS_ROOT=""
if [ "$(uname -s)" = "Linux" ] && [ -w /dev/shm ]; then
  XFS_ROOT="$(mktemp -d -p /dev/shm "mvln-xfs-${SHELL_NAME}.XXXXXX" 2>/dev/null || true)"
fi

# 1. Move a file
it "1. moves a file and leaves an absolute symlink"
d="$(case_dir 1)"; cd "$d"; printf 'hello\n' > a.txt
mvln a.txt store/a.txt >/dev/null
[ -L a.txt ] && [ "$(cat a.txt)" = "hello" ] && [ "$(readlink a.txt)" = "$d/store/a.txt" ] \
  && ok || fail "post-state wrong"

# 2. Move a directory
it "2. moves a directory and leaves a symlink"
d="$(case_dir 2)"; cd "$d"; mkdir src && printf 'x\n' > src/inner
mvln src store/src >/dev/null
[ -L src ] && [ -d src/ ] && [ "$(cat src/inner)" = "x" ] && ok || fail "dir post-state wrong"

# 3. Destination is existing real directory
it "3. appends basename when dest is an existing dir"
d="$(case_dir 3)"; cd "$d"; printf '1\n' > a.txt; mkdir bag
mvln a.txt bag >/dev/null
[ -L a.txt ] && [ -f bag/a.txt ] && ok || fail "did not append basename"

# 4. Destination parent does not exist
it "4. creates missing destination parent"
d="$(case_dir 4)"; cd "$d"; printf '1\n' > a.txt
mvln a.txt nested/dir/a.txt >/dev/null
[ -L a.txt ] && [ -f nested/dir/a.txt ] && ok || fail "missing parent not created"

# 5. Destination exists, no --force
it "5. refuses existing destination without --force"
d="$(case_dir 5)"; cd "$d"; printf 'orig\n' > a.txt; mkdir store; printf 'in-the-way\n' > store/a.txt
rc=$(catch mvln a.txt store/a.txt)
[ "$rc" -ne 0 ] && [ -f a.txt ] && [ "$(cat store/a.txt)" = "in-the-way" ] \
  && ok || fail "rc=$rc, side effects?"

# 6. Destination exists, --force — also verify symlink target
it "6. overwrites with --force and points symlink at new target"
d="$(case_dir 6)"; cd "$d"; printf 'new\n' > a.txt; mkdir store; printf 'old\n' > store/a.txt
mvln -f a.txt store/a.txt >/dev/null
[ -L a.txt ] && [ "$(cat store/a.txt)" = "new" ] \
  && [ "$(readlink a.txt)" = "$d/store/a.txt" ] \
  && ok || fail "force did not overwrite or target wrong"

# 7. Source does not exist
it "7. fails when source is missing"
d="$(case_dir 7)"; cd "$d"
rc=$(catch mvln nope.txt store/nope.txt)
[ "$rc" -ne 0 ] && [ ! -e store/nope.txt ] && ok || fail "rc=$rc"

# 8. Source canonicalizes to destination
it "8. fails when src and dst are the same path"
d="$(case_dir 8)"; cd "$d"; printf '1\n' > a.txt
rc=$(catch mvln a.txt ./a.txt)
[ "$rc" -ne 0 ] && [ -f a.txt ] && [ ! -L a.txt ] && ok || fail "rc=$rc"

# 9. Source is a symlink — preserve original target string AND new symlink at source.
it "9. relocates a symlink without dereferencing (target preserved)"
d="$(case_dir 9)"; cd "$d"; printf '1\n' > real.txt; ln -s real.txt link.txt
mvln link.txt store/link.txt >/dev/null
[ -L link.txt ] \
  && [ -L store/link.txt ] \
  && [ "$(readlink store/link.txt)" = "real.txt" ] \
  && [ "$(readlink link.txt)" = "$d/store/link.txt" ] \
  && ok || fail "symlink not preserved"

# 10. Write through the resulting symlink
it "10. writes propagate through the symlink to the destination"
d="$(case_dir 10)"; cd "$d"; printf 'before\n' > a.txt
mvln a.txt store/a.txt >/dev/null
printf 'after\n' > a.txt
[ "$(cat store/a.txt)" = "after" ] && ok || fail "write did not propagate"

# 11. --help (must not return 141 even under pipefail)
it "11. prints help on --help and exits 0 (no SIGPIPE)"
rc=$(catch sh -c 'mvln --help | head -n 1')
mvln --help >/dev/null 2>&1
rc2=$?
[ "$rc" -eq 0 ] && [ "$rc2" -eq 0 ] && ok || fail "rc=$rc rc2=$rc2"

# 12. Unknown flag -> 64
it "12. rejects unknown flags with exit 64"
rc=$(catch mvln --bogus a b)
[ "$rc" -eq 64 ] && ok || fail "rc=$rc"

# 13. Symlink target is absolute
it "13. creates an absolute symlink target"
d="$(case_dir 13)"; cd "$d"; printf '1\n' > a.txt
mvln a.txt store/a.txt >/dev/null
target="$(readlink a.txt)"
case "$target" in /*|[A-Z]:*) ok ;; *) fail "target not absolute: $target" ;; esac

# 14. Trailing slash on destination is treated as container
it "14. trailing-slash destination treats it as a container"
d="$(case_dir 14)"; cd "$d"; printf '1\n' > a.txt
mvln a.txt newdir/ >/dev/null
[ -L a.txt ] && [ -f newdir/a.txt ] && ok || fail "trailing slash not handled"

# 15. Trailing slash on source must not dereference a symlinked dir
it "15. trailing-slash source does not dereference symlink-dirs"
d="$(case_dir 15)"; cd "$d"; mkdir realdir && printf 'k\n' > realdir/k
ln -s realdir linkdir
mvln linkdir/ store/linkdir >/dev/null
[ -L linkdir ] && [ -L store/linkdir ] \
  && [ "$(readlink store/linkdir)" = "realdir" ] \
  && ok || fail "src trailing-slash dereferenced the symlink"

# 16. Filenames with leading dash require `--`
it "16. handles filenames that begin with a dash"
d="$(case_dir 16)"; cd "$d"; printf '1\n' > "./-weird.txt"
mvln -- -weird.txt store/-weird.txt >/dev/null
[ -L "./-weird.txt" ] && [ -f "store/-weird.txt" ] && ok || fail "leading-dash file failed"

# 17. Dangling source symlink
it "17. moves a dangling source symlink"
d="$(case_dir 17)"; cd "$d"; ln -s /no/such/path dangling.lnk
mvln dangling.lnk store/dangling.lnk >/dev/null
[ -L dangling.lnk ] && [ -L store/dangling.lnk ] \
  && [ "$(readlink store/dangling.lnk)" = "/no/such/path" ] \
  && ok || fail "dangling symlink not handled"

# 18. Special file (FIFO) is rejected
if command -v mkfifo >/dev/null 2>&1; then
  it "18. rejects FIFO / special files"
  d="$(case_dir 18)"; cd "$d"; mkfifo fifo
  rc=$(catch mvln fifo store/fifo)
  [ "$rc" -ne 0 ] && [ -p fifo ] && ok || fail "rc=$rc, side effects?"
fi

# 19. Logical (default) preserves user-typed parent symlinks
it "19. logical-mode preserves a symlinked parent in the source path"
d="$(case_dir 19)"; cd "$d"; mkdir real
printf '1\n' > real/a.txt
ln -s real link
cd link
mvln a.txt store/a.txt >/dev/null
[ -L "$d/link/a.txt" ] && [ -f "$d/link/store/a.txt" ] && ok || fail "logical resolution wrong"

# 20. Cross-filesystem move on Linux
if [ -n "$XFS_ROOT" ]; then
  it "20. cross-filesystem move (Linux tmpfs)"
  d="$(case_dir 20)"; cd "$d"; printf 'x\n' > big.bin
  mvln big.bin "$XFS_ROOT/big.bin" >/dev/null
  [ -L big.bin ] && [ -f "$XFS_ROOT/big.bin" ] \
    && [ "$(cat big.bin)" = "x" ] \
    && ok || fail "cross-fs move broken"
  rm -rf "$XFS_ROOT"
fi
