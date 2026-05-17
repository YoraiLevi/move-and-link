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

# 21. Custom cd function with side effects does not corrupt path resolution
it "21. custom cd function with ls side effect does not corrupt src_dir"
d="$(case_dir 21)"; cd "$d"; printf '1\n' > a.txt
cd() { builtin cd "$@" && ls; }
mvln a.txt store/a.txt >/dev/null
rc=$?
unset -f cd
[ "$rc" -eq 0 ] && [ -L a.txt ] && [ "$(readlink a.txt)" = "$d/store/a.txt" ] \
  && ok || fail "custom cd side effect corrupted path resolution (rc=$rc)"

# --- README canonical destination patterns (cases 22-27) ---
# Each case below pins one of the four documented patterns or the rename-vs-nest
# trap. The earlier file/dir cases (1, 2, 3, 14) used same-basename sources and
# therefore could not distinguish "rename" from "nest"; the cases below use
# distinct basenames so the two interpretations produce different paths.

# 22. Pattern 1: file -> exact NEW name (rename during move)
it "22. file -> exact new name renames during move"
d="$(case_dir 22)"; cd "$d"; printf 'hello\n' > a.txt
mvln a.txt store/notes.txt >/dev/null
[ -L a.txt ] && [ -f store/notes.txt ] && [ ! -e store/a.txt ] \
  && [ "$(readlink a.txt)" = "$d/store/notes.txt" ] \
  && [ "$(cat store/notes.txt)" = "hello" ] \
  && ok || fail "rename-to-new-name did not produce store/notes.txt"

# 23. Pattern 3: directory -> exact NEW name in non-existent parent
it "23. dir -> exact new name in non-existent parent renames during move"
d="$(case_dir 23)"; cd "$d"; mkdir src && printf 'y\n' > src/inner
mvln src archive/src-2026 >/dev/null
[ -L src ] && [ -d archive/src-2026 ] && [ ! -e archive/src ] \
  && [ "$(readlink src)" = "$d/archive/src-2026" ] \
  && [ "$(cat src/inner)" = "y" ] \
  && ok || fail "dir rename to new name failed"

# 24. Pattern 4a: directory into existing dir, no trailing slash (nest)
it "24. dir -> existing dir (no trailing slash) nests under basename"
d="$(case_dir 24)"; cd "$d"; mkdir src && printf 'z\n' > src/inner; mkdir bag
mvln src bag >/dev/null
[ -L src ] && [ -d bag/src ] && [ -f bag/src/inner ] \
  && [ "$(readlink src)" = "$d/bag/src" ] \
  && [ "$(cat src/inner)" = "z" ] \
  && ok || fail "dir-into-existing-dir did not nest"

# 25. Pattern 4b: directory into dir via trailing slash (dir absent -> auto-create + nest)
it "25. dir -> trailing-slash dest nests under basename even if dir absent"
d="$(case_dir 25)"; cd "$d"; mkdir src && printf 'w\n' > src/inner
mvln src bag/ >/dev/null
[ -L src ] && [ -d bag/src ] && [ -f bag/src/inner ] \
  && [ "$(readlink src)" = "$d/bag/src" ] \
  && ok || fail "trailing-slash on dir did not auto-create + nest"

# 26a. Rename-vs-nest trap: same command, dest absent -> rename
it "26a. dir -> non-existent target renames to that name (no slash)"
d="$(case_dir 26a)"; cd "$d"; mkdir src && printf 'a\n' > src/inner
mvln src bag >/dev/null
[ -L src ] && [ -d bag ] && [ -f bag/inner ] && [ ! -e bag/src ] \
  && [ "$(readlink src)" = "$d/bag" ] \
  && ok || fail "rename-to-bag did not produce bag/inner"

# 26b. Rename-vs-nest trap: same command, dest present -> nest
it "26b. dir -> existing dir target nests under basename (no slash)"
d="$(case_dir 26b)"; cd "$d"; mkdir src && printf 'b\n' > src/inner; mkdir bag
mvln src bag >/dev/null
[ -L src ] && [ -d bag/src ] && [ -f bag/src/inner ] \
  && [ "$(readlink src)" = "$d/bag/src" ] \
  && ok || fail "nest-into-bag did not produce bag/src/inner"

