#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ConfirmPreference = 'High'   # keep Move-AsLink's ConfirmImpact=Medium quiet.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    . (Join-Path $here '..\powershell\Move-AsLink.ps1')
} catch {
    Write-Error "Failed to dot-source Move-AsLink.ps1: $($_.Exception.Message)"
    exit 1
}

# --- tiny harness ---
$script:pass = 0; $script:fail = 0
function It([string] $name, [scriptblock] $body, [bool] $skip = $false) {
    if ($skip) { Write-Host "  $name ... SKIP"; return }
    try {
        & $body
        $script:pass++; Write-Host "  $name ... ok"
    } catch {
        $script:fail++
        Write-Host "  $name ... FAIL"
        Write-Host "    reason: $($_.Exception.Message)"
    }
}
function ShouldThrow([scriptblock] $b) {
    $threw = $false
    try { & $b } catch { $threw = $true }
    if (-not $threw) { throw "expected throw, got success" }
}
function ShouldEq($actual, $expected) {
    if ($actual -ne $expected) { throw "expected '$expected', got '$actual'" }
}
function LinkType([string] $p) { (Get-Item -LiteralPath $p -Force).LinkType }
function LinkTarget([string] $p) {
    $t = (Get-Item -LiteralPath $p -Force).Target
    if ($null -eq $t) { return $null }
    if ($t -is [array]) { return [string]$t[0] }
    return [string]$t
}

