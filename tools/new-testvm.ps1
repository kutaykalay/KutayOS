<#
.SYNOPSIS
    Creates the KutayOS test VM in VMware Workstation (Windows 11 IoT Enterprise LTSC 2024).
.DESCRIPTION
    EFI + Secure Boot (Windows 11 requirements, and the anti-cheat checks the
    playbook must not break), 6 GB RAM, 4 vCPU, 64 GB growable NVMe disk,
    installer ISO attached on SATA. Does nothing if the VM already exists.
    VMware only allows a vTPM on an encrypted VM, which cannot be scripted, so
    add it by hand before first boot:
        VM Settings > Add > Trusted Platform Module (accept "encrypt TPM files only")
    After Windows setup, install VMware Tools and take snapshot 'clean':
        vmrun snapshot "<vmx>" clean
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools/new-testvm.ps1
#>
[CmdletBinding()]
param(
    [string]$Name = 'KutayOS-Test',
    [string]$IsoPath = '',
    [string]$VmRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Virtual Machines'),
    [int]$MemoryMB = 6144,
    [int]$Cpus = 4,
    [int]$DiskGB = 64
)

$ErrorActionPreference = 'Stop'
$vmwareDir = Join-Path $env:ProgramFiles 'VMware\VMware Workstation'
$vdiskManager = Join-Path $vmwareDir 'vmware-vdiskmanager.exe'

function Find-LtscIso {
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $iso = Get-ChildItem -LiteralPath $downloads -Filter '*ltsc_2024*.iso' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $iso) { throw "No *ltsc_2024*.iso in $downloads. Pass -IsoPath." }
    $iso.FullName
}

function Get-VmxText([string]$DiskFile, [int]$MemoryMB, [int]$Cpus) {
    $pcieBridges = foreach ($i in 4..7) {
        "pciBridge$i.present = `"TRUE`""
        "pciBridge$i.virtualDev = `"pcieRootPort`""
        "pciBridge$i.functions = `"8`""
    }
    @(
        '.encoding = "UTF-8"'
        'config.version = "8"'
        'virtualHW.version = "21"'
        "displayName = `"$Name`""
        'guestOS = "windows11-64"'
        'firmware = "efi"'
        'uefi.secureBoot.enabled = "TRUE"'
        "memsize = `"$MemoryMB`""
        "numvcpus = `"$Cpus`""
        "cpuid.coresPerSocket = `"$Cpus`""
        'pciBridge0.present = "TRUE"'
        $pcieBridges
        'vmci0.present = "TRUE"'
        'hpet0.present = "TRUE"'
        'nvme0.present = "TRUE"'
        'nvme0:0.present = "TRUE"'
        "nvme0:0.fileName = `"$DiskFile`""
        'sata0.present = "TRUE"'
        'sata0:1.present = "TRUE"'
        'sata0:1.deviceType = "cdrom-image"'
        "sata0:1.fileName = `"$IsoPath`""
        'sata0:1.startConnected = "TRUE"'
        'ethernet0.present = "TRUE"'
        'ethernet0.connectionType = "nat"'
        'ethernet0.virtualDev = "e1000e"'
        'ethernet0.addressType = "generated"'
        'usb_xhci.present = "TRUE"'
        'sound.present = "TRUE"'
        'sound.virtualDev = "hdaudio"'
        'sound.autoDetect = "TRUE"'
        'tools.syncTime = "FALSE"'
    ) -join "`r`n"
}

try {
    if (-not (Test-Path -LiteralPath $vdiskManager)) { throw "VMware Workstation not found in $vmwareDir" }
    if (-not $IsoPath) { $IsoPath = Find-LtscIso }
    if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }

    $vmDir = Join-Path $VmRoot $Name
    $vmx = Join-Path $vmDir "$Name.vmx"
    if (Test-Path -LiteralPath $vmx) {
        Write-Output "VM '$Name' already exists at $vmx; nothing to do."
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $vmDir | Out-Null
    # -t 0: single growable file
    & $vdiskManager -c -s "${DiskGB}GB" -a lsilogic -t 0 (Join-Path $vmDir "$Name.vmdk")
    if ($LASTEXITCODE -ne 0) { throw "vmware-vdiskmanager failed ($LASTEXITCODE)" }
    $vmxText = Get-VmxText -DiskFile "$Name.vmdk" -MemoryMB $MemoryMB -Cpus $Cpus
    [IO.File]::WriteAllText($vmx, $vmxText, (New-Object Text.UTF8Encoding $false))

    Write-Output "Created VM '$Name' at $vmx with ISO $IsoPath"
    Write-Output "Next: open it in VMware Workstation, add a Trusted Platform Module, install Windows and VMware Tools, then snapshot 'clean'."
    exit 0
} catch {
    Write-Error "new-testvm failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
