#Requires -Version 5.1
# System states that are not single registry values: hibernation, Compact OS and reserved storage.
# Each kind is read and set through the tool Microsoft documents for it, and every change is checked
# by reading the state back, so a tool that reports success without changing anything fails here.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:States = @{
    Hibernation     = 'On', 'Off'
    CompactOS       = 'Always', 'Never'
    ReservedStorage = 'Enabled', 'Disabled'
}
$script:PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$script:HiberFile = Join-Path $env:SystemDrive 'hiberfil.sys'
# compact.exe /CompactOS keeps its state here (1 = compact). The WOF driver hides the compression from
# file attributes, and the compact.exe output is translated, so this value is the language-neutral
# signal. Checked in the VM (docs/measurements/slice4-disk.md).
$script:SetupKey = 'HKLM:\SYSTEM\Setup'

# Runs a console tool and throws when its exit code is not one of $SuccessCode.
function Invoke-KutayNativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$SuccessCode = @(0)
    )
    # Under 'Stop', Windows PowerShell 5.1 turns a native tool's stderr into a terminating error.
    $ErrorActionPreference = 'Continue'
    $output = & $FilePath @ArgumentList 2>&1
    $code = $LASTEXITCODE
    if ($SuccessCode -notcontains $code) {
        $text = (@($output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' '
        throw "$FilePath $($ArgumentList -join ' ') failed with exit code ${code}: $text"
    }
    $code
}

function Get-KutayRegistryNumber([string]$Key, [string]$Name) {
    $item = Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue
    if (-not $item -or -not $item.PSObject.Properties[$Name]) { return $null }
    [int64]$item.$Name
}

function Assert-KutayStateName([string]$Kind, [string]$State) {
    if ($script:States[$Kind] -notcontains $State) {
        throw "State '$State' is not valid for $Kind; use $($script:States[$Kind] -join ' or ')"
    }
}

function Get-KutaySystemState {
    param([Parameter(Mandatory)][ValidateSet('Hibernation', 'CompactOS', 'ReservedStorage')][string]$Kind)
    switch ($Kind) {
        'Hibernation' {
            # powercfg writes HibernateEnabled. A clean install may not have it yet; then the hiberfile
            # shows whether hibernation is on.
            $enabled = Get-KutayRegistryNumber $script:PowerKey 'HibernateEnabled'
            if ($null -ne $enabled) { if ($enabled -eq 1) { return 'On' } else { return 'Off' } }
            if (Test-Path -LiteralPath $script:HiberFile) { return 'On' }
            return 'Off'
        }
        'CompactOS' {
            # Windows setup writes the value when it installs compact (seen in the VM); a missing value
            # means the OS was never compacted.
            if ((Get-KutayRegistryNumber $script:SetupKey 'Compact') -eq 1) { return 'Always' }
            return 'Never'
        }
        'ReservedStorage' {
            $state = [string](Get-WindowsReservedStorageState).ReservedStorageState
            # A state revert could not set again must not reach a snapshot.
            Assert-KutayStateName $Kind $state
            return $state
        }
    }
}

function Set-KutaySystemState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('Hibernation', 'CompactOS', 'ReservedStorage')][string]$Kind,
        [Parameter(Mandatory)][string]$State
    )
    Assert-KutayStateName $Kind $State
    if ((Get-KutaySystemState -Kind $Kind) -eq $State) { return }
    if (-not $PSCmdlet.ShouldProcess($Kind, "Set to $State")) { return }

    switch ($Kind) {
        # Only on/off is snapshotted. The hiberfile type (/type full|reduced) is a separate setting this
        # does not touch; whether /hibernate on keeps a reduced type is unverified (no S4 in the VM).
        'Hibernation' { Invoke-KutayNativeCommand -FilePath 'powercfg.exe' -ArgumentList '/hibernate', $State.ToLowerInvariant() | Out-Null }
        'CompactOS' { Invoke-KutayNativeCommand -FilePath 'compact.exe' -ArgumentList "/CompactOS:$($State.ToLowerInvariant())" | Out-Null }
        'ReservedStorage' { Set-WindowsReservedStorageState -State $State | Out-Null }
    }
    $now = Get-KutaySystemState -Kind $Kind
    if ($now -ne $State) { throw "$Kind is still $now after setting it to $State" }
}

Export-ModuleMember -Function Get-KutaySystemState, Set-KutaySystemState, Invoke-KutayNativeCommand