$root = Join-Path ([IO.Path]::GetTempPath()) "mvln-pwsh-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$origCwd = Get-Location
try {
    function NewCase([string] $n) {
        $d = Join-Path $root "case-$n"
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Location $d
        # Deliberately do NOT set [Environment]::CurrentDirectory. Real PowerShell users
        # navigate via Set-Location / cd, which updates $PWD (the PSDrive cwd) but leaves
        # [Environment]::CurrentDirectory (the .NET filesystem cwd) at whatever it was
        # when the session started. A previous version of this harness pre-synced the two,
        # which masked a real bug where Move-AsLink resolved relative paths against the
        # session-start dir instead of the user's actual location. We mirror real usage
        # so the bug surfaces in tests.
        return (Get-Location).ProviderPath
    }

    $onWindows = ($IsWindows -or $env:OS -eq 'Windows_NT')
    $canSymlink = $true
    if ($onWindows) {
        $probe = Join-Path $root '.canlink'
        try {
            New-Item -ItemType SymbolicLink -Path $probe -Target $root -ErrorAction Stop | Out-Null
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        } catch { $canSymlink = $false }
    }

    Write-Host "shell: pwsh $($PSVersionTable.PSVersion)  symlinks=$canSymlink"

    It '1. moves a file and leaves an absolute symlink' {
        $d = NewCase '1'
        'hello' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\a.txt | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
        ShouldEq (Get-Content (Join-Path $d 'a.txt')) 'hello'
        ShouldEq (LinkTarget (Join-Path $d 'a.txt')) (Join-Path $d 'store\a.txt')
    } -skip (-not $canSymlink)

    It '2. moves a directory and leaves a symlink' {
        $d = NewCase '2'
        New-Item -ItemType Directory src | Out-Null
        'x' | Set-Content src\inner
        Move-AsLink .\src .\store\src | Out-Null
        ShouldEq (LinkType (Join-Path $d 'src')) 'SymbolicLink'
        ShouldEq (Get-Content (Join-Path $d 'src\inner')) 'x'
    } -skip (-not $canSymlink)

    It '3. appends basename when dest is an existing dir' {
        $d = NewCase '3'
        '1' | Set-Content a.txt
        New-Item -ItemType Directory bag | Out-Null
        Move-AsLink .\a.txt .\bag | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
        if (-not (Test-Path (Join-Path $d 'bag\a.txt'))) { throw 'missing bag\a.txt' }
    } -skip (-not $canSymlink)

    It '4. creates missing destination parent' {
        $d = NewCase '4'
        '1' | Set-Content a.txt
        Move-AsLink .\a.txt .\nested\dir\a.txt | Out-Null
        if (-not (Test-Path (Join-Path $d 'nested\dir\a.txt'))) { throw 'missing nested\dir\a.txt' }
    } -skip (-not $canSymlink)

    It '5. refuses existing destination without -Force' {
        $d = NewCase '5'
        'orig' | Set-Content a.txt
        New-Item -ItemType Directory store | Out-Null
        'in-the-way' | Set-Content store\a.txt
        ShouldThrow { Move-AsLink .\a.txt .\store\a.txt }
        ShouldEq (Get-Content (Join-Path $d 'store\a.txt')) 'in-the-way'
    }

    It '6. overwrites with -Force and points the symlink at the new target' {
        $d = NewCase '6'
        'new' | Set-Content a.txt
        New-Item -ItemType Directory store | Out-Null
        'old' | Set-Content store\a.txt
        Move-AsLink .\a.txt .\store\a.txt -Force | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
        ShouldEq (Get-Content (Join-Path $d 'a.txt')) 'new'
        ShouldEq (LinkTarget (Join-Path $d 'a.txt')) (Join-Path $d 'store\a.txt')
    } -skip (-not $canSymlink)

    It '7. fails when source is missing' {
        NewCase '7' | Out-Null
        ShouldThrow { Move-AsLink .\nope.txt .\store\nope.txt }
    }

    It '8. fails when src and dst are the same path' {
        NewCase '8' | Out-Null
        '1' | Set-Content a.txt
        ShouldThrow { Move-AsLink .\a.txt .\a.txt }
    }

    It '9. relocates a symlink without dereferencing (target preserved)' {
        $d = NewCase '9'
        '1' | Set-Content real.txt
        New-Item -ItemType SymbolicLink -Path link.txt -Target (Join-Path $d 'real.txt') | Out-Null
        Move-AsLink .\link.txt .\store\link.txt | Out-Null
        ShouldEq (LinkType (Join-Path $d 'link.txt')) 'SymbolicLink'
        ShouldEq (LinkType (Join-Path $d 'store\link.txt')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'store\link.txt')) (Join-Path $d 'real.txt')
        ShouldEq (LinkTarget (Join-Path $d 'link.txt')) (Join-Path $d 'store\link.txt')
    } -skip (-not $canSymlink)

    It '10. writes propagate through the symlink to the destination' {
        $d = NewCase '10'
        'before' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\a.txt | Out-Null
        'after' | Set-Content a.txt
        ShouldEq (Get-Content (Join-Path $d 'store\a.txt')) 'after'
    } -skip (-not $canSymlink)

    It '11. exposes help via Get-Help' {
        $h = (Get-Help Move-AsLink).Synopsis
        if ([string]::IsNullOrWhiteSpace($h)) { throw 'no synopsis' }
    }

    It '12. parameter binding rejects bogus flags' {
        ShouldThrow { Move-AsLink -Bogus x y }
    }

    It '12b. positional arity (a b c) is rejected like bash exit 64' {
        ShouldThrow { Move-AsLink a b c }
    }

    It '13. creates an absolute symlink target' {
        $d = NewCase '13'
        '1' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\a.txt | Out-Null
        $t = LinkTarget (Join-Path $d 'a.txt')
        if (-not [IO.Path]::IsPathRooted($t)) { throw "target not rooted: $t" }
    } -skip (-not $canSymlink)

    It '14. trailing-slash destination is treated as a container' {
        $d = NewCase '14'
        '1' | Set-Content a.txt
        Move-AsLink .\a.txt .\newdir\ | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
        if (-not (Test-Path (Join-Path $d 'newdir\a.txt'))) { throw 'expected newdir\a.txt' }
    } -skip (-not $canSymlink)

    It '15. dangling source symlink is moved as-is' {
        $d = NewCase '15'
        New-Item -ItemType SymbolicLink -Path dangling.lnk -Target (Join-Path $d 'no_such') | Out-Null
        Move-AsLink .\dangling.lnk .\store\dangling.lnk | Out-Null
        ShouldEq (LinkType (Join-Path $d 'store\dangling.lnk')) 'SymbolicLink'
    } -skip (-not $canSymlink)

    It '16. Target normalized when (Get-Item).Target is string[] vs string' {
        $d = NewCase '16'
        '1' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\a.txt | Out-Null
        $t = LinkTarget (Join-Path $d 'a.txt')
        if ($t -isnot [string]) { throw "Target not normalized: $($t.GetType().FullName)" }
    } -skip (-not $canSymlink)

    It '17. dest partial-removal error wraps a clear message (Windows; open-handle)' {
        $d = NewCase '17'
        '1' | Set-Content a.txt
        New-Item -ItemType Directory store | Out-Null
        'x' | Set-Content store\a.txt
        $fs = [IO.File]::Open((Join-Path $d 'store\a.txt'), 'Open', 'Read', 'None')
        try {
            ShouldThrow { Move-AsLink .\a.txt .\store\a.txt -Force }
        } finally { $fs.Dispose() }
    } -skip (-not ($onWindows -and $canSymlink))

    # --- README canonical destination patterns (cases 22-27) ---
    # Pin the four documented patterns + the rename-vs-nest trap. The earlier
    # file/dir cases (1, 2, 3, 14) used same-basename sources and could not
    # distinguish "rename" from "nest"; these use distinct basenames.

    It '22. file -> exact new name renames during move' {
        $d = NewCase '22'
        'hello' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\notes.txt | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'a.txt')) (Join-Path $d 'store\notes.txt')
        if (Test-Path (Join-Path $d 'store\a.txt')) { throw 'unexpected store\a.txt' }
        if (-not (Test-Path (Join-Path $d 'store\notes.txt'))) { throw 'missing store\notes.txt' }
        ShouldEq (Get-Content (Join-Path $d 'store\notes.txt')) 'hello'
    } -skip (-not $canSymlink)

    It '23. dir -> exact new name in non-existent parent renames during move' {
        $d = NewCase '23'
        New-Item -ItemType Directory src | Out-Null
        'y' | Set-Content src\inner
        Move-AsLink .\src .\archive\src-2026 | Out-Null
        ShouldEq (LinkType (Join-Path $d 'src')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'src')) (Join-Path $d 'archive\src-2026')
        if (Test-Path (Join-Path $d 'archive\src')) { throw 'unexpected archive\src' }
        if (-not (Test-Path (Join-Path $d 'archive\src-2026\inner'))) {
            throw 'missing archive\src-2026\inner'
        }
    } -skip (-not $canSymlink)

    It '24. dir -> existing dir (no trailing slash) nests under basename' {
        $d = NewCase '24'
        New-Item -ItemType Directory src | Out-Null
        'z' | Set-Content src\inner
        New-Item -ItemType Directory bag | Out-Null
        Move-AsLink .\src .\bag | Out-Null
        ShouldEq (LinkType (Join-Path $d 'src')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'src')) (Join-Path $d 'bag\src')
        if (-not (Test-Path (Join-Path $d 'bag\src\inner'))) { throw 'missing bag\src\inner' }
    } -skip (-not $canSymlink)

    It '25. dir -> trailing-slash dest nests under basename even if dir absent' {
        $d = NewCase '25'
        New-Item -ItemType Directory src | Out-Null
        'w' | Set-Content src\inner
        Move-AsLink .\src .\bag\ | Out-Null
        ShouldEq (LinkType (Join-Path $d 'src')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'src')) (Join-Path $d 'bag\src')
        if (-not (Test-Path (Join-Path $d 'bag\src\inner'))) { throw 'missing bag\src\inner' }
    } -skip (-not $canSymlink)

    It '26a. dir -> non-existent target renames to that name (no slash)' {
        $d = NewCase '26a'
        New-Item -ItemType Directory src | Out-Null
        'a' | Set-Content src\inner
        Move-AsLink .\src .\bag | Out-Null
        ShouldEq (LinkTarget (Join-Path $d 'src')) (Join-Path $d 'bag')
        if (Test-Path (Join-Path $d 'bag\src')) { throw 'unexpected bag\src' }
        if (-not (Test-Path (Join-Path $d 'bag\inner'))) { throw 'missing bag\inner' }
    } -skip (-not $canSymlink)

    It '26b. dir -> existing dir target nests under basename (no slash)' {
        $d = NewCase '26b'
        New-Item -ItemType Directory src | Out-Null
        'b' | Set-Content src\inner
        New-Item -ItemType Directory bag | Out-Null
        Move-AsLink .\src .\bag | Out-Null
        ShouldEq (LinkTarget (Join-Path $d 'src')) (Join-Path $d 'bag\src')
        if (-not (Test-Path (Join-Path $d 'bag\src\inner'))) { throw 'missing bag\src\inner' }
    } -skip (-not $canSymlink)

    It "27a. dir -> 'bag\' with bag absent nests after auto-create" {
        $d = NewCase '27a'
        New-Item -ItemType Directory src | Out-Null
        'c' | Set-Content src\inner
        Move-AsLink .\src .\bag\ | Out-Null
        if (-not (Test-Path (Join-Path $d 'bag\src\inner'))) { throw 'missing bag\src\inner' }
    } -skip (-not $canSymlink)

    It "27b. dir -> 'bag\' with bag present nests as bag\src" {
        $d = NewCase '27b'
        New-Item -ItemType Directory src | Out-Null
        'd' | Set-Content src\inner
        New-Item -ItemType Directory bag | Out-Null
        Move-AsLink .\src .\bag\ | Out-Null
        if (-not (Test-Path (Join-Path $d 'bag\src\inner'))) { throw 'missing bag\src\inner' }
    } -skip (-not $canSymlink)

    # --- User-typed-syntax cases (28-35) ---
    # Pin the syntax real users type when their PSDrive cwd has diverged from
    # [Environment]::CurrentDirectory (i.e., they navigated via Set-Location).
    # The NewCase harness above no longer pre-syncs the two, so these tests
    # exercise the same resolution path users hit in interactive shells.

    It '28. (A) dot-relative source file resolves against PSDrive cwd' {
        $d = NewCase '28'
        'hello' | Set-Content original-file
        Move-AsLink .\original-file .\dir\ | Out-Null
        ShouldEq (LinkType (Join-Path $d 'original-file')) 'SymbolicLink'
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not $canSymlink)

    It '29. (A) dot-relative source directory resolves against PSDrive cwd' {
        $d = NewCase '29'
        New-Item -ItemType Directory original-dir | Out-Null
        'x' | Set-Content original-dir\inner
        Move-AsLink .\original-dir .\dir\ | Out-Null
        if (-not (Test-Path (Join-Path $d 'dir\original-dir\inner'))) {
            throw 'missing dir\original-dir\inner'
        }
    } -skip (-not $canSymlink)

    It '30. (B) bare-name source resolves against PSDrive cwd' {
        $d = NewCase '30'
        'hello' | Set-Content original-file
        Move-AsLink original-file dir\ | Out-Null
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not $canSymlink)

    It '31. (C) mixed forward/backslash separators (verbatim user-reported syntax)' {
        $d = NewCase '31'
        'hello' | Set-Content original-file
        Move-AsLink .\original-file ./dir/ | Out-Null
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not ($onWindows -and $canSymlink))

    # 32. (D) Tilde deliberately not tested directly. PowerShell expands ~ in the
    # parser before the function receives the string; Move-AsLink only sees the
    # already-resolved absolute path, which case 34 (F) exercises.

    It '33. (E) parent-directory references resolve from PSDrive cwd' {
        $d = NewCase '33'
        'hello' | Set-Content original-file
        New-Item -ItemType Directory subdir | Out-Null
        Set-Location subdir
        Move-AsLink ..\original-file ..\dir\ | Out-Null
        Set-Location $d
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not $canSymlink)

    It '34. (F) absolute source path works without harness cwd sync' {
        $d = NewCase '34'
        'hello' | Set-Content original-file
        Move-AsLink (Join-Path $d 'original-file') (Join-Path $d 'dir\original-file') | Out-Null
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not $canSymlink)

    It '35. (G) Push-Location updates PSDrive cwd for relative resolution' {
        $d = NewCase '35'
        'hello' | Set-Content original-file
        Set-Location $root
        Push-Location $d
        try {
            Move-AsLink .\original-file .\dir\ | Out-Null
        } finally { Pop-Location }
        ShouldEq (Get-Content (Join-Path $d 'dir\original-file')) 'hello'
    } -skip (-not $canSymlink)

    # --- Trailing-slash-on-source cases (36-38) ---
    # The user-typed shape Move-AsLink .\srcdir\ .\bagdir\ should behave
    # identically to Move-AsLink .\srcdir .\bagdir\ (the trailing slash on the
    # source is a no-op signal of "this is a directory" that we strip).

    It '36. dir source with trailing slash + existing dir target with trailing slash nests' {
        $d = NewCase '36'
        New-Item -ItemType Directory srcdir | Out-Null
        'a' | Set-Content srcdir\inner
        New-Item -ItemType Directory bagdir | Out-Null
        Move-AsLink .\srcdir\ .\bagdir\ | Out-Null
        ShouldEq (LinkType (Join-Path $d 'srcdir')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'srcdir')) (Join-Path $d 'bagdir\srcdir')
        if (-not (Test-Path (Join-Path $d 'bagdir\srcdir\inner'))) {
            throw 'missing bagdir\srcdir\inner'
        }
    } -skip (-not $canSymlink)

    It '37. dir source with trailing slash + exact new name dest renames' {
        $d = NewCase '37'
        New-Item -ItemType Directory srcdir | Out-Null
        'b' | Set-Content srcdir\inner
        Move-AsLink .\srcdir\ .\newname | Out-Null
        ShouldEq (LinkType (Join-Path $d 'srcdir')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'srcdir')) (Join-Path $d 'newname')
        if (Test-Path (Join-Path $d 'newname\srcdir')) { throw 'unexpected newname\srcdir' }
        if (-not (Test-Path (Join-Path $d 'newname\inner'))) { throw 'missing newname\inner' }
    } -skip (-not $canSymlink)

    It '38. dir source with trailing slash + non-existent dest with trailing slash nests' {
        $d = NewCase '38'
        New-Item -ItemType Directory srcdir | Out-Null
        'c' | Set-Content srcdir\inner
        Move-AsLink .\srcdir\ .\newbag\ | Out-Null
        ShouldEq (LinkType (Join-Path $d 'srcdir')) 'SymbolicLink'
        ShouldEq (LinkTarget (Join-Path $d 'srcdir')) (Join-Path $d 'newbag\srcdir')
        if (-not (Test-Path (Join-Path $d 'newbag\srcdir\inner'))) {
            throw 'missing newbag\srcdir\inner'
        }
    } -skip (-not $canSymlink)

    # --- Gap-closure cases (39-57) ---
    # Pin behavior the coverage matrix flagged as untested. Some are pwsh-specific
    # (junction, -WhatIf, named params, HKLM:\ refusal) and have no bash analog.

    It '39. (A11) path with spaces (quoted) works' {
        $d = NewCase '39'
        'x' | Set-Content 'my file.txt'
        Move-AsLink '.\my file.txt' '.\store\my file.txt' | Out-Null
        ShouldEq (LinkType (Join-Path $d 'my file.txt')) 'SymbolicLink'
        if (-not (Test-Path (Join-Path $d 'store\my file.txt'))) {
            throw 'missing store\my file.txt'
        }
    } -skip (-not $canSymlink)

    It '40. (A12) unicode filename works' {
        $d = NewCase '40'
        'x' | Set-Content 'café.txt'
        Move-AsLink '.\café.txt' '.\store\café.txt' | Out-Null
        ShouldEq (LinkType (Join-Path $d 'café.txt')) 'SymbolicLink'
        if (-not (Test-Path (Join-Path $d 'store\café.txt'))) {
            throw 'missing store\café.txt'
        }
    } -skip (-not $canSymlink)

    It '41. (A16) hardlink as source moves like a regular file' {
        $d = NewCase '41'
        'x' | Set-Content realfile.txt
        New-Item -ItemType HardLink -Path hardlink.txt -Target (Join-Path $d 'realfile.txt') | Out-Null
        Move-AsLink .\hardlink.txt .\store\hardlink.txt | Out-Null
        if (-not (Test-Path (Join-Path $d 'realfile.txt'))) {
            throw 'realfile.txt should still exist (hardlinked content untouched)'
        }
        if (-not (Test-Path (Join-Path $d 'store\hardlink.txt'))) {
            throw 'missing store\hardlink.txt'
        }
    } -skip (-not $canSymlink)

    It '42. (E1) empty file works' {
        $d = NewCase '42'
        New-Item -ItemType File empty.txt | Out-Null
        Move-AsLink .\empty.txt .\store\empty.txt | Out-Null
        if (-not (Test-Path (Join-Path $d 'store\empty.txt'))) {
            throw 'missing store\empty.txt'
        }
        $len = (Get-Item -LiteralPath (Join-Path $d 'store\empty.txt')).Length
        if ($len -ne 0) { throw "expected empty file, got length $len" }
    } -skip (-not $canSymlink)

    It '43. (E2) empty directory works' {
        $d = NewCase '43'
        New-Item -ItemType Directory empty-dir | Out-Null
        Move-AsLink .\empty-dir .\store\empty-dir | Out-Null
        if (-not (Test-Path (Join-Path $d 'store\empty-dir'))) {
            throw 'missing store\empty-dir'
        }
    } -skip (-not $canSymlink)

    It '44. (B7) dest exists as symlink is refused without -Force' {
        $d = NewCase '44'
        'src' | Set-Content src.txt
        'other' | Set-Content other.txt
        New-Item -ItemType SymbolicLink -Path sym -Target (Join-Path $d 'other.txt') | Out-Null
        ShouldThrow { Move-AsLink .\src.txt .\sym }
        if (-not (Test-Path (Join-Path $d 'src.txt'))) { throw 'src.txt should still exist' }
    } -skip (-not $canSymlink)

    It '45. (G3) -Force with same path still refused (same-path check fires first)' {
        $d = NewCase '45'
        'x' | Set-Content a.txt
        ShouldThrow { Move-AsLink .\a.txt .\a.txt -Force }
        if (-not (Test-Path (Join-Path $d 'a.txt'))) { throw 'a.txt should still exist' }
    }

    It '46. (G1) source = parent of dest is rejected' {
        NewCase '46' | Out-Null
        New-Item -ItemType Directory parent | Out-Null
        ShouldThrow { Move-AsLink .\parent .\parent\child }
    } -skip (-not $canSymlink)

    It '47. (G2) source nested inside dest dir collides via same-path check' {
        NewCase '47' | Out-Null
        New-Item -ItemType Directory bag | Out-Null
        'x' | Set-Content bag\item
        ShouldThrow { Move-AsLink .\bag\item .\bag }
    } -skip (-not $canSymlink)

    It '48. (A10) glob source pattern resolves literally (no expansion)' {
        NewCase '48' | Out-Null
        ShouldThrow { Move-AsLink '*.txt' 'store\literal.txt' }
    }

    It '49. (A20) whitespace-only source path is rejected' {
        NewCase '49' | Out-Null
        ShouldThrow { Move-AsLink ' ' 'store\blank' }
    }

    It '50. extra positional arguments rejected (same as 12b but explicit)' {
        NewCase '50' | Out-Null
        'x' | Set-Content a.txt
        ShouldThrow { Move-AsLink a.txt b.txt c.txt }
    }

    It '51. (A5) tilde in source path is parser-expanded before function sees it' {
        $d = NewCase '51'
        $origHome = $env:USERPROFILE
        $origHomeUnix = $env:HOME
        try {
            $env:USERPROFILE = $d
            $env:HOME = $d
            'x' | Set-Content (Join-Path $d 'tilde.txt')
            # Pwsh's path provider resolves ~ via Get-PSDrive Home; this varies.
            # Use Resolve-Path to confirm ~ maps to $d in this context, otherwise skip.
            $tildeAbs = (Resolve-Path -Path '~/tilde.txt' -ErrorAction SilentlyContinue).Path
            if ($tildeAbs -and ($tildeAbs -eq (Join-Path $d 'tilde.txt'))) {
                Move-AsLink ~/tilde.txt (Join-Path $d 'store\tilde.txt') | Out-Null
                if (-not (Test-Path (Join-Path $d 'store\tilde.txt'))) {
                    throw 'missing store\tilde.txt'
                }
            }
            # If pwsh's ~ didn't follow our env override, the test is effectively
            # a no-op — pwsh's tilde resolution is provider-tied, not env-tied.
        } finally {
            $env:USERPROFILE = $origHome
            $env:HOME = $origHomeUnix
        }
    } -skip (-not $canSymlink)

    It '52. (C3b) -Resolve canonicalizes through a symlinked parent' {
        $d = NewCase '52'
        New-Item -ItemType Directory real | Out-Null
        'orig' | Set-Content real\a.txt
        New-Item -ItemType SymbolicLink -Path link -Target (Join-Path $d 'real') | Out-Null
        Set-Location link
        try {
            Move-AsLink .\a.txt (Join-Path $d 'dest.txt') -Resolve | Out-Null
        } finally { Set-Location $d }
        if (-not (Test-Path (Join-Path $d 'dest.txt'))) {
            throw 'missing dest.txt'
        }
    } -skip (-not $canSymlink)

    It '53. (C6) -WhatIf does not actually move' {
        $d = NewCase '53'
        'hello' | Set-Content a.txt
        Move-AsLink .\a.txt .\store\a.txt -WhatIf | Out-Null
        # File should still be at original location and NOT yet a symlink.
        $item = Get-Item -LiteralPath (Join-Path $d 'a.txt')
        if ($item.LinkType -eq 'SymbolicLink') {
            throw 'should not have created symlink under -WhatIf'
        }
        if (Test-Path (Join-Path $d 'store\a.txt')) {
            throw 'should not have moved under -WhatIf'
        }
    }

    It '54. (C8) named parameters -Path / -Destination work' {
        $d = NewCase '54'
        'x' | Set-Content a.txt
        Move-AsLink -Path .\a.txt -Destination .\store\a.txt | Out-Null
        ShouldEq (LinkType (Join-Path $d 'a.txt')) 'SymbolicLink'
    } -skip (-not $canSymlink)

    It '55. (C11) -Force AND -Resolve combined' {
        $d = NewCase '55'
        'new' | Set-Content a.txt
        New-Item -ItemType Directory store | Out-Null
        'old' | Set-Content store\a.txt
        Move-AsLink .\a.txt .\store\a.txt -Force -Resolve | Out-Null
        ShouldEq (Get-Content (Join-Path $d 'a.txt')) 'new'
    } -skip (-not $canSymlink)

    It '56. (D7) HKLM:\ (non-FileSystem PSDrive) is refused with clear error' {
        $origLoc = Get-Location
        try {
            Set-Location HKLM:\SOFTWARE -ErrorAction Stop
            $threw = $false
            try { Move-AsLink .\foo .\bar } catch {
                $threw = $true
                if ($_.Exception.Message -notmatch 'not a filesystem path') {
                    throw "error message should mention 'not a filesystem path'; got: $($_.Exception.Message)"
                }
            }
            if (-not $threw) { throw 'should have thrown' }
        } finally { Set-Location $origLoc }
    } -skip (-not $onWindows)

    It '57. (A15) junction as source is moved (not dereferenced)' {
        $d = NewCase '57'
        New-Item -ItemType Directory target | Out-Null
        'x' | Set-Content target\inner
        New-Item -ItemType Junction -Path junc -Target (Join-Path $d 'target') | Out-Null
        Move-AsLink .\junc .\store\junc | Out-Null
        # The real 'target' should be untouched (junction was moved, not dereferenced).
        if (-not (Test-Path (Join-Path $d 'target\inner'))) {
            throw 'target should still exist at original location'
        }
        # store\junc should exist (either as a junction or symlink — both acceptable).
        if (-not (Test-Path (Join-Path $d 'store\junc'))) {
            throw 'missing store\junc'
        }
    } -skip (-not ($onWindows -and $canSymlink))

} finally {
    Set-Location $origCwd
    if (Test-Path $root) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("$script:pass passed, $script:fail failed")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
