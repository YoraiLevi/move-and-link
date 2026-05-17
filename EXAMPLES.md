# move-and-link — Full examples & coverage matrix

The comprehensive reference for `mvln` (bash/zsh) and `Move-AsLink` (pwsh). For the introduction, install instructions, and the four core destination patterns (file/dir × rename/nest), see the [README](README.md).

This document is organized as a **coverage matrix**: every shape a user can reasonably type, with its support status and a direct link to the test case that pins the behavior.

## How to read this document

Each entry has:

- The bash/zsh and PowerShell forms (where applicable)
- A one-line description of what it does
- A status icon
- Links to the specific test case that proves the behavior

### Status legend

| Icon | Meaning |
|------|---------|
| ✅   | **Supported** — works as documented, behavior pinned by a test |
| 🚫   | **Refused with a clear error** — by-design safety, not a bug |
| ⛔   | **Unsupported by design** — user cannot make this work; documented |
| ❓   | **Behavior unknown** — no test; behavior currently uncertain |
| ⚪   | **Inherited** — works via a framework feature (PowerShell common parameter); not our test surface |

### Test-link convention

Links go directly to the line in the test file where the case is defined. `[bash #22](tests/_cases.sh#L176)` opens the bash test at line 176; `[pwsh #22](tests/Test-MoveAsLink.ps1#L217)` opens the pwsh test at line 217. If a case is platform-specific (bash-only, pwsh-only, Linux-only), only one link appears.

---

## A. Source path forms

The source argument resolves against your **current working directory** — `$PWD` in bash/zsh, `(Get-Location).ProviderPath` in PowerShell (NOT `[Environment]::CurrentDirectory`).

### A1. Absolute path

```bash
mvln /home/you/Downloads/big.bin /mnt/bulk/big.bin
```
```powershell
Move-AsLink C:\Users\you\Downloads\big.bin D:\bulk\big.bin
```

