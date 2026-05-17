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

} finally {
    Set-Location $origCwd
    if (Test-Path $root) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("$script:pass passed, $script:fail failed")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
