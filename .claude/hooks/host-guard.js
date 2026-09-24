// Blocks system-modifying commands on the dev host; KutayOS tweaks must only run inside the test VM.
let raw = '';
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  if (process.env.KUTAYOS_HOST_GUARD === 'off') process.exit(0);
  let cmd = '';
  try {
    cmd = String(JSON.parse(raw).tool_input?.command ?? '');
  } catch {
    process.exit(0);
  }
  const rules = [
    [/(powershell|pwsh)(\.exe)?\b[^|;\n]*-(File|Command)\b[^|;\n]*playbook[\\/]+Executables/i, 'runs a playbook script'],
    [/(^|[;&|(]\s*)(\.\s+)?['"]?[^\s'"]*playbook[\\/]+Executables[\\/][^\s'"]*\.(ps1|cmd|bat)\b/i, 'runs a playbook script'],
    [/\breg(\.exe)?\s+(add|delete|import|load|unload|restore)\b/i, 'modifies the registry'],
    [/\b(Set|New|Remove|Rename)-ItemProperty\b[^\n]*\b(HKLM|HKCU|HKU|HKCR|Registry::)/i, 'modifies the registry'],
    [/\bbcdedit(\.exe)?\s+\/(set|deletevalue|delete)\b/i, 'modifies boot configuration'],
    [/\b(Set|Stop|Suspend)-Service\b|\bsc(\.exe)?\s+(config|stop|delete|failure)\b/i, 'changes services'],
    [/\bpowercfg(\.exe)?\s+[-\/](setactive|s|duplicatescheme|change|x|setacvalueindex|setdcvalueindex|delete|import)\b/i, 'changes power settings'],
    [/\b(Set|Add|Remove)-MpPreference\b/i, 'changes Defender'],
    [/\b(Disable|Unregister)-ScheduledTask\b|\bschtasks(\.exe)?\s+\/(change|delete)\b/i, 'changes scheduled tasks'],
    [/\b(Checkpoint-Computer|Enable-ComputerRestore|Disable-ComputerRestore|Restore-Computer)\b/i, 'changes System Restore'],
    [/\b(New|Set|Remove)-NetFirewallRule\b|\bnetsh\s+advfirewall\b/i, 'changes the firewall'],
  ];
  for (const [re, what] of rules) {
    if (re.test(cmd)) {
      process.stderr.write(
        `KutayOS host-guard: this command ${what} on the dev host. ` +
          'Run it inside the LTSC 2024 test VM instead. ' +
          'If the user explicitly wants it on the host, they can set KUTAYOS_HOST_GUARD=off.\n'
      );
      process.exit(2);
    }
  }
  process.exit(0);
});
