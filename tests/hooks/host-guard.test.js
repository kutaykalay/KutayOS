const { test } = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const hook = path.join(__dirname, '..', '..', '.claude', 'hooks', 'host-guard.js');

function run(command, env = {}) {
  const res = spawnSync(process.execPath, [hook], {
    input: JSON.stringify({ tool_input: { command } }),
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
  return res.status;
}

const blocked = [
  'reg add "HKLM\\SOFTWARE\\Policies\\X" /v A /t REG_DWORD /d 0 /f',
  'Set-ItemProperty -Path HKLM:\\SOFTWARE\\X -Name A -Value 0',
  'bcdedit /set disabledynamictick yes',
  'Set-Service DiagTrack -StartupType Disabled',
  'sc.exe config DiagTrack start= disabled',
  'powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61',
  'Set-MpPreference -DisableRealtimeMonitoring $true',
  'Checkpoint-Computer -Description test',
  'powershell -File src/playbook/Executables/KutayModules/Initialize-Kutay.ps1',
  '& .\\src\\playbook\\Executables\\KutayModules\\Initialize-Kutay.ps1',
  'New-NetFirewallRule -DisplayName x -Direction Outbound -Action Block',
];

const allowed = [
  'git status',
  'cat src/playbook/Executables/KutayModules/Initialize-Kutay.ps1',
  'powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1',
  'reg query HKLM\\SOFTWARE\\Microsoft',
  'Get-Service DiagTrack',
  'powercfg /list',
  'Invoke-Pester tests',
];

for (const cmd of blocked) {
  test(`blocks: ${cmd}`, () => assert.strictEqual(run(cmd), 2));
}
for (const cmd of allowed) {
  test(`allows: ${cmd}`, () => assert.strictEqual(run(cmd), 0));
}
test('KUTAYOS_HOST_GUARD=off bypasses', () => {
  assert.strictEqual(run(blocked[0], { KUTAYOS_HOST_GUARD: 'off' }), 0);
});
