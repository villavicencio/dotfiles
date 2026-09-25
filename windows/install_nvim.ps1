#Requires -Version 7
<#
.SYNOPSIS
    Windows counterpart of helpers/install_nvim.sh: restore the nvim plugin set
    pinned in nvim/lazy-lock.json, headlessly, and verify every pin.

.DESCRIPTION
    install.ps1 runs this after it links %LOCALAPPDATA%\nvim -> nvim/. It is also
    runnable on its own:  pwsh -File windows/install_nvim.ps1 [-DryRun]

    Same sequence as the POSIX helper (read that file's comments for the why):
      1. snapshot the lockfile
      2. `nvim --headless +qa` - lazy.nvim bootstraps itself and installs the
         missing plugins. On a fresh machine this DRIFTS pins and rewrites the
         lockfile through the link (plugins imported from NvChad lose their lock
         entry between install rounds), so:
      3. put the snapshot back, then `Lazy! restore` to the pinned commits
      4. put the snapshot back again, and verify with helpers/nvim_verify_lock.lua
    An nvim older than 0.12 is upgraded with winget first (install.ps1 imports with
    --no-upgrade); if it is still too old, that is a failure.
    A missing nvim is a failure too, because Neovim.Neovim is in windows/packages.json;
    -AllowMissing turns it into a skip, and -NoUpgrade makes a too-old nvim fail without
    running winget (install.ps1 passes both under -SkipPackages).
    The config dir nvim reports must resolve (links and junctions followed) to this
    repo's nvim/; anything else fails before nvim touches it.
    Exit code: 0 ok (or skipped under -AllowMissing), 1 nvim missing or too old,
    config dir not the repo's nvim/, snapshot or restore failure, or incomplete bootstrap.
#>
param([switch]$DryRun, [switch]$AllowMissing, [switch]$NoUpgrade)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot
$MinNvim = [version]'0.12'   # the pinned nvim-treesitter (main) requires 0.12

if ($DryRun) {
    Write-Host '[dry-run] would bootstrap nvim plugins: nvim --headless "+Lazy! restore" +qa' -ForegroundColor Yellow
    exit 0
}
if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) {
    # winget import runs with --ignore-unavailable, so a Neovim that failed to install
    # would otherwise pass through both steps silently.
    if ($AllowMissing) {
        Write-Warning 'nvim not on PATH - skipping the plugin bootstrap (-AllowMissing).'
        exit 0
    }
    Write-Warning 'nvim not on PATH - cannot bootstrap the plugins. Install Neovim.Neovim (winget) and re-run.'
    exit 1
}
function Get-NvimVersionLine { (& nvim --version | Select-Object -First 1) }
function Test-NvimNewEnough([string]$line) {
    $line -match 'v(\d+)\.(\d+)' -and [version]"$($Matches[1]).$($Matches[2])" -ge $MinNvim
}
# An installed-but-too-old nvim is a failure, not a skip: install.ps1 imports with
# --no-upgrade, so a machine that already had 0.11 keeps it. Upgrade it and re-check;
# exit 1 (recorded by install.ps1) if that still does not reach the minimum.
$verLine = Get-NvimVersionLine
if (-not (Test-NvimNewEnough $verLine) -and $NoUpgrade) {
    # install.ps1 -SkipPackages: never touch packages, so fail instead of upgrading.
    Write-Warning "this config needs Neovim $MinNvim+, found '$verLine'. Upgrade it (winget upgrade --id Neovim.Neovim -e) and re-run."
    exit 1
}
if (-not (Test-NvimNewEnough $verLine)) {
    Write-Host "Neovim is too old for this config ('$verLine'); running winget upgrade --id Neovim.Neovim -e..."
    winget upgrade --id Neovim.Neovim -e --accept-package-agreements --accept-source-agreements
    # The MSI keeps its install dir, but pick up any PATH change it made anyway.
    $env:Path = (@($env:Path) + [Environment]::GetEnvironmentVariable('Path', 'Machine') +
        [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
    $verLine = Get-NvimVersionLine
    if (-not (Test-NvimNewEnough $verLine)) {
        Write-Warning "this config needs Neovim $MinNvim+, found '$verLine' at $((Get-Command nvim).Source)."
        exit 1
    }
}

# Ask nvim where its config lives (%LOCALAPPDATA%\nvim unless XDG_CONFIG_HOME is set)
# rather than hardcoding it. --clean: don't load the config (and its installer) for this.
$configDir = (& nvim --clean --headless --cmd "lua io.write(vim.fn.stdpath('config'))" +qa) -join ''

# The real path of $Path with every symlink and junction on it followed (its parents
# too), or $null when it does not exist or cannot be resolved.
function Resolve-RealPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt [IO.Path]::GetPathRoot($full).Length) { $full = $full.TrimEnd('\', '/') }
    $parent = [IO.Path]::GetDirectoryName($full)
    if ($parent) {
        $realParent = Resolve-RealPath $parent
        if (-not $realParent) { return $null }
        $full = Join-Path $realParent ([IO.Path]::GetFileName($full))
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if ($item.LinkType -in 'SymbolicLink', 'Junction') {
        $target = $item.ResolveLinkTarget($true)
        if (-not $target -or -not $target.Exists) { return $null }
        return Resolve-RealPath $target.FullName
    }
    $item.FullName
}
# The config dir must BE this repo's nvim/ (through the install.ps1 link), or the
# bootstrap below would install, restore and rewrite someone else's config: a real
# %LOCALAPPDATA%\nvim that could not be moved aside keeps the link from being made.
# Compare resolved paths, not just "a lazy-lock.json exists". Nothing in that
# directory is touched on failure.
try {
    $realConfig = Resolve-RealPath $configDir
    $realRepoNvim = Resolve-RealPath (Join-Path $Repo 'nvim')
} catch {
    $realConfig = $null   # e.g. a link cycle
}
if (-not $realConfig -or -not $realRepoNvim -or
    -not [string]::Equals($realConfig, $realRepoNvim, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Warning "nvim's config dir $configDir is not this repo's nvim/ - not bootstrapping."
    Write-Host "  resolves to: $(if ($realConfig) { $realConfig } else { '(missing)' }); expected: $(Join-Path $Repo 'nvim')"
    Write-Host '  Move that directory aside and run install.ps1 (it links %LOCALAPPDATA%\nvim to the repo).'
    exit 1
}
$lock = Join-Path $configDir 'lazy-lock.json'
if (-not (Test-Path -LiteralPath $lock)) {
    Write-Warning "no lockfile at $lock - is $configDir linked to nvim/? (run install.ps1 first)"
    exit 1
}

function Test-SameBytes([string]$a, [string]$b) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b))
}
function Restore-Pins {
    # Byte-compare so a clean run never touches the tracked file. Otherwise copy to a
    # sibling temp file, prove it, and move it over the lockfile, so the tracked file
    # is never truncated by a failed write. On failure the snapshot is kept.
    if (Test-SameBytes $lock $pinned) { return }
    $tmpLock = Join-Path (Split-Path $lock) ".lazy-lock.json.restore.$PID"
    try {
        Copy-Item -LiteralPath $pinned $tmpLock -Force
        if (-not (Test-SameBytes $tmpLock $pinned)) { throw 'temp copy does not match the pins' }
        Move-Item -LiteralPath $tmpLock $lock -Force
        if (-not (Test-SameBytes $lock $pinned)) { throw 'lockfile does not match the pins after the move' }
    } catch {
        Remove-Item -LiteralPath $tmpLock -Force -ErrorAction SilentlyContinue
        $script:keepPinned = $true
        throw "could not restore the pinned $lock (it is left drifted; the pins are kept at $pinned): $($_.Exception.Message)"
    }
    Write-Host '    restored the pinned lazy-lock.json (the bootstrap install had rewritten it)'
}

$pinned = $null; $diag = $null; $keepPinned = $false
try {
    $pinned = New-TemporaryFile
    $diag = New-TemporaryFile
    # The snapshot is the only copy of the pins once nvim starts: prove it complete
    # (non-empty, byte-equal) before launching nvim. Restore-Pins only ever writes from it.
    Copy-Item -LiteralPath $lock $pinned -Force
    if ((Get-Item $pinned).Length -eq 0 -or -not (Test-SameBytes $lock $pinned)) {
        throw "could not snapshot $lock - not starting nvim"
    }

    Write-Host 'Bootstrapping nvim plugins (Lazy restore from pinned lazy-lock.json)...'
    # Output is ~all git progress; the restore pass keeps stderr for diagnostics.
    # Both passes must exit 0, but nvim exits 0 even when init.lua errors, so success
    # also needs every pin verified AND a clean headless load of the config.
    & nvim --headless +qa *> $null
    $bootRc = $LASTEXITCODE
    Restore-Pins
    & nvim --headless '+Lazy! restore' +qa 2> $diag > $null
    $restoreRc = $LASTEXITCODE
    Restore-Pins

    & nvim -l (Join-Path $Repo 'helpers/nvim_verify_lock.lua') $pinned.FullName
    $verifyRc = $LASTEXITCODE
    # NvChad's nvconfig module is only loaded once init.lua has run through; any
    # startup error text lands in the captured output.
    $load = (& nvim --headless "+lua io.write(package.loaded.nvconfig and 'config-loaded' or 'config-NOT-loaded')" +qa 2>&1 | Out-String).Trim()
    $loadRc = $LASTEXITCODE
    Restore-Pins   # that launch can install a still-missing plugin and rewrite the lockfile
    if ($verifyRc -eq 0 -and $bootRc -eq 0 -and $restoreRc -eq 0 -and $loadRc -eq 0 -and $load -eq 'config-loaded') {
        Write-Host 'nvim: all pinned plugins present at their locked commits and the config loads; bootstrap complete.'
        exit 0
    }
    if ($bootRc -ne 0) { Write-Warning "bootstrap pass exited $bootRc." }
    if ($restoreRc -ne 0) { Write-Warning "Lazy! restore exited $restoreRc." }
    if ($loadRc -ne 0 -or $load -ne 'config-loaded') {
        Write-Warning "the config did not load cleanly headless (exit $loadRc):"
        $load -split "`n" | ForEach-Object { "  $_" }
    }
    Write-Warning 'nvim plugin bootstrap INCOMPLETE (see above).'
    if ((Get-Item $diag).Length) {
        Write-Host '  --- last restore stderr ---'
        Get-Content $diag | ForEach-Object { "  $_" }
    }
    Write-Host '  Open nvim (it finishes installing on launch), then run :Lazy restore + :checkhealth.'
    $keepPinned = $true
    Write-Host "  The pins are kept at $pinned."
    exit 1
} catch {
    Write-Warning "nvim plugin bootstrap failed: $($_.Exception.Message)"
    $keepPinned = $true
    exit 1
} finally {
    if ($diag) { Remove-Item $diag -Force -ErrorAction SilentlyContinue }
    # A failed run keeps the snapshot: it may be the only copy of uncommitted pins.
    if ($pinned -and -not $keepPinned) { Remove-Item $pinned -Force -ErrorAction SilentlyContinue }
}
