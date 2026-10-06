#Requires -Version 5.1
# System states that are not single registry values: hibernation, Compact OS, reserved storage and
# scheduled tasks. Each kind is read and set through the tool Microsoft documents for it, and every
# change is checked by reading the state back, so a tool that reports success without changing
# anything fails here.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:States = @{
    Hibernation     = 'On', 'Off'
    CompactOS       = 'Always', 'Never'
    ReservedStorage = 'Enabled', 'Disabled'
    # Absent: this Windows build does not have the task. Only a snapshot records it; setting it is a no-op.
    ScheduledTask   = 'Enabled', 'Disabled', 'Absent'
}
# Kinds that name one item of many (a task), so they need -Name.
$script:NamedKinds = @('ScheduledTask')
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

function Assert-KutayStateTarget([string]$Kind, [string]$Name) {
    if ($script:NamedKinds -contains $Kind -and -not $Name) { throw "$Kind needs -Name" }
    if ($script:NamedKinds -notcontains $Kind -and $Name) { throw "$Kind takes no -Name" }
}

# '\Microsoft\Windows\Defrag\ScheduledDefrag' -> TaskPath '\Microsoft\Windows\Defrag\', TaskName 'ScheduledDefrag'
function Split-KutayTaskName([string]$Name) {
    $cut = $Name.LastIndexOf('\')
    if (-not $Name.StartsWith('\') -or $cut -eq $Name.Length - 1) {
        throw "Task '$Name' must be a full path such as \Microsoft\Windows\Folder\Task"
    }
    [pscustomobject]@{ TaskPath = $Name.Substring(0, $cut + 1); TaskName = $Name.Substring($cut + 1) }
}

function Get-KutayScheduledTaskState([string]$Name) {
    $target = Split-KutayTaskName $Name
    # Only "not found" means Absent. Any other error (Schedule service down, access denied) must stop
    # the tweak: read as Absent it would be skipped and snapshotted wrong.
    try {
        $task = @(Get-ScheduledTask -TaskPath $target.TaskPath -TaskName $target.TaskName -ErrorAction Stop)
    } catch {
        if ($_.CategoryInfo.Category -eq 'ObjectNotFound') { return 'Absent' }
        throw
    }
    if ($task.Count -eq 0) { return 'Absent' }
    if ($task.Count -gt 1) { throw "Task '$Name' matches more than one task" }
    $task = $task[0]
    # Ready, Running and Queued all mean the task will run.
    if ([string]$task.State -eq 'Disabled') { return 'Disabled' }
    return 'Enabled'
}

function Get-KutaySystemState {
    param(
        [Parameter(Mandatory)][ValidateSet('Hibernation', 'CompactOS', 'ReservedStorage', 'ScheduledTask')][string]$Kind,
        [string]$Name = ''
    )
    Assert-KutayStateTarget $Kind $Name
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
        'ScheduledTask' { return Get-KutayScheduledTaskState $Name }
    }
}

function Set-KutaySystemState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('Hibernation', 'CompactOS', 'ReservedStorage', 'ScheduledTask')][string]$Kind,
        [Parameter(Mandatory)][string]$State,
        [string]$Name = ''
    )
    Assert-KutayStateName $Kind $State
    Assert-KutayStateTarget $Kind $Name
    $target = $Kind
    if ($Name) { $target = "$Kind $Name" }
    # Returns $true when the state is $State afterwards, $false when it was left as it is.
    $current = Get-KutaySystemState -Kind $Kind -Name $Name
    if ($current -eq $State) { return $true }
    # A task can be missing on this build (or was missing when the snapshot was taken and appeared
    # since, through an update). There is nothing KutayOS changed, so leave it as Windows has it.
    if ($current -eq 'Absent' -or $State -eq 'Absent') {
        Write-Warning "$target is $current, wanted $State; left as it is"
        return $false
    }
    if (-not $PSCmdlet.ShouldProcess($target, "Set to $State")) { return $false }

    switch ($Kind) {
        # Only on/off is snapshotted. The hiberfile type (/type full|reduced) is a separate setting this
        # does not touch; whether /hibernate on keeps a reduced type is unverified (no S4 in the VM).
        'Hibernation' { Invoke-KutayNativeCommand -FilePath 'powercfg.exe' -ArgumentList '/hibernate', $State.ToLowerInvariant() | Out-Null }
        'CompactOS' { Invoke-KutayNativeCommand -FilePath 'compact.exe' -ArgumentList "/CompactOS:$($State.ToLowerInvariant())" | Out-Null }
        'ReservedStorage' { Set-WindowsReservedStorageState -State $State | Out-Null }
        'ScheduledTask' {
            $task = Split-KutayTaskName $Name
            if ($State -eq 'Disabled') {
                Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName | Out-Null
            } else {
                Enable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName | Out-Null
            }
        }
    }
    $now = Get-KutaySystemState -Kind $Kind -Name $Name
    if ($now -ne $State) { throw "$target is still $now after setting it to $State" }
    return $true
}

Export-ModuleMember -Function Get-KutaySystemState, Set-KutaySystemState, Invoke-KutayNativeCommand
