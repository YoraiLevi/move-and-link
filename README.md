# move-and-link

[![test](https://github.com/YoraiLevi/move-and-link/actions/workflows/test.yml/badge.svg)](https://github.com/YoraiLevi/move-and-link/actions/workflows/test.yml)

Move a file or directory off your fast/small disk onto bulk storage, and leave a symlink behind so every program, shortcut, and config file keeps finding it at the original path. **mvln** (move-and-link) is a small bash/zsh function and an equivalent PowerShell function — no daemon, no config, no dependency beyond your shell.

The classic use case: free up SSD space without re-installing your apps. The same pattern works for `node_modules` on a scratch disk, ML caches on a bulk drive, dotfiles in a git repo, Docker volumes on a faster mount, and so on. See [Examples](#examples) below.

## Bash / Zsh

Source `shell/mvln.sh` from your `~/.bashrc` or `~/.zshrc`. Manual install:

    mkdir -p ~/.local/share
    curl -fsSL https://raw.githubusercontent.com/YoraiLevi/move-and-link/main/shell/mvln.sh \
      -o ~/.local/share/mvln.sh

Then add this line to `~/.bashrc` (or `~/.zshrc`) once, by hand:

    . ~/.local/share/mvln.sh

(We deliberately don't auto-append; idempotent edits to your shell rc file are your call.)

Usage:

    mvln [-f|--force] [--resolve] [--] <source> <destination>

- `--force` overwrites an existing destination.
- `--resolve` canonicalizes through parent symlinks (`pwd -P`); without it the parent
  path you typed is preserved (`pwd`, logical).
- `--` separates flags from filenames that begin with `-` (e.g. `mvln -- -weird.txt store/`).

## PowerShell

Dot-source `powershell/Move-AsLink.ps1` from `$PROFILE`:

    Move-AsLink <Path> <Destination> [-Force] [-Resolve]

Same semantics. PowerShell uses PascalCase by convention, so `-Resolve` mirrors bash's `--resolve` and `-Force` mirrors `--force`.

On Windows, symlink creation requires either [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or an elevated shell. The function pre-flights a probe symlink before moving any data; if it can't, it aborts without touching the source.

## Behavior

- Files **and** directories.
- Symlink target is always absolute.
- If `<destination>` is an existing real directory **or ends with a path separator**,
  `basename(source)` is appended.
- Refuses to overwrite without `-f` / `-Force`.
- Strict symlink only — no junction or hardlink fallback. If symlink creation isn't permitted, mvln aborts before moving anything; enable Developer Mode (link above) or run the shell elevated.
- Special files (FIFO, socket, device) are rejected.

## The four destination patterns

Every `mvln` / `Move-AsLink` invocation is one of these four shapes. The single rule that distinguishes them: **if the destination ends with `/` (or `\`) OR is an existing real directory, the source's basename is appended; otherwise the destination is used as-is.**

### 1. File → exact new path (rename during move)

```bash
mvln a.txt store/notes.txt        # final: store/notes.txt
```
```powershell
Move-AsLink .\a.txt .\store\notes.txt
```

Destination has no trailing separator and `store/notes.txt` does not exist as a directory, so it is the literal new path. `store/` is auto-created. **Tested by case 22.**

### 2. File → into a directory (nested, not overwriting)

```bash
mvln a.txt bag/                   # final: bag/a.txt — trailing slash is the unambiguous form
mvln a.txt bag                    # same result IF bag already exists as a directory
```
```powershell
Move-AsLink .\a.txt .\bag\
Move-AsLink .\a.txt .\bag         # same result IF bag already exists
```

The trailing separator (or the fact that `bag` exists) flips the script into "container" mode; the file lands at `bag/a.txt` and `bag` itself is untouched. **Tested by cases 3 and 14.**

### 3. Directory → exact new path (rename, parent auto-created)

```bash
mvln src archive/src-2026         # final: archive/src-2026/
```
```powershell
Move-AsLink .\src .\archive\src-2026
```

`archive/src-2026` doesn't exist and has no trailing separator, so it is the new directory's identity. `archive/` is auto-created. **Tested by case 23.**

### 4. Directory → into a directory (nested)

```bash
mvln src bag/                     # final: bag/src/ — trailing slash always nests
mvln src bag                      # same result IF bag already exists as a directory
```
```powershell
Move-AsLink .\src .\bag\
Move-AsLink .\src .\bag           # same result IF bag already exists
```

Same container rule as pattern 2. **Tested by cases 24, 25, 27a, 27b.**

### The rename-vs-nest trap

Patterns 3 and 4 collapse to **the same command** (`mvln src bag`) when the trailing separator is omitted. The outcome flips based on whether `bag` already exists:

| Command         | `bag` absent              | `bag` exists as a real directory |
|-----------------|---------------------------|-----------------------------------|
| `mvln src bag`  | rename → `bag/`           | nest → `bag/src/`                |
| `mvln src bag/` | auto-create + nest → `bag/src/` | nest → `bag/src/`         |

**Habit:** if you mean *nest*, always include the trailing separator. The behavior is then identical regardless of whether the destination directory already exists. **Tested by cases 26a, 26b, 27a, 27b.**

## Examples

These four examples cover the everyday cases. For the comprehensive reference — every source path form, every flag, every realistic use case, and the error patterns the function intentionally rejects — see **[EXAMPLES.md](EXAMPLES.md)**.

### Symlink a config file into a dotfiles repo

```bash
mvln ~/.gitconfig ~/dotfiles/git/gitconfig
ls -la ~/.gitconfig
# lrwxrwxrwx  ... /home/you/.gitconfig -> /home/you/dotfiles/git/gitconfig
```

```powershell
Move-AsLink $HOME\.gitconfig $HOME\dotfiles\git\gitconfig
Get-Item $HOME\.gitconfig | Select-Object LinkType, Target
# LinkType     Target
# SymbolicLink {C:\Users\you\dotfiles\git\gitconfig}
```

### Offload a project's `node_modules` to a faster scratch disk

```bash
cd ~/work/my-app
mvln node_modules /mnt/nvme-scratch/my-app/node_modules
readlink node_modules
# /mnt/nvme-scratch/my-app/node_modules
# `npm run`, `tsc`, your editor's resolver — all keep working unchanged.
```

```powershell
Set-Location C:\work\my-app
Move-AsLink .\node_modules D:\scratch\my-app\node_modules
(Get-Item .\node_modules).Target
# D:\scratch\my-app\node_modules
```

### Move the `Downloads` folder to an external drive (trailing-slash destination)

```bash
mvln ~/Downloads /media/external/
# Trailing slash means "put it inside this directory", so the final path is
# /media/external/Downloads. Saves typing the basename twice.
ls -la ~/Downloads
```

```powershell
Move-AsLink $HOME\Downloads E:\
Get-Item $HOME\Downloads | Format-List Name, LinkType, Target
```

### Replace a stale offload with a fresh copy using `--force`

```bash
# /mnt/ml-cache/llama-70b already holds an older copy you want overwritten:
mvln --force ./llama-70b-v2 /mnt/ml-cache/llama-70b
readlink ./llama-70b-v2
# /mnt/ml-cache/llama-70b
```

```powershell
Move-AsLink .\llama-70b-v2 D:\ml-cache\llama-70b -Force
(Get-Item .\llama-70b-v2).Target
# D:\ml-cache\llama-70b
```

### More examples

See **[EXAMPLES.md](EXAMPLES.md)** for:

- **Source path syntax** — absolute, bare-name, dot-relative, `..`, `~`, mixed `/` and `\` separators on Windows, after `cd` / `Set-Location` / `Push-Location`
- **Flags in depth** — `--force` / `-Force`, `--resolve` / `-Resolve`, `--` POSIX terminator
- **Source-type handling** — files, directories, existing symlinks (preserved, not dereferenced), dangling symlinks, filenames starting with `-`
- **Recipes** — Steam game offload, Hugging Face cache to bulk storage, Docker volume relocation, build artifacts on scratch, symlinked-parent `--resolve` workflow
- **Error patterns** — what `mvln` / `Move-AsLink` refuse to do and why (source missing, same path, dest exists without `--force`, special files, non-FileSystem PSDrive in pwsh)
- **Cross-reference** — table mapping every documented form to the test case that pins it

<details>
<summary><b>Caveats</b> (click to expand)</summary>

- **Cross-filesystem moves** (`EXDEV`) are not transactional: `mv` (or `Move-Item`)
  copies-then-deletes. If `mv` succeeds but the symlink step fails, the helper attempts
  to roll back via a reverse `mv`; if rollback also fails, you'll get an error naming
  both paths so you can recover by hand.
- **Case-insensitive filesystems** (default macOS, Windows): `mvln Foo.txt foo.txt` is
  rejected via inode comparison on bash/zsh and case-insensitive string compare on
  PowerShell-on-Windows.
- **`PATH_MAX` / Windows `MAX_PATH`**: not handled specially; absolute paths longer than
  the OS limit will fail at the `mv` / `Move-Item` step.
- **Race window**: there is a TOCTOU between the existence check and the `mv`. A
  concurrent process creating the destination between those two steps may produce a
  silent overwrite on Linux (`mv`) or an error on Windows (`Move-Item`). Don't run two
  `mvln` invocations against the same destination concurrently.
- **`ln -sn`** (used internally) is a no-deref symlink create. We deliberately do not
  pass `-f` so a post-`mv` race that recreates the source path will surface as an error
  rather than blow it away; the function will then attempt a reverse `mv` rollback.
- **Shell function overrides (bash/zsh)**: if your shell config wraps common commands like
  `cd`, `pwd`, `ls`, `dirname`, or `basename` with functions that print extra output (e.g.
  `cd() { builtin cd "$@" && ls; }`), those functions are inherited by `$(...)` subshells
  and their extra stdout gets captured alongside the real output, corrupting internal path
  variables. `mvln` guards against this with `builtin cd`, `builtin pwd`, and `command ls`
  / `command dirname` / `command basename`. If you see a garbled path in an error message
  that looks like a directory listing, a shell function override is the likely cause.
  PowerShell is not affected: path resolution there uses `[IO.Path]` static methods which
  cannot be overridden.

</details>

## Tests

CI runs ~28 edge cases across `bash`, `zsh`, and `pwsh` on Ubuntu, macOS, and Windows,
including a Linux cross-filesystem (`/dev/shm` tmpfs) case, (on Windows) a
partial-removal-with-open-handle case, and the four canonical destination patterns
documented above.

**CI is the authoritative validator.** Local test runs can produce misleading
results on Windows hosts (MSYS bash treats `ln -s` as a copy without
`MSYS=winsymlinks:nativestrict`; `[IO.Path]` in pwsh resolves `.\` and `\`
differently on Linux/macOS than on Windows; zsh is rarely installed locally).
For contributors: push to a branch and read the CI matrix. See `CLAUDE.md` for
the project's testing policy.

For an end-user install spot-check (not a contributor verification):

    bash tests/test-mvln.bash
    zsh  tests/test-mvln.zsh
    pwsh -NoProfile -File tests/Test-MoveAsLink.ps1

## License

MIT
