<#
.SYNOPSIS
    Creates the KutayOS test VM in VirtualBox (Windows 11 IoT Enterprise LTSC 2024).
.DESCRIPTION
    EFI + Secure Boot + TPM 2.0 (Windows 11 requirements, and the anti-cheat
    checks the playbook must not break), 6 GB RAM, 4 vCPU, 64 GB dynamic disk,
    installer ISO attached. Does nothing if the VM already exists.
    After Windows setup, install Guest Additions and take snapshot 'clean':
        VBoxManage snapshot KutayOS-Test take clean
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/new-testvm.ps1
#>
[CmdletBinding()]
param(
    [string]$Name = 'KutayOS-Test',
    [string]$IsoPath = '',
    [int]$MemoryMB = 6144,
    [int]$Cpus = 4,
    [int]$DiskMB = 65536
)

$ErrorActionPreference = 'Stop'
$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'

function Invoke-VBox {
    & $vbox @args
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') failed ($LASTEXITCODE)" }
}

function Find-LtscIso {
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $iso = Get-ChildItem -LiteralPath $downloads -Filter '*ltsc_2024*.iso' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $iso) { throw "No *ltsc_2024*.iso in $downloads. Pass -IsoPath." }
    $iso.FullName
}

try {
    if (-not (Test-Path -LiteralPath $vbox)) { throw "VBoxManage not found at $vbox" }
    if (-not $IsoPath) { $IsoPath = Find-LtscIso }
    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

    $existing = & $vbox list vms
    if ($existing -match ('^"' + [regex]::Escape($Name) + '"')) {
        Write-Output "VM '$Name' already exists; nothing to do."
        exit 0
    }

    Invoke-VBox createvm --name $Name --ostype Windows11_64 --register
    Invoke-VBox modifyvm $Name --memory=$MemoryMB --cpus=$Cpus --firmware=efi `
        --tpm-type=2.0 --graphicscontroller=vboxsvga --vram=128 `
        --clipboard-mode=bidirectional --usb-xhci=on --audio-enabled=on
    Invoke-VBox modifynvram $Name inituefivarstore
    Invoke-VBox modifynvram $Name enrollmssignatures
    Invoke-VBox modifynvram $Name enrollorclpk
    Invoke-VBox modifynvram $Name secureboot --enable

    $cfgFile = (& $vbox showvminfo $Name --machinereadable |
        Select-String '^CfgFile=').Line -replace '^CfgFile="(.*)"$', '$1'
    $disk = Join-Path (Split-Path -Parent $cfgFile) "$Name.vdi"
    Invoke-VBox createmedium disk --filename $disk --size $DiskMB --variant Standard
    Invoke-VBox storagectl $Name --name SATA --add sata --controller IntelAhci --portcount 2
    Invoke-VBox storageattach $Name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
    Invoke-VBox storageattach $Name --storagectl SATA --port 1 --device 0 --type dvddrive --medium $IsoPath

    Write-Output "Created VM '$Name' with ISO $IsoPath"
    Write-Output "Next: VBoxManage startvm $Name, install Windows, install Guest Additions, then snapshot 'clean'."
    exit 0
} catch {
    Write-Error "new-testvm failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
