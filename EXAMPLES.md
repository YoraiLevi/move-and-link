# move-and-link — Full examples reference

The comprehensive reference for `mvln` (bash/zsh) and `Move-AsLink` (pwsh). For the introduction, install instructions, and the four core destination patterns (file/dir × rename/nest), see the [README](README.md).

Every example below shows the bash/zsh form, the PowerShell form, and what the final state on disk looks like. Where a test case in [`tests/_cases.sh`](tests/_cases.sh) or [`tests/Test-MoveAsLink.ps1`](tests/Test-MoveAsLink.ps1) pins the behavior, it's cited as `[case NN]`.

---

## 1. Source path forms

The source argument resolves against your **current working directory** (`$PWD` in bash/zsh, `Get-Location` / `$PWD` in PowerShell — *not* `[Environment]::CurrentDirectory`). Every form below is interchangeable; pick whichever reads best for your situation.

### 1.1 Absolute paths

```bash
mvln /home/you/Downloads/big.bin /mnt/bulk/big.bin
```
```powershell
Move-AsLink C:\Users\you\Downloads\big.bin D:\bulk\big.bin
```
**Result:** real file lives at the destination, symlink replaces the source path. Independent of your current directory. `[case 34]`

### 1.2 Bare names (relative to current directory)

```bash
cd ~/work/my-app
mvln node_modules /mnt/scratch/my-app/node_modules
```
```powershell
Set-Location C:\work\my-app
Move-AsLink node_modules D:\scratch\my-app\node_modules
```
**Result:** `node_modules` is interpreted as relative to your current directory. Works exactly like every other shell command — no `.\` prefix needed. `[case 30]`

### 1.3 Dot-relative paths

```bash
cd ~/work/my-app
mvln ./node_modules /mnt/scratch/my-app/node_modules
```
```powershell
Set-Location C:\work\my-app
Move-AsLink .\node_modules D:\scratch\my-app\node_modules
```
**Result:** identical to 1.2. The `./` (or `.\`) is cosmetic on POSIX shells but recommended in pwsh to disambiguate filenames that look like flag values. `[case 28]`

### 1.4 Mixed forward/backslash separators (Windows pwsh only)

```powershell
Move-AsLink .\original-file ./dir/
Move-AsLink ./src .\bag\
```
**Result:** on Windows, `\` and `/` are both treated as path separators by .NET. Mixing them in a single command works correctly. On Linux/macOS pwsh, `\` is a literal filename character — do not mix there. `[case 31, Windows-only]`

### 1.5 Parent-directory references

```bash
cd ~/work/my-app/build
mvln ../big-asset /mnt/cdn/big-asset
```
```powershell
Set-Location C:\work\my-app\build
Move-AsLink ..\big-asset D:\cdn\big-asset
```
**Result:** `..` resolves against your current directory and walks up one level. `..\..\` etc. work too. `[case 33]`

### 1.6 Tilde-expanded paths

```bash
mvln ~/Downloads/big.bin /mnt/bulk/big.bin
```
```powershell
Move-AsLink ~\Downloads\big.bin D:\bulk\big.bin
```
**Result:** the shell parser expands `~` to your home directory **before** `mvln` / `Move-AsLink` sees the argument. The function only sees the resolved absolute path. No special handling required from the function side.

### 1.7 After navigating with `cd` / `Set-Location`

```bash
cd ~/projects/site
mvln ./static /mnt/cdn/static
```
```powershell
Set-Location C:\projects\site
Move-AsLink .\static D:\cdn\static
```
**Result:** the function uses the directory you're *currently* in — the one shown in your prompt — not the directory PowerShell was started from. (This was a bug in pwsh until commit `ca7a5c7`.) `[cases 28, 29, 30, 35]`

### 1.8 After `Push-Location` (pwsh)

```powershell
Push-Location C:\projects\site
try {
    Move-AsLink .\static D:\cdn\static
} finally { Pop-Location }
```
**Result:** identical to `Set-Location`. `Push-Location` is just `Set-Location` with a return stack. `[case 35]`

---

## 2. Destination path forms

The destination argument has one disambiguation rule: **if it ends with `/` (or `\`) OR is an existing real directory, the source's basename is appended; otherwise it's used as-is.** The README's [Four destination patterns](README.md#the-four-destination-patterns) section explains the four resulting shapes. Below is the long tail.

### 2.1 Exact new path (rename during move)

```bash
mvln a.txt store/notes.txt          # final: store/notes.txt
mvln src archive/src-2026           # final: archive/src-2026/
```
**Result:** the destination string is used literally. Any missing parent directories (`store/`, `archive/`) are created automatically. `[cases 22, 23]`

### 2.2 Into an existing directory

```bash
mkdir bag
mvln a.txt bag                      # final: bag/a.txt
mvln src bag                        # final: bag/src/
```
**Result:** because `bag` already exists as a real directory, the source's basename is appended. `bag` itself is **not** overwritten. `[cases 3, 24, 26b]`

### 2.3 Trailing separator (force nest, even if dir doesn't exist)

```bash
mvln a.txt bag/                     # final: bag/a.txt (bag/ auto-created)
mvln src bag/                       # final: bag/src/ (bag/ auto-created)
```
```powershell
Move-AsLink .\a.txt .\bag\
Move-AsLink .\src .\bag\
```
**Result:** the trailing separator unambiguously signals "nest into a container", even if the container doesn't exist yet. Use this form when you want nesting and don't want to depend on whether the destination dir pre-exists. `[cases 14, 25, 27a, 27b]`

### 2.4 Non-existent nested parent directories

```bash
mvln a.txt deeply/nested/path/a.txt
```
```powershell
Move-AsLink .\a.txt .\deeply\nested\path\a.txt
```
**Result:** `deeply/nested/path/` is auto-created via `mkdir -p` (bash) or `New-Item -ItemType Directory -Force` (pwsh). The file lands at `deeply/nested/path/a.txt`. `[case 4]`

### 2.5 Cross-volume destination

```bash
mvln big.bin /mnt/different-drive/big.bin
```
```powershell
Move-AsLink .\big.bin E:\big.bin
```
**Result:** works. The underlying `mv` / `Move-Item` copies-then-deletes across volumes. Not transactional — see [Caveats in README](README.md). `[case 20, Linux-only]`

---

## 3. Flags

### 3.1 Force overwrite (`--force` / `-Force`)

```bash
mvln --force ./llama-70b-v2 /mnt/ml-cache/llama-70b
mvln -f ./llama-70b-v2 /mnt/ml-cache/llama-70b
```
```powershell
Move-AsLink .\llama-70b-v2 D:\ml-cache\llama-70b -Force
```
**Result:** if the destination already exists (file, directory, or symlink), it's removed first and then the move proceeds. Without `--force`/`-Force`, the function refuses and changes nothing. `[cases 5, 6]`

### 3.2 Canonical path resolution (`--resolve` / `-Resolve`)

```bash
# ~/projects is itself a symlink to /mnt/work/projects.
cd ~/projects/my-app
mvln build ~/scratch/my-app-build
readlink build
# /home/you/scratch/my-app-build   (logical: parent symlink preserved)

