<#
.SYNOPSIS
    Makes Lords of the Realm II (Steam/GOG) run on Windows 11.

.DESCRIPTION
    1. Downloads cnc-ddraw (DirectDraw replacement) from its official GitHub releases
       and installs it next to Lords2.exe, configured for windowed 4:3 play.
    2. Replaces the crash-causing compatibility flags (WIN98, 256COLOR, 640X480, ...)
       on Lords2.exe and the Steam launcher with plain RUNASINVOKER (current user only).
    3. Creates a desktop shortcut that starts the game from its own folder.

    No admin rights needed.

.PARAMETER GamePath
    Folder that contains Lords2.exe. Detected automatically for common Steam/GOG installs.

.PARAMETER Fullscreen
    Configure cnc-ddraw for fullscreen instead of a window.

.PARAMETER NoShortcut
    Don't create the desktop shortcut.
#>
param(
    [string]$GamePath,
    [switch]$Fullscreen,
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'

function Find-GamePath {
    $roots = @()
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($steam) {
            $roots += Join-Path $steam 'steamapps\common'
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) {
                foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    $roots += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common'
                }
            }
        }
    } catch {}
    $roots += "${env:ProgramFiles(x86)}\Steam\steamapps\common", 'C:\GOG Games', "${env:ProgramFiles(x86)}\GOG Galaxy\Games"

    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($sub in 'Lords of the Realm II\English\Lords of the Realm II', 'Lords of the Realm II', 'Lords of the Realm 2') {
            $p = Join-Path $root $sub
            if (Test-Path (Join-Path $p 'Lords2.exe')) { return $p }
        }
    }
    return $null
}

if (-not $GamePath) { $GamePath = Find-GamePath }
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'Lords2.exe'))) {
    # Allow pointing at the Steam root folder too
    if ($GamePath -and (Test-Path (Join-Path $GamePath 'English\Lords of the Realm II\Lords2.exe'))) {
        $GamePath = Join-Path $GamePath 'English\Lords of the Realm II'
    } else {
        Write-Host "Couldn't find Lords2.exe. Run again with -GamePath ""<folder containing Lords2.exe>""." -ForegroundColor Red
        exit 1
    }
}
$GamePath = (Resolve-Path $GamePath).Path
Write-Host "Game folder: $GamePath"

# --- 1. cnc-ddraw ---------------------------------------------------------
Write-Host 'Downloading cnc-ddraw...'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod 'https://api.github.com/repos/FunkyFr3sh/cnc-ddraw/releases/latest' -Headers @{ 'User-Agent' = 'lotr2-win11-fix' }
$asset = $release.assets | Where-Object { $_.name -eq 'cnc-ddraw.zip' } | Select-Object -First 1
if (-not $asset) { throw 'cnc-ddraw.zip not found in the latest cnc-ddraw release.' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('lotr2fix_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'cnc-ddraw.zip'
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath (Join-Path $tmp 'x')
    Copy-Item (Join-Path $tmp 'x\*') $GamePath -Recurse -Force
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "Installed cnc-ddraw $($release.tag_name)."

# Change settings in the main [ddraw] section only (the file also has per-game sections).
$ini = Join-Path $GamePath 'ddraw.ini'
$settings = [ordered]@{
    windowed          = $(if ($Fullscreen) { 'false' } else { 'true' })
    width             = $(if ($Fullscreen) { '0' } else { '960' })
    height            = $(if ($Fullscreen) { '0' } else { '720' })
    maintas           = 'true'
    no_compat_warning = 'true'
}
$lines = [Collections.Generic.List[string]](Get-Content $ini)
$start = $lines.IndexOf('[ddraw]')
$end = $lines.Count
for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\[') { $end = $i; break } }
foreach ($key in $settings.Keys) {
    $found = $false
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -match "^$key=") { $lines[$i] = "$key=$($settings[$key])"; $found = $true; break }
    }
    if (-not $found) { $lines.Insert($start + 1, "$key=$($settings[$key])"); $end++ }
}
Set-Content $ini $lines -Encoding ASCII
Write-Host ("Configured ddraw.ini ({0})." -f $(if ($Fullscreen) { 'fullscreen' } else { 'windowed 960x720' }))

# --- 2. Compatibility flags -----------------------------------------------
$layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
if (-not (Test-Path $layers)) { New-Item $layers -Force | Out-Null }
foreach ($exe in 'Lords2.exe', 'Launcher\LOTR2Launcher.exe') {
    $full = Join-Path $GamePath $exe
    if (Test-Path $full) {
        New-ItemProperty $layers -Name $full -Value '~ RUNASINVOKER' -PropertyType String -Force | Out-Null
        Write-Host "Reset compatibility flags: $exe"
    }
}

# --- 3. Desktop shortcut --------------------------------------------------
if (-not $NoShortcut) {
    $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Lords of the Realm II.lnk'
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $GamePath 'Lords2.exe'
    $lnk.WorkingDirectory = $GamePath   # the game quits silently without this
    $lnk.IconLocation = (Join-Path $GamePath 'Lords2.exe') + ',0'
    $lnk.Save()
    Write-Host "Created desktop shortcut: $lnkPath"
}

Write-Host ''
Write-Host 'Done. Start the game from Steam or the desktop shortcut.' -ForegroundColor Green
