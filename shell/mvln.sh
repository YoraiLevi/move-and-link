# mvln: move <src> to <dst>, replace <src> with an absolute symlink to <dst>.
# Usage: mvln [-f|--force] [--resolve] [-h|--help] <source> <destination>
# Compatible with bash 3.2+ and zsh 5+ (defaults; no `emulate sh` required).
mvln() {
  # zsh: do not split unquoted vars (matches bash); be explicit, defensive of caller's options.
  if [ -n "${ZSH_VERSION-}" ]; then
    setopt localoptions no_nomatch no_glob_subst sh_word_split 2>/dev/null
  fi

  local force=0 resolve=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      --resolve)  resolve=1; shift ;;
      -h|--help)
        printf '%s\n' \
          'mvln [-f|--force] [--resolve] [--] <source> <destination>' \
          '  Move <source> to <destination>, then replace <source> with an' \
          '  absolute symlink pointing to <destination>.' \
          '  If <destination> is an existing real directory, basename(source) is appended.' \
          '  Refuses if the final destination already exists, unless -f/--force.' \
          '  By default, parent paths are kept logical (symlinks preserved). Pass' \
          '  --resolve to canonicalize through symlinks (pwd -P).' \
          '  Use `--` to separate flags from filenames that begin with `-`.'
        return 0 ;;
      --) shift; break ;;
      -*) printf 'mvln: unknown flag: %s\n' "$1" >&2; return 64 ;;
      *)  break ;;
    esac
  done

  if [ "$#" -ne 2 ]; then
    printf 'usage: mvln [-f|--force] [--resolve] <source> <destination>\n' >&2
    return 64
  fi

  local src="$1" dst="$2"

  # Existence + type check (also catches dangling symlinks via -L).
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    printf 'mvln: source does not exist: %s\n' "$src" >&2
    return 1
  fi
  # Reject special files (FIFO, socket, device, ...): only regular file, dir, or symlink.
  if [ ! -L "$src" ] && [ ! -f "$src" ] && [ ! -d "$src" ]; then
    printf 'mvln: source is not a regular file, directory, or symlink: %s\n' "$src" >&2
    return 1
  fi

  # Strip trailing slashes from src so BSD `mv` does not dereference a symlinked dir.
  while [ "${#src}" -gt 1 ] && [ "${src%/}" != "$src" ]; do src="${src%/}"; done

  # Detect "destination is a container" intent: existing real dir OR trailing slash.
  local dst_trailing=0
  case "$dst" in */) dst_trailing=1 ;; esac
  if [ "$dst_trailing" -eq 1 ] || { [ -d "$dst" ] && [ ! -L "$dst" ]; }; then
    while [ "${#dst}" -gt 1 ] && [ "${dst%/}" != "$dst" ]; do dst="${dst%/}"; done
    dst="$dst/$(basename -- "$src")"
  fi

  # Pick logical (default) or physical (--resolve) absolute-path resolution.
  local pwd_flags=""
  [ "$resolve" -eq 1 ] && pwd_flags="-P"

  local src_dir abs_src
  src_dir="$(builtin cd -- "$(dirname -- "$src")" && pwd $pwd_flags)" \
    || { printf 'mvln: cannot resolve source parent: %s\n' "$src" >&2; return 1; }
  abs_src="$src_dir/$(basename -- "$src")"

  local dst_parent dst_base abs_dst
  dst_parent="$(dirname -- "$dst")"
  dst_base="$(basename -- "$dst")"
  mkdir -p -- "$dst_parent" \
    || { printf 'mvln: cannot create destination parent: %s\n' "$dst_parent" >&2; return 1; }
  dst_parent="$(builtin cd -- "$dst_parent" && pwd $pwd_flags)" \
    || { printf 'mvln: cannot resolve destination parent: %s\n' "$dst" >&2; return 1; }
  abs_dst="$dst_parent/$dst_base"

  # Same-path guard: string equality first; then inode equality if both already exist
  # (catches case-insensitive filesystems on macOS/Windows).
  if [ "$abs_src" = "$abs_dst" ]; then
    printf 'mvln: source and destination are the same: %s\n' "$abs_src" >&2
    return 1
  fi
  if [ -e "$abs_dst" ] && [ -e "$abs_src" ]; then
    local si di
    si="$(ls -dLi -- "$abs_src" 2>/dev/null | awk '{print $1}')"
    di="$(ls -dLi -- "$abs_dst" 2>/dev/null | awk '{print $1}')"
    if [ -n "$si" ] && [ "$si" = "$di" ]; then
      printf 'mvln: source and destination resolve to the same inode: %s\n' "$abs_src" >&2
      return 1
    fi
  fi

  if [ -e "$abs_dst" ] || [ -L "$abs_dst" ]; then
    if [ "$force" -ne 1 ]; then
      printf 'mvln: destination exists: %s (use -f to overwrite)\n' "$abs_dst" >&2
      return 1
    fi
    rm -rf -- "$abs_dst" \
      || { printf 'mvln: failed to remove existing destination: %s\n' "$abs_dst" >&2; return 1; }
  fi

  # Pre-flight: create and remove a sentinel symlink at $src_dir BEFORE moving any data.
  # If symlinks are not permitted on this filesystem / OS, fail with no side effects.
  local probe="$src_dir/.mvln-probe.$$"
  if ! ln -s -- "$abs_dst" "$probe" 2>/dev/null; then
    printf 'mvln: cannot create symlinks at %s; aborting before move\n' "$src_dir" >&2
    return 1
  fi
  rm -f -- "$probe"

  mv -- "$abs_src" "$abs_dst" \
    || { printf 'mvln: mv failed; nothing changed\n' >&2; return 1; }

  # Use `ln -sn` (no-deref). On post-mv race, attempt rollback.
  if ! ln -sn -- "$abs_dst" "$abs_src" 2>/dev/null; then
    if mv -- "$abs_dst" "$abs_src" 2>/dev/null; then
      printf 'mvln: ln failed; rolled back to %s\n' "$abs_src" >&2
    else
      printf 'mvln: ln failed AND rollback failed; data is at %s, source path %s is gone\n' \
        "$abs_dst" "$abs_src" >&2
    fi
    return 1
  fi

  printf 'mvln: %s -> %s\n' "$abs_src" "$abs_dst"
}
