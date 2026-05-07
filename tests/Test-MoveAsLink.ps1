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
        [Environment]::CurrentDirectory = $d
        return $d
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

} finally {
    Set-Location $origCwd
    if (Test-Path $root) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host ("$script:pass passed, $script:fail failed")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
