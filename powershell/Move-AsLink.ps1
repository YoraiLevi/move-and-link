function Move-AsLink {
<#
.SYNOPSIS
    Move a file or directory, then replace the original location with an absolute symlink to it.
.DESCRIPTION
    If <Destination> is an existing real directory (not a reparse point), or ends in a path
    separator, the source's basename is appended.
    Refuses if the final destination already exists, unless -Force.
    Always creates a real SymbolicLink (no junction/hardlink fallback). Throws if symlink
    creation is not permitted (Developer Mode off and shell not elevated on Windows < 11).
    By default the parent directories are kept logical (symlinks preserved). Pass -Resolve
    to canonicalize through symlinks.
    Filenames that begin with `-` should be quoted; this function uses -LiteralPath internally.
.EXAMPLE
    Move-AsLink C:\Users\me\big-folder D:\storage\big-folder
.EXAMPLE
    Move-AsLink .\file.bin E:\offload\ -Force
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, Position = 1)]
        [string] $Destination,

        [switch] $Force,
        [switch] $Resolve
    )

    $cwd = [Environment]::CurrentDirectory   # Filesystem cwd, not PSDrive cwd.

    function ToAbs([string] $p) {
        if ([IO.Path]::IsPathRooted($p)) { [IO.Path]::GetFullPath($p) }
        else { [IO.Path]::GetFullPath([IO.Path]::Combine($cwd, $p)) }
    }
    function ResolveParent([string] $parentRaw) {
        $abs = ToAbs $parentRaw
        if ($Resolve) {
            try { return (Resolve-Path -LiteralPath $abs -ErrorAction Stop).ProviderPath }
            catch { return $abs }
        }
        return $abs
    }

    # --- 1. Existence (handles dangling-symlink source on Win PS 5.1) ---
    if (-not (Test-Path -LiteralPath $Path) -and `
        -not (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        $parent = [IO.Path]::GetDirectoryName($Path)
        if ([string]::IsNullOrEmpty($parent)) { $parent = $cwd }
        $leaf   = [IO.Path]::GetFileName($Path)
        $entry  = Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq $leaf } | Select-Object -First 1
        if (-not $entry) { throw "Move-AsLink: source does not exist: $Path" }
    }

    $srcParentRaw = [IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrEmpty($srcParentRaw)) { $srcParentRaw = $cwd }
    $srcParentAbs = ResolveParent $srcParentRaw
    $srcLeaf      = [IO.Path]::GetFileName($Path)
    $srcAbs       = [IO.Path]::GetFullPath([IO.Path]::Combine($srcParentAbs, $srcLeaf))

    # --- 2. Trailing-separator destination => container intent ---
    $endsWithSep = $Destination.EndsWith('/') -or $Destination.EndsWith('\')
    $isExistingRealDir = $false
    if (Test-Path -LiteralPath $Destination -PathType Container) {
        $dstItem  = Get-Item -LiteralPath $Destination -Force
        $isExistingRealDir = ($dstItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
    }
    $dstFinal = $Destination
    if ($endsWithSep -or $isExistingRealDir) {
        $dstFinal = [IO.Path]::Combine($Destination.TrimEnd('/','\'), $srcLeaf)
    }

    # --- 3. Resolve destination ---
    $dstParentRaw = [IO.Path]::GetDirectoryName($dstFinal)
    if ([string]::IsNullOrEmpty($dstParentRaw)) { $dstParentRaw = $cwd }
    if (-not (Test-Path -LiteralPath $dstParentRaw)) {
        New-Item -ItemType Directory -Path $dstParentRaw -Force -ErrorAction Stop | Out-Null
    }
    $dstParentAbs = ResolveParent $dstParentRaw
    $dstAbs       = [IO.Path]::GetFullPath([IO.Path]::Combine($dstParentAbs, [IO.Path]::GetFileName($dstFinal)))

    # --- 4. Same-path guard (case-insensitive on Windows) ---
    $samePath = if ($IsWindows -or $env:OS -eq 'Windows_NT') { $srcAbs -ieq $dstAbs }
                else { $srcAbs -eq $dstAbs }
    if ($samePath) { throw "Move-AsLink: source and destination are the same: $srcAbs" }

    # --- 5. Existing destination handling ---
    if (Test-Path -LiteralPath $dstAbs) {
        if (-not $Force) {
            throw "Move-AsLink: destination exists: $dstAbs (use -Force to overwrite)"
        }
        try {
            Remove-Item -LiteralPath $dstAbs -Recurse -Force -ErrorAction Stop
        } catch {
            throw ("Move-AsLink: destination partially removed; clean up before retrying: " +
                   "$dstAbs. Original error: $($_.Exception.Message)")
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$srcAbs -> $dstAbs", 'Move and replace with SymbolicLink')) {
        return
    }

    # --- 6. Pre-flight symlink probe at source's parent ---
    $probe = [IO.Path]::Combine($srcParentAbs, ".mvln-probe.$([guid]::NewGuid().ToString('N'))")
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Target $dstAbs -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch {
        if (Test-Path -LiteralPath $probe) {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        }
        throw ("Move-AsLink: cannot create symlinks at $srcParentAbs; aborting before move. " +
               "On Windows, enable Developer Mode (Settings -> System -> For developers) " +
               "or run an elevated shell. Original error: $($_.Exception.Message)")
    }

    # --- 7. Move + link, with rollback ---
    Move-Item -LiteralPath $srcAbs -Destination $dstAbs -ErrorAction Stop

    try {
        New-Item -ItemType SymbolicLink -Path $srcAbs -Target $dstAbs -ErrorAction Stop | Out-Null
    } catch {
        $linkErr = $_.Exception.Message
        try {
            Move-Item -LiteralPath $dstAbs -Destination $srcAbs -ErrorAction Stop
            throw "Move-AsLink: symlink creation failed; rolled back to $srcAbs. Original error: $linkErr"
        } catch {
            throw ("Move-AsLink: symlink creation failed AND rollback failed. " +
                   "Data is at $dstAbs; source path $srcAbs is gone. Original error: $linkErr")
        }
    }

    Write-Host ("Move-AsLink: {0} -> {1}" -f $srcAbs, $dstAbs)
}
