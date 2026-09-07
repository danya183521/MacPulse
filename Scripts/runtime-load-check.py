#!/usr/bin/env python3
"""Короткие реальные нагрузки; исходные снимки остаются локально и исключены из git."""
import subprocess,time,json,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1]
phases=[]
with open(root/'Evidence/load-samples.jsonl','w') as out:
    probe=subprocess.Popen([str(root/'.research/probe'),'32'],stdout=out)
    try:
        start=time.monotonic();time.sleep(5)
        phases.append(('cpu-start',time.monotonic()-start))
        workers=[subprocess.Popen(['/usr/bin/yes'],stdout=subprocess.DEVNULL) for _ in range(4)]
        try:time.sleep(8)
        finally:
            for p in workers:p.terminate()
            for p in workers:p.wait()
        phases.append(('cpu-end',time.monotonic()-start));time.sleep(5)
        phases.append(('gpu-start',time.monotonic()-start))
        subprocess.run([str(root/'.research/gpu-load')],check=True)
        phases.append(('gpu-end',time.monotonic()-start));probe.wait(timeout=20)
    finally:
        if probe.poll() is None:probe.terminate()
rows=[json.loads(s) for s in open(root/'Evidence/load-samples.jsonl')]
base=rows[0]['uptime']
windows={'idle':(1,4),'cpu load':(7,12),'recovery':(14,17),'gpu load':(21,26)}
report={'phases':phases,'windows':{}}
for name,(a,b) in windows.items():
    selected=[r for r in rows if a<=r['uptime']-base<=b]
    report['windows'][name]={k:round(statistics.mean(r[k] for r in selected if k in r),3) for k in ['cpu','gpu','cpuTemperature','gpuTemperature','cpuPower','gpuPower','systemPower','packagePower','batteryPower'] if any(k in r for r in selected)}
Path(root/'Evidence/load-check.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