**Status:** ✅ Supported · **Tests:** [bash #34](tests/_cases.sh#L283) · [pwsh #34](tests/Test-MoveAsLink.ps1#L351)

Works regardless of your current directory. Resolves immediately because `[IO.Path]::IsPathRooted` returns true.

### A2. Bare name (relative to current directory)

```bash
cd ~/work/my-app
mvln node_modules /mnt/scratch/my-app/node_modules
```
```powershell
Set-Location C:\work\my-app
Move-AsLink node_modules D:\scratch\my-app\node_modules
```

**Status:** ✅ Supported · **Tests:** [bash #30](tests/_cases.sh#L262) · [pwsh #30](tests/Test-MoveAsLink.ps1#L323)

No `./` prefix needed. Resolves against `$PWD` / `Get-Location` like every other shell command.

### A3. Dot-relative path

```bash
mvln ./node_modules /mnt/scratch/my-app/node_modules
```
```powershell
Move-AsLink .\node_modules D:\scratch\my-app\node_modules
```

**Status:** ✅ Supported · **Tests:** [bash #28](tests/_cases.sh#L247) · [pwsh #28](tests/Test-MoveAsLink.ps1#L305)

Identical to A2. The `./` (or `.\`) is cosmetic on POSIX shells but useful in pwsh to disambiguate filenames that look like parameter values.

### A4. Parent-directory reference

```bash
cd ~/work/my-app/build
mvln ../big-asset /mnt/cdn/big-asset
```
```powershell
Set-Location C:\work\my-app\build
Move-AsLink ..\big-asset D:\cdn\big-asset
```

**Status:** ✅ Supported · **Tests:** [bash #33](tests/_cases.sh#L274) · [pwsh #33](tests/Test-MoveAsLink.ps1#L341)

`..` resolves against your current directory and walks up one level. Stack as needed (`..\..\foo`).

### A5. Tilde-expanded path

```bash
mvln ~/Downloads/big.bin /mnt/bulk/big.bin
```
```powershell
Move-AsLink ~\Downloads\big.bin D:\bulk\big.bin
```

**Status:** ✅ Supported · **Tests:** [bash #51](tests/_cases.sh#L421) · [pwsh #51](tests/Test-MoveAsLink.ps1#L512)

`~` resolves to the user's home directory. In **bash/zsh** the shell parser expands `~` before the function sees it. In **PowerShell** the parser does NOT expand `~`; `Move-AsLink` does it explicitly via the FileSystem provider's `Home` property so the same syntax works in both shells.

### A6. Mixed forward/backslash separators (Windows pwsh only)

```powershell
Move-AsLink .\original-file ./dir/
Move-AsLink ./src .\bag\
```

**Status:** ✅ Supported (Windows only) · **Tests:** [pwsh #31](tests/Test-MoveAsLink.ps1#L330)

On Windows, `\` and `/` are both path separators in .NET. On Linux/macOS pwsh, `\` is a literal filename character — do not mix there.

### A7. Trailing separator on source

```bash
mvln ./srcdir/ ./bagdir/
```
```powershell
Move-AsLink .\srcdir\ .\bagdir\
```

**Status:** ✅ Supported · **Tests:** [bash #36](tests/_cases.sh#L304), [#37](tests/_cases.sh#L312), [#38](tests/_cases.sh#L320) · [pwsh #36](tests/Test-MoveAsLink.ps1#L374), [#37](tests/Test-MoveAsLink.ps1#L387), [#38](tests/Test-MoveAsLink.ps1#L398)

A trailing `/` (or `\` on Windows) on the source is silently stripped before basename extraction. Tab-completion of directory names typically adds one; the function handles it transparently.

### A8. UNC path

```powershell
Move-AsLink \\server\share\file D:\local\file
```

**Status:** ❓ Behavior unknown · **Tests:** none (not feasible in GitHub Actions runners — would require a real SMB share)

Likely works via .NET path resolution, but unverified.

### A9. `C:foo` drive-relative pwsh shorthand

```powershell
Move-AsLink C:foo D:\backup\foo    # 'C:foo' = "foo at C:'s current location"
```

**Status:** ❓ Behavior unknown · **Tests:** none (niche pwsh quirk; deferred)

A rarely-used PowerShell syntax; behavior is uncertain. Use full absolute paths (`C:\full\path\foo`) for reliability.

### A10. Glob pattern as source

```bash
mvln '*.txt' store/
```
```powershell
Move-AsLink '*.txt' .\store\
```

**Status:** ⛔ Unsupported by design · **Tests:** [bash #48](tests/_cases.sh#L401) · [pwsh #48](tests/Test-MoveAsLink.ps1#L496)

The function takes one literal source path. Glob patterns aren't expanded internally; if the shell doesn't expand them upstream (e.g., no matching files), `*.txt` is passed as a literal name and rejected as "source does not exist." If you need glob-style moves, write a shell loop: `for f in *.txt; do mvln "$f" store/; done`.

### A11. Path with spaces (quoted)

```bash
mvln "my file.txt" "store/my file.txt"
```
```powershell
Move-AsLink 'my file.txt' 'store\my file.txt'
```

**Status:** ✅ Supported · **Tests:** [bash #39](tests/_cases.sh#L334) · [pwsh #39](tests/Test-MoveAsLink.ps1#L414)

Standard shell quoting applies. Common on Windows (`Program Files`, etc.).

### A12. Unicode / non-ASCII characters in filename

```bash
mvln "café.txt" "store/café.txt"
```
```powershell
Move-AsLink 'café.txt' 'store\café.txt'
```

**Status:** ✅ Supported · **Tests:** [bash #40](tests/_cases.sh#L341) · [pwsh #40](tests/Test-MoveAsLink.ps1#L424)

Filesystem-dependent (NTFS, APFS, ext4 all support Unicode by default). Filenames with non-ASCII characters work end-to-end.

### A13. Symlink as source (preserved, not dereferenced)

```bash
ln -s real.txt link.txt
mvln link.txt store/link.txt
readlink store/link.txt
# real.txt   ← the original target string is preserved
```
```powershell
New-Item -ItemType SymbolicLink -Path link.txt -Target real.txt
Move-AsLink .\link.txt .\store\link.txt
(Get-Item .\store\link.txt).Target
# real.txt
```

**Status:** ✅ Supported · **Tests:** [bash #9](tests/_cases.sh#L67) · [pwsh #9](tests/Test-MoveAsLink.ps1#L138)

Useful when reorganizing collections of symlinks without disturbing what they point to.

### A14. Dangling symlink as source

```bash
ln -s /no/such/path dangling.lnk
mvln dangling.lnk store/dangling.lnk
# Succeeds; store/dangling.lnk is still dangling but moved.
```
```powershell
New-Item -ItemType SymbolicLink -Path dangling.lnk -Target C:\no\such\path
Move-AsLink .\dangling.lnk .\store\dangling.lnk
```

**Status:** ✅ Supported · **Tests:** [bash #17](tests/_cases.sh#L124) · [pwsh #15](tests/Test-MoveAsLink.ps1#L186)

The function checks for the symlink entry's existence, not its target. Dangling symlinks move cleanly.

### A15. Junction as source (Windows)

```powershell
New-Item -ItemType Junction -Path junc -Target C:\target\dir
Move-AsLink .\junc .\store\junc
```

**Status:** ✅ Supported (Windows only) · **Tests:** [pwsh #57](tests/Test-MoveAsLink.ps1#L592)

The junction itself is moved (not its target). The original target directory is untouched.

### A16. Hardlink as source

```bash
ln realfile hardlink     # POSIX hardlink
mvln hardlink store/hardlink
```
```powershell
New-Item -ItemType HardLink -Path hardlink.txt -Target C:\realfile.txt
Move-AsLink .\hardlink.txt .\store\hardlink.txt
```

**Status:** ✅ Supported · **Tests:** [bash #41](tests/_cases.sh#L348) · [pwsh #41](tests/Test-MoveAsLink.ps1#L434)

Hardlinks are indistinguishable from regular files. The other hardlinked names remain intact.

### A17. Filename starting with `-`

```bash
mvln -- -weird.txt store/-weird.txt
```
```powershell
Move-AsLink -Path -weird.txt -Destination .\store\-weird.txt
# or:  Move-AsLink -- -weird.txt store\-weird.txt
```

**Status:** ✅ Supported · **Tests:** [bash #16](tests/_cases.sh#L118)

Bash needs `--` to separate flags from leading-dash arguments. PowerShell accepts `--` too but the canonical pwsh form is the named-parameter `-Path` / `-Destination`.

### A18. Path longer than the OS limit (Windows `MAX_PATH`)

**Status:** 🚫 Refused (fails at `Move-Item` step) · **Tests:** none (CI-fragile)

Documented as a caveat in the README. Not actively defended against; the underlying `Move-Item` or `mv` returns an OS-level error.

### A19. Empty string `""`

```bash
mvln "" store/x
```
```powershell
Move-AsLink "" .\store\x
```

**Status:** 🚫 Refused · **Tests:** none (handled by parameter validation; would be one-line test to make explicit)

Bash rejects via arity check (`-n` test or existence test); pwsh rejects via `[Parameter(Mandatory)]` parameter binding.

### A20. Whitespace-only path `" "`

```bash
mvln " " store/blank
```

**Status:** 🚫 Refused · **Tests:** [bash #49](tests/_cases.sh#L409) · [pwsh #49](tests/Test-MoveAsLink.ps1#L501)

Source doesn't exist; clean error.

### A21. Filename containing a newline (POSIX-only edge case)

```bash
weird="$(printf 'a\nb.txt')"
mvln "$weird" "store/$weird"
```

**Status:** ✅ Supported (POSIX only) · **Tests:** [bash #52](tests/_cases.sh#L433)

POSIX filesystems allow newlines in filenames. Windows NTFS doesn't, so this is bash/zsh-only.

### A22. FIFO / socket / device (POSIX special file)

```bash
mkfifo myfifo
mvln myfifo store/myfifo
# mvln: source is not a regular file, directory, or symlink: myfifo
```

**Status:** 🚫 Refused · **Tests:** [bash #18](tests/_cases.sh#L132)

The function explicitly rejects non-regular files. Windows has no equivalent special file types.

---

## B. Destination path forms

### B1. Exact new name (rename during move)

```bash
mvln a.txt store/notes.txt
```
```powershell
Move-AsLink .\a.txt .\store\notes.txt
```

**Status:** ✅ Supported · **Tests:** [bash #22](tests/_cases.sh#L176), [#23](tests/_cases.sh#L185) · [pwsh #22](tests/Test-MoveAsLink.ps1#L217), [#23](tests/Test-MoveAsLink.ps1#L228)

The destination is used literally as the new path. Parent directories auto-created.

### B2. Existing directory, no trailing separator (nest)

```bash
mkdir bag
mvln a.txt bag       # final: bag/a.txt
```
```powershell
New-Item -ItemType Directory bag
Move-AsLink .\a.txt .\bag
```

**Status:** ✅ Supported · **Tests:** [bash #3](tests/_cases.sh#L28), [#24](tests/_cases.sh#L194), [#26b](tests/_cases.sh#L219) · [pwsh #3](tests/Test-MoveAsLink.ps1#L91), [#24](tests/Test-MoveAsLink.ps1#L241), [#26b](tests/Test-MoveAsLink.ps1#L272)

`bag` exists as a real directory, so the source's basename is appended. `bag` itself is untouched.

### B3. Trailing separator (always nest, auto-create)

```bash
mvln a.txt bag/      # final: bag/a.txt (bag/ auto-created if missing)
```
```powershell
Move-AsLink .\a.txt .\bag\
```

**Status:** ✅ Supported · **Tests:** [bash #14](tests/_cases.sh#L103), [#25](tests/_cases.sh#L203), [#27a](tests/_cases.sh#L227), [#27b](tests/_cases.sh#L234) · [pwsh #14](tests/Test-MoveAsLink.ps1#L178), [#25](tests/Test-MoveAsLink.ps1#L252), [#27a](tests/Test-MoveAsLink.ps1#L282), [#27b](tests/Test-MoveAsLink.ps1#L290)

The trailing separator unambiguously signals "container", regardless of whether the directory pre-exists.

### B4. Non-existent nested parent directories

```bash
mvln a.txt deeply/nested/path/a.txt
```
```powershell
Move-AsLink .\a.txt .\deeply\nested\path\a.txt
```

**Status:** ✅ Supported · **Tests:** [bash #4](tests/_cases.sh#L34) · [pwsh #4](tests/Test-MoveAsLink.ps1#L100)

`deeply/nested/path/` is auto-created via `mkdir -p` (bash) / `New-Item -ItemType Directory -Force` (pwsh).

### B5. Existing file, no `--force` / `-Force`

```bash
mvln a.txt store/a.txt  # if store/a.txt exists:
# mvln: destination exists: /abs/store/a.txt (use -f to overwrite)
```

**Status:** 🚫 Refused · **Tests:** [bash #5](tests/_cases.sh#L40) · [pwsh #5](tests/Test-MoveAsLink.ps1#L107)

Source is left in place; nothing is changed.

### B6. Existing file, with `--force` / `-Force`

```bash
mvln --force a.txt store/a.txt
```
```powershell
Move-AsLink .\a.txt .\store\a.txt -Force
```

**Status:** ✅ Supported · **Tests:** [bash #6](tests/_cases.sh#L47) · [pwsh #6](tests/Test-MoveAsLink.ps1#L116)

Existing destination is removed first, then the move proceeds.

### B7. Existing symlink, no `--force` / `-Force`

**Status:** 🚫 Refused · **Tests:** [bash #44](tests/_cases.sh#L371) · [pwsh #44](tests/Test-MoveAsLink.ps1#L467)

Symlinks are treated the same as files for the existing-destination check.

### B8. Same path as source

```bash
mvln a.txt ./a.txt
# mvln: source and destination are the same: /abs/a.txt
```
```powershell
Move-AsLink .\a.txt .\a.txt
```

**Status:** 🚫 Refused · **Tests:** [bash #8](tests/_cases.sh#L61) · [pwsh #8](tests/Test-MoveAsLink.ps1#L132)

Bash uses inode comparison to also catch case-insensitive collisions (`Foo.txt` vs `foo.txt` on macOS/Windows). PowerShell uses case-insensitive string compare on Windows.

### B9. Cross-volume destination

```bash
mvln big.bin /mnt/different-drive/big.bin
```
```powershell
Move-AsLink .\big.bin E:\big.bin
```

**Status:** ✅ Supported · **Tests:** [bash #20](tests/_cases.sh#L149) (Linux-only)

Underlying `mv` / `Move-Item` copies-then-deletes across volumes. Not transactional — see README Caveats.

### B10. UNC destination

**Status:** ❓ Behavior unknown · **Tests:** none (CI-untestable)

Likely works for symlink creation if SMB share supports it; unverified.

### B11. Dangling symlink as destination

**Status:** ❓ Behavior unknown · **Tests:** none (deferred)

Behavior at the existing-destination check is uncertain. Would behave like a refusal (`Test-Path` is true for the entry itself) but not pinned.

---

## C. Source types

### C1. Regular file

**Status:** ✅ Supported · **Tests:** [bash #1](tests/_cases.sh#L15) · [pwsh #1](tests/Test-MoveAsLink.ps1#L73) (plus many others)

The canonical case; exercised by almost every test.

### C2. Empty file

```bash
: > empty.txt
mvln empty.txt store/empty.txt
```
```powershell
New-Item -ItemType File empty.txt
Move-AsLink .\empty.txt .\store\empty.txt
```

**Status:** ✅ Supported · **Tests:** [bash #42](tests/_cases.sh#L357) · [pwsh #42](tests/Test-MoveAsLink.ps1#L447)

### C3. Directory (non-empty)

**Status:** ✅ Supported · **Tests:** [bash #2](tests/_cases.sh#L22) · [pwsh #2](tests/Test-MoveAsLink.ps1#L82)

Whole directory tree moved as a unit; internal structure preserved exactly.

### C4. Empty directory

**Status:** ✅ Supported · **Tests:** [bash #43](tests/_cases.sh#L364) · [pwsh #43](tests/Test-MoveAsLink.ps1#L458)

### C5. File with active open handle (Windows)

**Status:** ✅ Supported (clean error if dest-overwrite blocked) · **Tests:** [pwsh #17](tests/Test-MoveAsLink.ps1#L201)

Windows-specific: if `Force` overwrite is attempted on a destination with an open handle, the function wraps the partial-removal error with a clear message.

---

## D. Destination states

### D1. Destination doesn't exist

**Status:** ✅ Supported · **Tests:** [bash #22](tests/_cases.sh#L176) · [pwsh #22](tests/Test-MoveAsLink.ps1#L217) (canonical rename pattern)

### D2. Destination is a real directory

**Status:** ✅ Supported (nests) · **Tests:** see B2

### D3. Destination is a file

**Status:** 🚫 Refused without `--force` · **Tests:** see B5

### D4. Destination is a symlink

**Status:** 🚫 Refused without `--force` · **Tests:** see B7

### D5. Destination is a dangling symlink

**Status:** ❓ Behavior unknown · **Tests:** none

### D6. Destination's parent doesn't exist

**Status:** ✅ Supported (auto-create) · **Tests:** see B4

### D7. Destination's parent is a symlink

```bash
ln -s realdir parentlink
mvln file.txt parentlink/file.txt
```

**Status:** ✅ Supported (logical mode preserves the user-typed parent symlink) · **Tests:** [bash #19](tests/_cases.sh#L140)

---

## E. Flags / parameters — bash / zsh `mvln`

### E1. `-f` short form (force overwrite)

```bash
mvln -f src dst
```

**Status:** ✅ Supported · **Tests:** [bash #6](tests/_cases.sh#L47)

### E2. `--force` long form

```bash
mvln --force src dst
```

**Status:** ✅ Supported · **Tests:** [bash #6](tests/_cases.sh#L47)

### E3. `--resolve` (canonicalize through symlinks)

```bash
cd ~/projects/my-app   # ~/projects is itself a symlink
mvln --resolve build /mnt/cdn/build
```

**Status:** ✅ Supported · **Tests:** [bash #19](tests/_cases.sh#L140)

### E4. `-h` / `--help`

```bash
mvln -h
mvln --help
```

**Status:** ✅ Supported · **Tests:** [bash #11](tests/_cases.sh#L84)

### E5. `--` POSIX flag terminator

```bash
mvln -- -weird.txt store/-weird.txt
```

**Status:** ✅ Supported · **Tests:** [bash #16](tests/_cases.sh#L118)

### E6. Bogus flag (`--xyz`)

**Status:** 🚫 Refused with exit code 64 · **Tests:** [bash #12](tests/_cases.sh#L91)

### E7. Wrong number of positional arguments

**Status:** 🚫 Refused with exit code 64 · **Tests:** [bash #50](tests/_cases.sh#L415)

### E8. Flag combination `-f --resolve`

**Status:** ✅ Supported · **Tests:** [bash #53](tests/_cases.sh#L442)

### E9. Repeated flag (`-f -f`)

**Status:** ✅ Supported (idempotent) · **Tests:** none (implicit by flag-parsing loop semantics)

### E10. Flag after positional (`mvln src dst -f`)

**Status:** ⚪ Defined POSIX behavior (bash stops at first non-flag, so `-f` is treated as extra positional → arity check fires) · **Tests:** none (relies on standard POSIX conventions; documented elsewhere)

---

## F. Flags / parameters — PowerShell `Move-AsLink`

### F1. `-Path <string>` (positional 0, mandatory)

```powershell
Move-AsLink -Path .\a.txt -Destination .\store\a.txt
```

**Status:** ✅ Supported · **Tests:** [pwsh #54](tests/Test-MoveAsLink.ps1#L561) (named-parameter test); used positionally in every other move test

### F2. `-Destination <string>` (positional 1, mandatory)

**Status:** ✅ Supported · **Tests:** [pwsh #54](tests/Test-MoveAsLink.ps1#L561)

### F3. `-Force`

```powershell
Move-AsLink .\src .\dst -Force
```

**Status:** ✅ Supported · **Tests:** [pwsh #6](tests/Test-MoveAsLink.ps1#L116)

### F4. `-Resolve`

```powershell
Set-Location C:\symlinked\dir
Move-AsLink .\foo D:\bar -Resolve
```

**Status:** ✅ Supported · **Tests:** [pwsh #52](tests/Test-MoveAsLink.ps1#L533), [#55](tests/Test-MoveAsLink.ps1#L568)

### F5. `-Force` AND `-Resolve` combined

**Status:** ✅ Supported · **Tests:** [pwsh #55](tests/Test-MoveAsLink.ps1#L568)

### F6. `-WhatIf` (preview, do not act)

```powershell
Move-AsLink .\foo .\bar -WhatIf
```

**Status:** ✅ Supported (via `SupportsShouldProcess`) · **Tests:** [pwsh #53](tests/Test-MoveAsLink.ps1#L547)

### F7. `-Confirm` (prompt before acting)

**Status:** ✅ Supported (via `SupportsShouldProcess`) · **Tests:** none (non-interactive in CI; behavior inherited from PowerShell)

### F8. `-Force:$false` (explicit false on switch)

**Status:** ⚪ Inherited (works as a no-op like omitting the switch) · **Tests:** none

### F9. PowerShell common parameters

All of these are inherited from `[CmdletBinding()]` and work automatically. They're tested by PowerShell itself; we don't write our own tests for them.

| Parameter | Effect |
|-----------|--------|
| `-Verbose` | Enable the verbose stream |
| `-Debug` | Enable the debug stream |
| `-ErrorAction` | Error-handling preference (Stop/Continue/SilentlyContinue/Ignore) |
| `-ErrorVariable` | Capture errors into a variable |
| `-WarningAction` | Warning preference |
| `-WarningVariable` | Capture warnings |
| `-InformationAction` | Information-stream preference |
| `-InformationVariable` | Capture information |
| `-OutVariable` | Capture output stream |
| `-OutBuffer` | Output buffer size |
| `-PipelineVariable` | Name the current pipeline value |
| `-ProgressAction` (pwsh 7+) | Progress preference |

**Status:** ⚪ Inherited (all 12) · **Tests:** none (PowerShell language contract)

### F10. Bogus parameter (`-Xyz`)

**Status:** 🚫 Refused (parameter-binding error) · **Tests:** [pwsh #12](tests/Test-MoveAsLink.ps1#L162)

### F11. Too many positional arguments

**Status:** 🚫 Refused · **Tests:** [pwsh #12b](tests/Test-MoveAsLink.ps1#L166), [pwsh #50](tests/Test-MoveAsLink.ps1#L506)

### F12. Missing mandatory parameter (no positional 0 or no `-Path`)

**Status:** 🚫 Refused (PowerShell triggers an interactive prompt for the missing param; in non-interactive contexts, errors out) · **Tests:** none (would require non-interactive mode test setup)

### F13. Pipeline input

```powershell
Get-Item .\foo | Move-AsLink -Destination .\bar    # NOT supported
```

**Status:** ⛔ Unsupported by design · **Tests:** none

`$Path` is not declared with `ValueFromPipeline`. Use positional or named-parameter invocation. Use a loop if you need to move many files: `Get-ChildItem *.txt | ForEach-Object { Move-AsLink $_.FullName .\store\ }`.

---

## G. Help discovery

### G1. `mvln -h` / `mvln --help`

**Status:** ✅ Supported · **Tests:** [bash #11](tests/_cases.sh#L84)

### G2. `Get-Help Move-AsLink`

**Status:** ✅ Supported · **Tests:** [pwsh #11](tests/Test-MoveAsLink.ps1#L157)

Synopsis comes from the `<#.SYNOPSIS#>` block in `powershell/Move-AsLink.ps1`.

### G3. `Get-Help Move-AsLink -Full`

**Status:** ⚪ Inherited · **Tests:** none

### G4. `Get-Help Move-AsLink -Examples`

**Status:** ⚪ Inherited · **Tests:** none

The `.EXAMPLE` blocks in the function's doc-comment are surfaced here.

### G5. Tab-completion of parameter names

**Status:** ⚪ Inherited · **Tests:** none

PowerShell tab-completes any parameter that's declared on the function.

---

## H. Environment / invocation context

### H1. Invoked from arbitrary directory with absolute paths

**Status:** ✅ Supported · **Tests:** [bash #34](tests/_cases.sh#L283) · [pwsh #34](tests/Test-MoveAsLink.ps1#L351)

### H2. After `cd` / `Set-Location`

**Status:** ✅ Supported · **Tests:** [bash #28](tests/_cases.sh#L247), [#30](tests/_cases.sh#L262), [#35](tests/_cases.sh#L290) · [pwsh #28](tests/Test-MoveAsLink.ps1#L305), [#30](tests/Test-MoveAsLink.ps1#L323), [#35](tests/Test-MoveAsLink.ps1#L358)

This was a real bug in pwsh until commit `ca7a5c7` — the function used to resolve relative paths against the session-start directory (`[Environment]::CurrentDirectory`) instead of the user's actual location. Now uses `(Get-Location).ProviderPath`.

### H3. After `Push-Location` (pwsh)

**Status:** ✅ Supported · **Tests:** [pwsh #35](tests/Test-MoveAsLink.ps1#L358)

### H4. From a symlinked-parent directory (logical mode, default)

```bash
# ~/projects is a symlink to /mnt/work/projects
cd ~/projects/my-app
mvln build /mnt/cdn/build
readlink build
# /home/you/scratch/...   ← the parent path you typed is preserved
```

**Status:** ✅ Supported · **Tests:** [bash #19](tests/_cases.sh#L140)

### H5. From a symlinked-parent directory with `--resolve` / `-Resolve`

```bash
mvln --resolve dist /mnt/cdn/dist
readlink dist
# /mnt/cdn/dist   ← canonicalized through the parent symlink
```
```powershell
Move-AsLink .\dist E:\cdn\dist -Resolve
```

**Status:** ✅ Supported · **Tests:** [bash #19](tests/_cases.sh#L140) · [pwsh #52](tests/Test-MoveAsLink.ps1#L533)

### H6. From `HKLM:\` or other non-FileSystem PSDrive (pwsh)

```powershell
Set-Location HKLM:\SOFTWARE
Move-AsLink .\foo .\bar
# Move-AsLink: current location is not a filesystem path (HKLM:\SOFTWARE).
# Use an absolute filesystem path, or Set-Location to a filesystem path first.
```

**Status:** 🚫 Refused with clear error · **Tests:** [pwsh #56](tests/Test-MoveAsLink.ps1#L577)

Defensive guard added in commit `ca7a5c7` alongside the cwd fix.

### H7. Windows without Developer Mode (symlinks not permitted)

**Status:** 🚫 Refused before any data moves (pre-flight probe) · **Tests:** none directly (implicit in symlink-requiring cases that get skipped when `$canSymlink` is false)

Enable Developer Mode (Settings → System → For developers) or run an elevated shell.

### H8. Two concurrent `mvln` / `Move-AsLink` invocations on the same destination (TOCTOU)

**Status:** 🚫 Caveat (race window between existence check and `mv`) · **Tests:** none (not feasible in CI)

Documented in the README Caveats. Don't run two invocations against the same destination concurrently.

### H9. Custom `cd` function with side effects (bash)

```bash
cd() { builtin cd "$@" && ls; }   # common in dotfiles
mvln src dst
```

**Status:** ✅ Supported · **Tests:** [bash #21](tests/_cases.sh#L160)

Hardened in commit `b47de88` via `builtin cd` and `command pwd` calls so user-function overrides don't leak into path resolution.

### H10. Custom `Get-Location` override (pwsh)

**Status:** ❓ Behavior unknown · **Tests:** none

PowerShell doesn't have a `builtin` equivalent to bypass a user-defined function. Would need investigation.

---

## I. Cross-cutting / unusual

### I1. Source = parent of destination (self-referential)

```bash
mkdir parent
mvln parent parent/child   # would create infinite-nest hazard
# Rejected by mv's self-subdirectory check.
```

**Status:** 🚫 Refused · **Tests:** [bash #46](tests/_cases.sh#L386) · [pwsh #46](tests/Test-MoveAsLink.ps1#L483)

### I2. Source nested inside destination directory (basename collision)

```bash
mkdir bag
touch bag/item
mvln bag/item bag   # after basename-append: dst = bag/item == src
```

**Status:** 🚫 Refused (same-path check fires) · **Tests:** [bash #47](tests/_cases.sh#L393) · [pwsh #47](tests/Test-MoveAsLink.ps1#L489)

### I3. `--force` / `-Force` with same source and destination path

**Status:** 🚫 Refused (same-path check fires before force overrides) · **Tests:** [bash #45](tests/_cases.sh#L379) · [pwsh #45](tests/Test-MoveAsLink.ps1#L476)

### I4. Symlink onto its own target

**Status:** ❓ Behavior unknown · **Tests:** none

A potential self-referential hazard if `-Force` is used. Not pinned.

### I5. Very large directory (thousands of files)

**Status:** ⚪ Supported (OS-level perf, not function concern) · **Tests:** none

### I6. Cross-volume / cross-filesystem move

```bash
mvln big.bin /mnt/other-drive/big.bin
```

**Status:** ✅ Supported · **Tests:** [bash #20](tests/_cases.sh#L149) (Linux tmpfs)

Underlying `mv` / `Move-Item` copies-then-deletes across volumes. Not transactional.

### I7. Writes through the resulting symlink propagate

```bash
mvln a.txt store/a.txt
echo "new content" > a.txt   # writes through the symlink to store/a.txt
cat store/a.txt              # "new content"
```

**Status:** ✅ Supported · **Tests:** [bash #10](tests/_cases.sh#L77) · [pwsh #10](tests/Test-MoveAsLink.ps1#L149)

This is the whole point of the tool — your file appears to live where it used to, but the bytes are actually on the bulk drive.

### I8. Symlink target is always absolute

**Status:** ✅ Supported · **Tests:** [bash #13](tests/_cases.sh#L96) · [pwsh #13](tests/Test-MoveAsLink.ps1#L170)

The created symlink uses an absolute target path, so it remains valid if the source location changes.

### I9. Bash shell function override hardening

`mvln.sh` uses `builtin cd`, `builtin pwd`, `command dirname`, `command basename`, `command ls` to bypass user-defined function overrides that could corrupt path resolution.

**Status:** ✅ Supported · **Tests:** [bash #21](tests/_cases.sh#L160)

---

## J. Real-world recipes (use-case examples)

The shapes above describe the *syntax*. Below are *applications* — patterns users commonly want.

### J1. Symlink a config file into a dotfiles repo

```bash
mvln ~/.gitconfig ~/dotfiles/git/gitconfig
ls -la ~/.gitconfig
# lrwxrwxrwx ... ~/.gitconfig -> ~/dotfiles/git/gitconfig
```
```powershell
Move-AsLink $HOME\.gitconfig $HOME\dotfiles\git\gitconfig
```

**Status:** ✅ Supported (Pattern 1: file → exact new path) · **See:** B1

### J2. Offload `node_modules` to a scratch SSD

```bash
cd ~/work/my-app
mvln node_modules /mnt/nvme-scratch/my-app/node_modules
```
```powershell
Set-Location C:\work\my-app
Move-AsLink .\node_modules D:\scratch\my-app\node_modules
```

**Status:** ✅ Supported (Pattern 3: directory → exact new path) · **See:** B1

### J3. Move `Downloads` folder to an external drive (trailing-slash form)

```bash
mvln ~/Downloads /media/external/
# Trailing slash means "put it inside this directory", so final = /media/external/Downloads
```
```powershell
Move-AsLink $HOME\Downloads E:\
```

**Status:** ✅ Supported (Pattern 4b: directory + trailing slash) · **See:** B3

### J4. Replace a stale offload with a fresh copy

```bash
mvln --force ./llama-70b-v2 /mnt/ml-cache/llama-70b
```
```powershell
Move-AsLink .\llama-70b-v2 D:\ml-cache\llama-70b -Force
```

**Status:** ✅ Supported · **See:** B6 (force overwrite)

### J5. Relocate a Steam game off the SSD

```bash
mvln ~/.steam/steam/steamapps/common/Cyberpunk2077 /mnt/games-hdd/Cyberpunk2077
```
```powershell
Move-AsLink "C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077" `
            "D:\Games\Cyberpunk 2077"
```

**Status:** ✅ Supported · **Notes:** Steam re-launches the game transparently via the symlink. ~80 GB freed.

### J6. Move a Hugging Face cache to bulk storage

```bash
mvln ~/.cache/huggingface /mnt/bulk-hdd/huggingface
```
```powershell
Move-AsLink $HOME\.cache\huggingface F:\bulk\huggingface
```

**Status:** ✅ Supported · **Notes:** `transformers`, `datasets`, `diffusers` all keep finding caches transparently. Cross-volume; non-transactional (see Caveats).

### J7. Offload a Docker named volume

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

**Status:** ✅ Supported · **Notes:** Stop the daemon first; moving a directory the kernel has open invites corruption.

### J8. Per-project build artifacts on scratch

```bash
cd ~/projects/my-rust-app
mvln target /mnt/scratch/my-rust-app/target
cargo build    # writes through the symlink
```
```powershell
Set-Location C:\projects\my-rust-app
Move-AsLink .\target D:\scratch\my-rust-app\target
```

**Status:** ✅ Supported · **Notes:** `cargo`, `npm`, `gradle`, `make` all write transparently.

---

## K. Coverage scorecard

| Category | Cells | ✅ tested | ⚪ inherited | 🚫 tested | 📝 gap | ❓ unknown |
|----------|------:|----------:|-------------:|----------:|-------:|-----------:|
| A. Source forms | 22 | 14 | 0 | 4 | 2 | 2 |
| B. Destination forms | 11 | 7 | 0 | 3 | 1 | 0 |
| C. Source types | 5 | 5 | 0 | 0 | 0 | 0 |
| D. Destination states | 7 | 4 | 0 | 2 | 0 | 1 |
| E. bash flags | 10 | 8 | 2 | 2 | 0 | 0 |
| F. pwsh params | 13 (+ 12 common) | 6 | 14 | 2 | 4 | 0 |
| G. Help discovery | 5 | 2 | 3 | 0 | 0 | 0 |
| H. Environment | 10 | 7 | 0 | 2 | 1 | 1 |
| I. Cross-cutting | 9 | 7 | 1 | 1 | 1 | 1 |
| **Totals** | **~104** | **60** | **20** | **16** | **9** | **5** |

**Reading the totals:** 76 cells have explicit CI guarantees we own (60 supported + 16 refusal-pinned). 20 are inherited from PowerShell's language contract (not our test surface). 9 are genuine "no test yet" gaps. 5 are open questions where the behavior itself is uncertain.

---

## L. Full case-to-test cross-reference

| Case | bash | pwsh | Pins |
|------|------|------|------|
| 1 | [#L15](tests/_cases.sh#L15) | [#L73](tests/Test-MoveAsLink.ps1#L73) | file → symlink basic |
| 2 | [#L22](tests/_cases.sh#L22) | [#L82](tests/Test-MoveAsLink.ps1#L82) | directory → symlink basic |
| 3 | [#L28](tests/_cases.sh#L28) | [#L91](tests/Test-MoveAsLink.ps1#L91) | file → existing dir nest |
| 4 | [#L34](tests/_cases.sh#L34) | [#L100](tests/Test-MoveAsLink.ps1#L100) | auto-create missing parent |
| 5 | [#L40](tests/_cases.sh#L40) | [#L107](tests/Test-MoveAsLink.ps1#L107) | refuses existing dest without --force |
| 6 | [#L47](tests/_cases.sh#L47) | [#L116](tests/Test-MoveAsLink.ps1#L116) | --force overwrites, re-points symlink |
| 7 | [#L55](tests/_cases.sh#L55) | [#L127](tests/Test-MoveAsLink.ps1#L127) | source missing → error |
| 8 | [#L61](tests/_cases.sh#L61) | [#L132](tests/Test-MoveAsLink.ps1#L132) | same path src/dst rejected |
| 9 | [#L67](tests/_cases.sh#L67) | [#L138](tests/Test-MoveAsLink.ps1#L138) | symlink source preserved (not dereferenced) |
| 10 | [#L77](tests/_cases.sh#L77) | [#L149](tests/Test-MoveAsLink.ps1#L149) | writes propagate through symlink |
| 11 | [#L84](tests/_cases.sh#L84) | [#L157](tests/Test-MoveAsLink.ps1#L157) | help discovery |
| 12 | [#L91](tests/_cases.sh#L91) | [#L162](tests/Test-MoveAsLink.ps1#L162) | bogus flag rejected (exit 64 bash) |
| 12b | — | [#L166](tests/Test-MoveAsLink.ps1#L166) | extra positional rejected (pwsh) |
| 13 | [#L96](tests/_cases.sh#L96) | [#L170](tests/Test-MoveAsLink.ps1#L170) | symlink target is absolute |
| 14 | [#L103](tests/_cases.sh#L103) | [#L178](tests/Test-MoveAsLink.ps1#L178) | trailing-slash dest is container |
| 15 | [#L109](tests/_cases.sh#L109) (trailing-slash src) | [#L186](tests/Test-MoveAsLink.ps1#L186) (dangling symlink) | platform-specific |
| 16 | [#L118](tests/_cases.sh#L118) (leading-dash) | [#L193](tests/Test-MoveAsLink.ps1#L193) (Target normalization) | platform-specific |
| 17 | [#L124](tests/_cases.sh#L124) (dangling symlink) | [#L201](tests/Test-MoveAsLink.ps1#L201) (open-handle) | platform-specific |
| 18 | [#L132](tests/_cases.sh#L132) | — | FIFO rejection (POSIX-only) |
| 19 | [#L140](tests/_cases.sh#L140) | — | logical-mode preserves symlinked parent |
| 20 | [#L149](tests/_cases.sh#L149) | — | cross-filesystem move (Linux tmpfs) |
| 21 | [#L160](tests/_cases.sh#L160) | — | custom cd override hardening (bash) |
| 22 | [#L176](tests/_cases.sh#L176) | [#L217](tests/Test-MoveAsLink.ps1#L217) | file → exact NEW name (rename) |
| 23 | [#L185](tests/_cases.sh#L185) | [#L228](tests/Test-MoveAsLink.ps1#L228) | directory → exact NEW name |
| 24 | [#L194](tests/_cases.sh#L194) | [#L241](tests/Test-MoveAsLink.ps1#L241) | dir → existing dir (nest, no slash) |
| 25 | [#L203](tests/_cases.sh#L203) | [#L252](tests/Test-MoveAsLink.ps1#L252) | dir → trailing-slash (auto-create + nest) |
| 26a | [#L211](tests/_cases.sh#L211) | [#L262](tests/Test-MoveAsLink.ps1#L262) | trap: src bag, bag absent → rename |
| 26b | [#L219](tests/_cases.sh#L219) | [#L272](tests/Test-MoveAsLink.ps1#L272) | trap: src bag, bag present → nest |
| 27a | [#L227](tests/_cases.sh#L227) | [#L282](tests/Test-MoveAsLink.ps1#L282) | trailing slash always nests (dir absent) |
| 27b | [#L234](tests/_cases.sh#L234) | [#L290](tests/Test-MoveAsLink.ps1#L290) | trailing slash always nests (dir present) |
| 28 | [#L247](tests/_cases.sh#L247) | [#L305](tests/Test-MoveAsLink.ps1#L305) | (A) dot-relative file after Set-Location |
| 29 | [#L255](tests/_cases.sh#L255) | [#L313](tests/Test-MoveAsLink.ps1#L313) | (A) dot-relative dir after Set-Location |
| 30 | [#L262](tests/_cases.sh#L262) | [#L323](tests/Test-MoveAsLink.ps1#L323) | (B) bare-name source after Set-Location |
| 31 | (skipped POSIX) | [#L330](tests/Test-MoveAsLink.ps1#L330) | (C) mixed `/` `\` separators (Windows) |
| 32 | (skipped tilde / parser-level) | (skipped) | (D) reserved for tilde, see #51 instead |
| 33 | [#L274](tests/_cases.sh#L274) | [#L341](tests/Test-MoveAsLink.ps1#L341) | (E) parent-dir references (`..`) |
| 34 | [#L283](tests/_cases.sh#L283) | [#L351](tests/Test-MoveAsLink.ps1#L351) | (F) absolute path without harness cwd sync |
| 35 | [#L290](tests/_cases.sh#L290) | [#L358](tests/Test-MoveAsLink.ps1#L358) | (G) Push-Location / cd-and-back |
| 36 | [#L304](tests/_cases.sh#L304) | [#L374](tests/Test-MoveAsLink.ps1#L374) | trailing-slash on dir source + existing-dir-w/slash dest |
| 37 | [#L312](tests/_cases.sh#L312) | [#L387](tests/Test-MoveAsLink.ps1#L387) | trailing-slash on dir source + exact new name |
| 38 | [#L320](tests/_cases.sh#L320) | [#L398](tests/Test-MoveAsLink.ps1#L398) | trailing-slash on dir source + non-existent trailing-slash dest |
| 39 | [#L334](tests/_cases.sh#L334) | [#L414](tests/Test-MoveAsLink.ps1#L414) | (A11) path with spaces (quoted) |
| 40 | [#L341](tests/_cases.sh#L341) | [#L424](tests/Test-MoveAsLink.ps1#L424) | (A12) unicode filename |
| 41 | [#L348](tests/_cases.sh#L348) | [#L434](tests/Test-MoveAsLink.ps1#L434) | (A16) hardlink as source |
| 42 | [#L357](tests/_cases.sh#L357) | [#L447](tests/Test-MoveAsLink.ps1#L447) | (E1) empty file |
| 43 | [#L364](tests/_cases.sh#L364) | [#L458](tests/Test-MoveAsLink.ps1#L458) | (E2) empty directory |
| 44 | [#L371](tests/_cases.sh#L371) | [#L467](tests/Test-MoveAsLink.ps1#L467) | (B7) dest is symlink, refused |
| 45 | [#L379](tests/_cases.sh#L379) | [#L476](tests/Test-MoveAsLink.ps1#L476) | (G3) --force with same path, still refused |
| 46 | [#L386](tests/_cases.sh#L386) | [#L483](tests/Test-MoveAsLink.ps1#L483) | (G1) source = parent of dest, rejected |
| 47 | [#L393](tests/_cases.sh#L393) | [#L489](tests/Test-MoveAsLink.ps1#L489) | (G2) source nested in dest dir, same-path collision |
| 48 | [#L401](tests/_cases.sh#L401) | [#L496](tests/Test-MoveAsLink.ps1#L496) | (A10) glob source pattern is literal (no expansion) |
| 49 | [#L409](tests/_cases.sh#L409) | [#L501](tests/Test-MoveAsLink.ps1#L501) | (A20) whitespace-only source rejected |
| 50 | [#L415](tests/_cases.sh#L415) | [#L506](tests/Test-MoveAsLink.ps1#L506) | extra positional args rejected (exit 64 bash) |
| 51 | [#L421](tests/_cases.sh#L421) | [#L512](tests/Test-MoveAsLink.ps1#L512) | (A5) tilde-expanded source |
| 52 | [#L433](tests/_cases.sh#L433) (newline filename) | [#L533](tests/Test-MoveAsLink.ps1#L533) (-Resolve pwsh) | platform-specific |
| 53 | [#L442](tests/_cases.sh#L442) (-f --resolve combo) | [#L547](tests/Test-MoveAsLink.ps1#L547) (-WhatIf) | platform-specific |
| 54 | — | [#L561](tests/Test-MoveAsLink.ps1#L561) | (C8) named parameters -Path / -Destination |
| 55 | — | [#L568](tests/Test-MoveAsLink.ps1#L568) | (C11) -Force AND -Resolve combined |
| 56 | — | [#L577](tests/Test-MoveAsLink.ps1#L577) | (D7) HKLM:\ non-FileSystem PSDrive refused |
| 57 | — | [#L592](tests/Test-MoveAsLink.ps1#L592) | (A15) junction as source (Windows) |

---

## See also

- [README](README.md) — install, four destination patterns, canonical examples
- [tests/_cases.sh](tests/_cases.sh) — bash/zsh test cases
- [tests/Test-MoveAsLink.ps1](tests/Test-MoveAsLink.ps1) — pwsh test cases
- [CLAUDE.md](CLAUDE.md) — project testing policy (CI is the authoritative validator)
