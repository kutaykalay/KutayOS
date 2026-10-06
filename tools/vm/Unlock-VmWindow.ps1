<#
.SYNOPSIS
    Fills the VMware Workstation "This virtual machine is encrypted" password pane and presses
    Continue, without bringing the window to the foreground.
.DESCRIPTION
    Invoke-TestVmReset opens the Workstation window on the running VM (the guest needs a display to
    start VMware Tools). For an encrypted VM that window asks for the password even when it is
    saved in Credential Manager. The pane is a plain Win32 dialog (#32770 with an Edit and a
    "Continue" button), so WM_SETTEXT + BM_CLICK fill it with no focus change and no keystrokes that
    could land in another window. Returns $true when the pane was found and submitted.
    Needs KUTAY_VM_PASS.
#>
[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
if (-not $env:KUTAY_VM_PASS) { throw 'KUTAY_VM_PASS is not set' }

if (-not ('KutayVmWindow' -as [type])) {
    Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class KutayVmWindow {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    const uint WM_SETTEXT = 0x000C, BM_CLICK = 0x00F5;

    static string Text(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
    static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    static List<IntPtr> Kids(IntPtr parent) {
        var r = new List<IntPtr>(); EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero); return r;
    }

    // Returns "submitted", or "" when no visible password pane exists in the given processes.
    public static string Unlock(int[] pids, string password) {
        var frames = new List<IntPtr>();
        EnumWindows((h, l) => {
            int pid; GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) >= 0 && IsWindowVisible(h) && Cls(h) == "VMUIFrame") frames.Add(h);
            return true;
        }, IntPtr.Zero);
        foreach (var frame in frames) {
            foreach (var pane in Kids(frame)) {
                if (Cls(pane) != "#32770" || !IsWindowVisible(pane)) continue;
                IntPtr edit = IntPtr.Zero, button = IntPtr.Zero; bool encrypted = false;
                foreach (var c in Kids(pane)) {
                    if (!IsWindowVisible(c)) continue;
                    string cls = Cls(c), text = Text(c);
                    if (cls == "Static" && text.StartsWith("This virtual machine is encrypted.")) encrypted = true;
                    else if (cls == "Edit") edit = c;
                    else if (cls == "Button" && text == "Continue") button = c;
                }
                if (!encrypted || edit == IntPtr.Zero || button == IntPtr.Zero) continue;
                SendMessage(edit, WM_SETTEXT, IntPtr.Zero, password);
                SendMessage(button, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
                return "submitted";
            }
        }
        return "";
    }
}
'@
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $pids = [int[]]@(Get-Process -Name vmware -ErrorAction SilentlyContinue | ForEach-Object Id)
    if ($pids.Count -gt 0 -and [KutayVmWindow]::Unlock($pids, $env:KUTAY_VM_PASS) -eq 'submitted') { return $true }
    Start-Sleep -Seconds 1
}
return $false
