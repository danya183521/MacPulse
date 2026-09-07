#!/usr/bin/env python3
"""Проверяет реакцию сетевых счётчиков на служебный трафик без передачи метрик."""
import subprocess,time,json,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1]
with open(root/'Evidence/network-samples.jsonl','w') as out:
    probe=subprocess.Popen([str(root/'.research/probe'),'30'],stdout=out)
    events=[];start=time.monotonic()
    try:
        time.sleep(3)
        events.append(['download-start',time.monotonic()-start])
        down=subprocess.run(['curl','--fail','--silent','--show-error','--max-time','15','--limit-rate','1M','https://speed.cloudflare.com/__down?bytes=8000000','-o','/dev/null'],capture_output=True,text=True)
        events.append(['download-end',time.monotonic()-start,down.returncode,down.stderr])
        time.sleep(3)
        events.append(['upload-start',time.monotonic()-start])
        up=subprocess.run(['curl','--fail','--silent','--show-error','--max-time','15','--limit-rate','512K','-X','POST','--data-binary','@-','https://speed.cloudflare.com/__up','-o','/dev/null'],input=bytes(3000000),capture_output=True)
        events.append(['upload-end',time.monotonic()-start,up.returncode,up.stderr.decode()])
        probe.wait(timeout=35)
    finally:
        if probe.poll() is None:probe.terminate()
rows=[json.loads(x) for x in open(root/'Evidence/network-samples.jsonl')]
base=rows[0]['uptime'];report={'events':events,'intervals':{}}
for title,a,b in [('idle',0,3),('download',events[0][1]+1,events[1][1]),('upload',events[2][1]+1,events[3][1])]:
    selected=[r for r in rows if a<=r['uptime']-base<=b]
    report['intervals'][title]={k:round(statistics.mean(r[k] for r in selected if k in r),1) for k in ['download','upload'] if any(k in r for r in selected)}
(root/'Evidence/network-check.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