# 27a. Trailing slash is unambiguous: 'src bag/' nests whether bag exists or not
it "27a. dir -> 'bag/' with bag absent nests after auto-create"
d="$(case_dir 27a)"; cd "$d"; mkdir src && printf 'c\n' > src/inner
mvln src bag/ >/dev/null
[ -L src ] && [ -d bag/src ] && [ -f bag/src/inner ] \
  && ok || fail "trailing-slash + absent did not auto-create + nest"

# 27b. Trailing slash with existing bag also nests
it "27b. dir -> 'bag/' with bag present nests as bag/src"
d="$(case_dir 27b)"; cd "$d"; mkdir src && printf 'd\n' > src/inner; mkdir bag
mvln src bag/ >/dev/null
[ -L src ] && [ -d bag/src ] && [ -f bag/src/inner ] \
  && ok || fail "trailing-slash + present did not nest"

# --- User-typed-syntax cases (28-35) ---
# Shell parity for the pwsh user-syntax tests. POSIX shells have one notion of
# cwd (getcwd) so they don't suffer the pwsh PSDrive-vs-.NET divergence bug,
# but we pin the same syntax surface so neither implementation can drift away
# from the documented user experience without CI catching it.

# 28. (A) Dot-relative source file after cd
it "28. (A) dot-relative source file resolves against shell cwd"
d="$(case_dir 28)"; cd "$d"; printf 'hello\n' > original-file
mvln ./original-file ./dir/ >/dev/null
[ -L original-file ] && [ -f dir/original-file ] \
  && [ "$(cat dir/original-file)" = "hello" ] \
  && ok || fail "dot-relative source did not resolve"

# 29. (A) Dot-relative source directory after cd
it "29. (A) dot-relative source directory resolves against shell cwd"
d="$(case_dir 29)"; cd "$d"; mkdir original-dir && printf 'x\n' > original-dir/inner
mvln ./original-dir ./dir/ >/dev/null
[ -L original-dir ] && [ -d dir/original-dir ] && [ -f dir/original-dir/inner ] \
  && ok || fail "dot-relative source dir did not resolve"

# 30. (B) Bare-name source
it "30. (B) bare-name source resolves against shell cwd"
d="$(case_dir 30)"; cd "$d"; printf 'hello\n' > original-file
mvln original-file dir/ >/dev/null
[ -L original-file ] && [ -f dir/original-file ] \
  && ok || fail "bare-name source did not resolve"

# 31. (C) Skipped on POSIX shells: \ is a literal filename character on Linux/macOS,
# not a path separator. Mixed-separator support is Windows/pwsh-specific.

# 32. (D) Tilde — shell parser-level expansion; not mvln's responsibility. Skipped.

# 33. (E) Parent-directory references
it "33. (E) parent-directory references resolve from shell cwd"
d="$(case_dir 33)"; cd "$d"; printf 'hello\n' > original-file
mkdir subdir; cd subdir
mvln ../original-file ../dir/ >/dev/null
cd "$d"
[ -L original-file ] && [ -f dir/original-file ] \
  && ok || fail "parent-ref did not resolve"

# 34. (F) Absolute source path
it "34. (F) absolute source path works"
d="$(case_dir 34)"; cd "$d"; printf 'hello\n' > original-file
mvln "$d/original-file" "$d/dir/original-file" >/dev/null
[ -L original-file ] && [ -f dir/original-file ] \
  && ok || fail "absolute source did not resolve"

# 35. (G) After navigating away and back, relative resolution still works
it "35. (G) after cd away and back, relative resolution still works"
d="$(case_dir 35)"; cd "$d"; printf 'hello\n' > original-file
cd "$ROOT"
cd "$d"
mvln ./original-file ./dir/ >/dev/null
[ -L original-file ] && [ -f dir/original-file ] \
  && ok || fail "cd-away-then-back did not preserve resolution"