mvln --resolve dist /mnt/cdn-staging/my-app-dist
readlink dist
# /mnt/cdn-staging/my-app-dist     (canonical: symlinks resolved)
```
```powershell
Set-Location $HOME\projects\my-app
Move-AsLink .\build $HOME\scratch\my-app-build
Move-AsLink .\dist E:\cdn-staging\my-app-dist -Resolve
```
**Result:** by default the function preserves whatever parent path you typed (logical resolution). `--resolve` / `-Resolve` canonicalizes through symlinks so the stored symlink target uses real underlying paths. Use this if downstream tooling can't follow nested symlinks. `[case 19]`

### 3.3 POSIX flag terminator (`--`, bash/zsh only)

```bash
mvln -- -weird.txt store/-weird.txt
```
**Result:** everything after `--` is treated as a positional argument, not a flag. Use this for filenames that start with `-`. PowerShell doesn't need this — it uses positional/named parameter binding instead. `[case 16]`

---

## 4. Source types

### 4.1 Regular files

Covered throughout — `[cases 1, 10, 22, 28, 30, 34]`.

### 4.2 Directories

Whole directories are moved as a unit, then symlinked. Internal structure is preserved exactly. `[cases 2, 23, 24, 25, 29]`

### 4.3 Existing symlinks (preserved, not dereferenced)

```bash
ln -s real.txt link.txt
mvln link.txt store/link.txt
readlink store/link.txt
# real.txt   (the ORIGINAL target is preserved — we moved the symlink, not the file)
```
```powershell
New-Item -ItemType SymbolicLink -Path link.txt -Target real.txt
Move-AsLink .\link.txt .\store\link.txt
(Get-Item .\store\link.txt).Target
# real.txt
```
**Result:** the symlink itself is relocated, with its original target string intact. Useful when reorganizing collections of symlinks without breaking what they point to. `[case 9]`

### 4.4 Dangling symlinks

```bash
ln -s /no/such/path dangling.lnk
mvln dangling.lnk store/dangling.lnk
# Succeeds; store/dangling.lnk is still dangling but moved.
```
```powershell
New-Item -ItemType SymbolicLink -Path dangling.lnk -Target C:\no\such\path
Move-AsLink .\dangling.lnk .\store\dangling.lnk
```
**Result:** dangling symlinks (whose targets don't exist) are still movable. The function only requires the *symlink entry* to exist, not its target. `[case 17 (bash), case 15 (pwsh)]`

### 4.5 Filenames starting with a dash

```bash
mvln -- -weird.txt store/-weird.txt
```
```powershell
Move-AsLink -- -weird.txt store\-weird.txt    # -- works in pwsh too
Move-AsLink -Path -weird.txt -Destination store\-weird.txt    # or use named params
```
**Result:** `--` separates flags from positional args; in pwsh, named parameters also work. `[case 16]`

### 4.6 Trailing slash on a symlinked-directory source

```bash
ln -s realdir linkdir
mvln linkdir/ store/linkdir
readlink store/linkdir
# realdir   (the trailing slash on the source does NOT dereference the symlink)
```
**Result:** when the source is a symlink that points to a directory, a trailing slash on the source does **not** dereference it. The symlink itself is moved, preserving its target. `[case 15 (bash)]`

---

## 5. Realistic use cases

### 5.1 Relocate a Steam game off the SSD without reinstalling

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
**Outcome:** Steam's launcher resolves the symlink and continues to launch the game. No re-download required. Works for any installer that doesn't aggressively validate install paths.

### 5.2 Move a 200 GB Hugging Face cache to bulk storage

```bash
mvln ~/.cache/huggingface /mnt/bulk-hdd/huggingface
du -sh ~/.cache/huggingface  # follows the symlink; reports the moved size
readlink ~/.cache/huggingface
# /mnt/bulk-hdd/huggingface
# HF_HOME stays unchanged; transformers / datasets keep finding everything.
```
```powershell
Move-AsLink $HOME\.cache\huggingface F:\bulk\huggingface
```
**Outcome:** `transformers`, `datasets`, `diffusers`, and anything else honoring `HF_HOME` / `XDG_CACHE_HOME` keeps resolving caches transparently. Cross-volume move; not transactional (see Caveats).

### 5.3 Offload a Docker named volume's data directory

```bash
sudo systemctl stop docker
sudo mvln /var/lib/docker/volumes/postgres_data /mnt/db-ssd/postgres_data
sudo systemctl start docker
```
```powershell
Stop-Service com.docker.service
Move-AsLink "C:\ProgramData\Docker\volumes\postgres_data" `
            "D:\docker-data\postgres_data"
Start-Service com.docker.service
```
**Outcome:** Docker resolves through the symlink; container mounts work as before. **Stop the daemon first** — moving a directory the kernel has open is a recipe for corruption.

