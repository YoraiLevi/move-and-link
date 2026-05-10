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

## Examples

### Move a single config file to a shared dotfiles directory

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

### Relocate a Steam game off the SSD without re-installing

```bash
mvln ~/.steam/steam/steamapps/common/Cyberpunk2077 /mnt/games-hdd/Cyberpunk2077
# Steam still finds the game via the symlink; ~80 GB freed on the SSD.
```

```powershell
Move-AsLink "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077" `
            "D:\Games\Cyberpunk 2077"
Get-Item "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077" |
    Select-Object LinkType, Target
```

### Move the `Downloads` folder to an external drive (using a trailing-slash destination)

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

### Move a 200 GB Hugging Face cache to spinning rust (cross-volume)

```bash
mvln ~/.cache/huggingface /mnt/bulk-hdd/huggingface
du -sh ~/.cache/huggingface  # follows the symlink; reports the moved size
readlink ~/.cache/huggingface
# /mnt/bulk-hdd/huggingface
# HF_HOME stays unchanged; transformers/datasets keep finding everything.
```

```powershell
Move-AsLink $HOME\.cache\huggingface F:\bulk\huggingface
Get-ChildItem $HOME\.cache\huggingface | Measure-Object -Property Length -Sum
# Reads through the link to the new volume.
```

### Offload a Docker named volume's data directory (cross-volume)

```bash
sudo systemctl stop docker
sudo mvln /var/lib/docker/volumes/postgres_data /mnt/db-ssd/postgres_data
sudo systemctl start docker
ls -la /var/lib/docker/volumes/postgres_data
# Docker resolves through the symlink; container mounts work as before.
```

```powershell
Stop-Service com.docker.service
Move-AsLink "C:\ProgramData\Docker\volumes\postgres_data" `
            "D:\docker-data\postgres_data"
Start-Service com.docker.service
```

### Move through a symlinked parent (`--resolve` to opt out of the default)

```bash
# ~/projects is itself a symlink to /mnt/work/projects.
# By default, mvln keeps the parent path you typed (logical):
cd ~/projects/my-app
mvln build ~/scratch/my-app-build
readlink build
# /home/you/scratch/my-app-build   (logical: parent symlink preserved)

# Use --resolve when you want the *real* underlying path baked in:
mvln --resolve dist /mnt/cdn-staging/my-app-dist
readlink dist
# /mnt/cdn-staging/my-app-dist   (canonicalized, no symlinks in the path)
```

```powershell
Set-Location $HOME\projects\my-app
Move-AsLink .\build $HOME\scratch\my-app-build
(Get-Item .\build).Target

Move-AsLink .\dist E:\cdn-staging\my-app-dist -Resolve
(Get-Item .\dist).Target
```

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

CI runs ~21 edge cases across `bash`, `zsh`, and `pwsh` on Ubuntu, macOS, and Windows,
including a Linux cross-filesystem (`/dev/shm` tmpfs) case and (on Windows) a
partial-removal-with-open-handle case.

Run locally:

    bash tests/test-mvln.bash
    zsh  tests/test-mvln.zsh
    pwsh -NoProfile -File tests/Test-MoveAsLink.ps1

## License

MIT
