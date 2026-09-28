#Requires -Version 5.1
# Snapshots of the state KutayOS changes, so every change can be put back.
# One JSON file per tweak id under %windir%\KutayOS\State. The first snapshot wins: running a tweak
# twice must not record KutayOS's own value as the original.

Set-StrictMode -Version 2.0
# Modules don't inherit the caller's preference. A non-terminating registry error must stop a
# revert, or the snapshot would be deleted although the value was never put back.
$ErrorActionPreference = 'Stop'

$script:StateRoot = Join-Path $env:windir 'KutayOS\State'
$script:IdPattern = '^[a-z0-9]+(-[a-z0-9]+)*$'
$script:Hives = @{
    HKLM = 'HKEY_LOCAL_MACHINE'
    HKCU = 'HKEY_CURRENT_USER'
    HKU  = 'HKEY_USERS'
    HKCR = 'HKEY_CLASSES_ROOT'
}

function ConvertTo-KutayProviderPath([string]$Path) {
    $hive, $rest = $Path -split '\\', 2
    if (-not $script:Hives.ContainsKey($hive)) { throw "Unknown registry hive in '$Path'" }
    "Registry::$($script:Hives[$hive])\$rest"
}

function Get-SnapshotFile([string]$Id) {
    if ($Id -cnotmatch $script:IdPattern) { throw "Invalid snapshot id '$Id' (use lowercase letters, digits and hyphens)" }
    Join-Path $script:StateRoot "$Id.json"
}

function Split-RegistryItem([string]$Item) {
    $path, $name = $Item -split '\|', 2
    if (-not $path -or -not $name) { throw "Registry item '$Item' must look like 'path|name'" }
    [pscustomobject]@{ path = $path; name = $name }
}

function Read-KutayRegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $key = Get-Item -LiteralPath (ConvertTo-KutayProviderPath $Path) -ErrorAction SilentlyContinue
    if (-not $key -or $key.GetValueNames() -notcontains $Name) {
        return [pscustomobject]@{ exists = $false; type = $null; data = $null }
    }
    $type = $key.GetValueKind($Name).ToString()
    $data = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    if ($type -eq 'Binary') { $data = [Convert]::ToBase64String($data) }
    [pscustomobject]@{ exists = $true; type = $type; data = $data }
}

function Set-KutayRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')]
        [string]$Type,
        [AllowEmptyString()][AllowEmptyCollection()]$Data
    )
    $key = ConvertTo-KutayProviderPath $Path
    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "Set $Type value")) { return }
    # New-Item -Force on an existing key wipes its values, so only create a missing key.
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
    # Plain assignments: a switch would unroll these arrays into object[] through the pipeline.
    $value = $Data
    if ($Type -eq 'Binary') { [byte[]]$value = [Convert]::FromBase64String($Data) }
    if ($Type -eq 'MultiString') { [string[]]$value = @($Data) }
    New-ItemProperty -LiteralPath $key -Name $Name -PropertyType $Type -Value $value -Force -ErrorAction Stop | Out-Null
}

function Remove-KutayRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $key = ConvertTo-KutayProviderPath $Path
    $item = Get-Item -LiteralPath $key -ErrorAction SilentlyContinue
    if ($item -and $item.GetValueNames() -contains $Name -and $PSCmdlet.ShouldProcess("$Path\$Name", 'Remove value')) {
        Remove-ItemProperty -LiteralPath $key -Name $Name -ErrorAction Stop
    }
}

function Save-KutaySnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [Parameter(Mandatory)][string[]]$Registry
    )
    $file = Get-SnapshotFile $Id
    $items = @($Registry | ForEach-Object { Split-RegistryItem $_ })
    if (Test-Path -LiteralPath $file) { return }

    $values = @($items | ForEach-Object {
            $current = Read-KutayRegistryValue -Path $_.path -Name $_.name
            [ordered]@{ path = $_.path; name = $_.name; exists = $current.exists; type = $current.type; data = $current.data }
        })
    $snapshot = [ordered]@{ id = $Id; createdAt = (Get-Date).ToString('s'); registry = $values }
    New-Item -ItemType Directory -Force -Path $script:StateRoot | Out-Null
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $snapshot -Depth 5))
}

function Restore-KutaySnapshot {
    param([Parameter(Mandatory)][string]$Id)
    $file = Get-SnapshotFile $Id
    if (-not (Test-Path -LiteralPath $file)) { return }

    $snapshot = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    foreach ($item in @($snapshot.registry)) {
        if ($item.exists) {
            Set-KutayRegistryValue -Path $item.path -Name $item.name -Type $item.type -Data $item.data
        } else {
            Remove-KutayRegistryValue -Path $item.path -Name $item.name
        }
    }
    # Only forget the snapshot once every value is back, so a failed revert can be retried.
    Remove-Item -LiteralPath $file
}

function Get-KutaySnapshotId {
    if (-not (Test-Path -LiteralPath $script:StateRoot)) { return }
    Get-ChildItem -LiteralPath $script:StateRoot -Filter *.json | Sort-Object Name | ForEach-Object { $_.BaseName }
}

Export-ModuleMember -Function Save-KutaySnapshot, Restore-KutaySnapshot, Get-KutaySnapshotId,
    Read-KutayRegistryValue, Set-KutayRegistryValue, Remove-KutayRegistryValue
