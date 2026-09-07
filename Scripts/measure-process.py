#!/usr/bin/env python3
"""Измеряет CPU time и RSS только процесса MacPulse без изменения его состояния."""
import subprocess,time,json,sys
from pathlib import Path
pid=int(subprocess.check_output(['pgrep','-x','MacPulse'],text=True).strip().splitlines()[0])
def read():
    raw=subprocess.check_output(['ps','-p',str(pid),'-o','time=,rss='],text=True).strip().split()
    fields=raw[0].split(':');seconds=sum(float(v)*60**i for i,v in enumerate(reversed(fields)))
    return seconds,int(raw[1])
a,rss0=read();start=time.monotonic();time.sleep(30);b,rss1=read();elapsed=time.monotonic()-start
result={'pid':pid,'seconds':round(elapsed,3),'cpu_seconds':round(b-a,3),'one_core_cpu_percent':round(100*(b-a)/elapsed,3),'rss_start_MiB':round(rss0/1024,2),'rss_end_MiB':round(rss1/1024,2),'context':sys.argv[1] if len(sys.argv)>1 else 'dashboard visible'}
Path('Evidence/process-usage.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
