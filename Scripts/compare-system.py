#!/usr/bin/env python3
"""Сверяет общий сборщик с независимыми командами macOS, сохраняет только нужные поля."""
import subprocess,json,re,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def command(*args):return subprocess.check_output(args,text=True)
rows=[json.loads(s) for s in command(str(root/'.research/probe'),'2').splitlines()]
s=rows[-1]
vm=command('/usr/bin/vm_stat');page=int(re.search(r'page size of (\d+)',vm)[1])
fields={k.strip('"'):int(v) for k,v in re.findall(r'^(.+?):\s+(\d+)\.',vm,re.M)}
used=(fields['Pages active']+fields['Pages inactive']+fields['Pages speculative']+fields['Pages wired down']+fields['Pages occupied by compressor']-fields['Pages purgeable']-fields['File-backed pages'])*page
battery=command('/usr/bin/pmset','-g','batt');percent=int(re.search(r'(\d+)%;',battery)[1])
disk=command('/bin/df','-k','/System/Volumes/Data').splitlines()[1].split()
model=command('/usr/sbin/sysctl','-n','hw.model').strip();chip=command('/usr/sbin/sysctl','-n','machdep.cpu.brand_string').strip();physical=int(command('/usr/sbin/sysctl','-n','hw.memsize'))
report={
    'capturedAt':time.strftime('%Y-%m-%dT%H:%M:%S%z'),
    'model':{'app':s['model'],'sysctl':model,'match':s['model']==model},
    'chip':{'app':s['chip'],'sysctl':chip,'match':s['chip']==chip},
    'physicalBytes':{'app':s['memoryTotal'],'sysctl':physical,'match':s['memoryTotal']==physical},
    'memoryUsedBytes':{'app':s['memoryUsed'],'vm_stat_formula':used,'difference':s['memoryUsed']-used,'within_128MiB':abs(s['memoryUsed']-used)<128*1024**2},
    'batteryPercent':{'app':s['battery'],'pmset':percent,'match':s['battery']==percent},
    'batteryCharging':{'app':bool(s['charging']),'pmset':('charging;' in battery and 'discharging;' not in battery)},
    'storageTotalBytes':{'app':s['storageTotal'],'df':int(disk[1])*1024,'match':s['storageTotal']==int(disk[1])*1024},
    'storageFreeBytes':{'app':s['storageAvailable'],'df':int(disk[3])*1024,'difference':s['storageAvailable']-int(disk[3])*1024},
    'cpuLogicalCores':{'app':len(s['cores']),'sysctl':int(command('/usr/sbin/sysctl','-n','hw.logicalcpu'))},
    'notes':['Reads are sequential, so volatile values need a bounded tolerance.','df volume Used is not comparable to total-minus-free in a shared APFS container.','pmset and vm_stat are independent tools, but share underlying kernel/hardware sources.']}
(root/'Evidence/system-comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
assert all(v['match'] for v in report.values() if isinstance(v,dict) and 'match' in v)
assert report['memoryUsedBytes']['within_128MiB']
