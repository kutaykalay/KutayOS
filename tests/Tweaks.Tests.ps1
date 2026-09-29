# Rules every tweak YAML must follow (see the project rules): title, description, a source link,
# an evidence level, and a snapshot of every registry value before it is changed.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes these variables between its blocks')]
param()

BeforeDiscovery {
    $tweakRoot = Join-Path $PSScriptRoot '..\src\playbook\Configuration\tweaks'
    $tweaks = @(Get-ChildItem -LiteralPath $tweakRoot -Recurse -Filter *.yml | ForEach-Object {
            @{ Name = "$($_.Directory.Name)/$($_.Name)"; Path = $_.FullName; Id = $_.BaseName }
        })
}

Describe 'Tweak <Name>' -ForEach $tweaks {
    BeforeAll {
        $text = Get-Content -LiteralPath $Path -Raw
    }

    It 'has a title and a description' {
        $text | Should -Match '(?m)^title:\s*\S'
        $text | Should -Match '(?m)^description:\s*\S'
    }

    It 'links a source' {
        $text | Should -Match '(?m)^\s*# Source: https?://\S+'
    }

    It 'declares an evidence level' {
        $text | Should -Match '(?m)^\s*# Evidence: (measured|documented|community)\b'
    }

    It 'snapshots every registry value before changing it' {
        $pattern = "!registryValue:\s*\{\s*path:\s*'([^']+)',\s*value:\s*'([^']+)'"
        $changes = [regex]::Matches($text, $pattern)
        foreach ($change in $changes) {
            $item = "$($change.Groups[1].Value)|$($change.Groups[2].Value)"
            $before = $text.Substring(0, $change.Index)
            $before | Should -Match ([regex]::Escape("-Id $Id ")) -Because "the snapshot id must match the file name"
            $before | Should -Match ([regex]::Escape($item)) -Because "$item must be snapshotted before it changes"
        }
    }

    It 'writes per-user values only through Set-KutayUserSetting' {
        # AME's HKCU !registryValue picks its own set of hives, which the snapshot can't follow.
        $text | Should -Not -Match "!registryValue:\s*\{\s*path:\s*'(HKCU|HKU|HKEY_CURRENT_USER|HKEY_USERS)\\"
    }

    It 'names its user settings snapshot after the file' {
        foreach ($match in [regex]::Matches($text, 'Set-KutayUserSetting\.ps1\s+-Id\s+(\S+)')) {
            $match.Groups[1].Value | Should -Be $Id
        }
    }
}
