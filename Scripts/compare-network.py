#!/usr/bin/env python3
"""Сверяет 64-битные счётчики приложения с netstat до и после чтения."""
import json
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]

def counters():
    output = subprocess.check_output(['/usr/sbin/netstat', '-ibn'], text=True)
    result = {}
    for line in output.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 10 and fields[2].startswith('<Link#'):
            result[fields[0]] = {'received': int(fields[6]), 'sent': int(fields[9])}
    return result

before = counters()
sample = json.loads(subprocess.check_output([str(root / '.research/probe'), '1'], text=True))
after = counters()
interface = sample['interface']
actual = {'received': sample['networkReceivedBytes'], 'sent': sample['networkSentBytes']}
checks = {key: before[interface][key] <= value <= after[interface][key] for key, value in actual.items()}
report = {'capturedAt': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'interface': interface,
          'source': 'sysctl IFMIB_IFDATA / IFDATA_GENERAL / if_data64',
          'netstatBefore': before[interface], 'app': actual, 'netstatAfter': after[interface],
          'betweenIndependentReads': checks}
(root / 'Evidence/network-counter-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
assert all(checks.values()), 'Счётчики не попали между независимыми чтениями'