### 5.4 Symlink a config file into a dotfiles repo

```bash
mvln ~/.gitconfig ~/dotfiles/git/gitconfig
ls -la ~/.gitconfig
# lrwxrwxrwx ... ~/.gitconfig -> ~/dotfiles/git/gitconfig
```
```powershell
Move-AsLink $HOME\.gitconfig $HOME\dotfiles\git\gitconfig
```
**Outcome:** the config file now lives in your dotfiles repo (so it's version-controlled), but every tool that reads `~/.gitconfig` finds it transparently.

### 5.5 Move build artifacts to a scratch disk per-project

```bash
cd ~/projects/my-rust-app
mvln target /mnt/scratch/my-rust-app/target
cargo build  # writes through the symlink; SSD is spared
```
```powershell
Set-Location C:\projects\my-rust-app
Move-AsLink .\target D:\scratch\my-rust-app\target
```
**Outcome:** `cargo build`, `npm run build`, `gradle build`, `make` — all write transparently through the symlink to the scratch disk. Project layout in your repo is untouched.

### 5.6 Move Downloads to an external drive (trailing slash example)

```bash
mvln ~/Downloads /media/external/
# Trailing slash means "put it inside this directory", so the final path is
# /media/external/Downloads. Saves typing the basename twice.
```
```powershell
Move-AsLink $HOME\Downloads E:\
```
**Outcome:** your Downloads directory now lives at `/media/external/Downloads` (or `E:\Downloads` on Windows). The symlink at the original path keeps every browser, app, and shortcut working.

---

## 6. Patterns that error out (intentional safety)

These are the things you might try that the function will refuse to do — usually because doing them silently would be dangerous.

### 6.1 Source does not exist

```bash
mvln nope.txt store/nope.txt
# mvln: source does not exist: nope.txt
# (exit code 1)
```
```powershell
Move-AsLink .\nope.txt .\store\nope.txt
# Move-AsLink: source does not exist: .\nope.txt
```
`[case 7]`

### 6.2 Source and destination resolve to the same path

```bash
mvln a.txt ./a.txt
# mvln: source and destination are the same: /abs/a.txt
```
```powershell
Move-AsLink .\a.txt .\a.txt
# Move-AsLink: source and destination are the same
```
**Result:** rejected. This also catches case-insensitive filesystem confusion (`mvln Foo.txt foo.txt` on macOS/Windows is rejected via inode comparison). `[case 8]`

### 6.3 Destination already exists, no `--force` / `-Force`

```bash
mvln a.txt store/a.txt
# mvln: destination exists: /abs/store/a.txt (use -f to overwrite)
```
```powershell
Move-AsLink .\a.txt .\store\a.txt
# Move-AsLink: destination exists: ...\store\a.txt (use -Force to overwrite)
```
**Result:** the source file is left in place; nothing is changed. `[case 5]`

### 6.4 Special files (FIFO, socket, device)

```bash
mkfifo myfifo
mvln myfifo store/myfifo
# mvln: source is not a regular file, directory, or symlink: myfifo
```
**Result:** rejected. The function only handles regular files, directories, and symlinks. `[case 18]`

### 6.5 Non-FileSystem PSDrive in pwsh

```powershell
Set-Location HKLM:\SOFTWARE
Move-AsLink .\foo .\bar
# Move-AsLink: current location is not a filesystem path (HKLM:\SOFTWARE).
# Use an absolute filesystem path, or Set-Location to a filesystem path first.
```
**Result:** rejected before any data moves. Added in commit `ca7a5c7` as a defensive guard.

### 6.6 Symlinks not permitted on this filesystem

```bash
mvln a.txt /mnt/no-symlinks-here/a.txt
# mvln: cannot create symlinks at /home/you; aborting before move
```
**Result:** the function pre-flights a symlink probe at the source's parent directory **before** moving any data. If symlinks can't be created (Windows without Developer Mode, certain FAT/exFAT mounts, etc.), the move is refused and no data is touched.

### 6.7 Bogus flag

```bash
mvln --bogus a b
# mvln: unknown flag: --bogus
# (exit code 64)
```
```powershell
Move-AsLink -Bogus a b
# Move-AsLink: A parameter cannot be found that matches parameter name 'Bogus'.
```
`[case 12]`

---

## 7. Test-case cross-reference

| Case | Pins                                                             |
|------|------------------------------------------------------------------|
| 1    | File → symlink basic                                             |
| 2    | Directory → symlink basic                                        |
| 3    | File → existing dir (nest, no trailing slash)                    |
| 4    | Missing destination parent auto-created                          |
| 5    | Refuses existing destination without `--force`                   |
| 6    | `--force` overwrites and re-points symlink                       |
| 7    | Fails when source missing                                        |
| 8    | Fails when src and dst are same path                             |
| 9    | Symlink source relocated, target preserved                       |
| 10   | Writes through symlink propagate to destination                  |
| 14   | Trailing-slash destination = container                           |
| 15   | Trailing-slash source does NOT dereference symlink dirs (bash)   |
| 16   | Filenames starting with `-` require `--`                         |
| 17   | Dangling symlinks moved as-is (bash); open-handle (pwsh)         |
| 18   | Special files (FIFO) rejected                                    |
| 19   | Logical-mode preserves symlinked parent in source path           |
| 20   | Cross-filesystem move (Linux tmpfs)                              |
| 21   | Custom `cd` function with side-effects doesn't corrupt resolution |
| 22   | File → exact NEW name (rename)                                   |
| 23   | Directory → exact NEW name in non-existent parent                |
| 24   | Directory → existing dir (nest, no trailing slash)               |
| 25   | Directory → trailing-slash dest (auto-create + nest)             |
| 26a  | Rename-vs-nest trap: dest absent → rename                        |
| 26b  | Rename-vs-nest trap: dest present → nest                         |
| 27a  | Trailing slash always nests (dir absent)                         |
| 27b  | Trailing slash always nests (dir present)                        |
| 28   | (A) Dot-relative source file after `Set-Location`                |
| 29   | (A) Dot-relative source directory after `Set-Location`           |
| 30   | (B) Bare-name source after `Set-Location`                        |
| 31   | (C) Mixed forward/backslash separators (Windows only)            |
| 33   | (E) Parent-directory references (`..`)                           |
| 34   | (F) Absolute source path without harness cwd sync                |
| 35   | (G) `Push-Location` updates PSDrive cwd for relative resolution  |

---

## See also

- [README](README.md) — install, behavior, four destination patterns, canonical examples
- [tests/_cases.sh](tests/_cases.sh) — bash/zsh test cases
- [tests/Test-MoveAsLink.ps1](tests/Test-MoveAsLink.ps1) — pwsh test cases
- [CLAUDE.md](CLAUDE.md) — project testing policy (CI is the authoritative validator)
