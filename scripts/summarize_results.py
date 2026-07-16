#!/usr/bin/env python3
import csv, json, math, re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rows=[]
def pct(values, p):
    if not values: return ""
    values=sorted(values); return values[math.ceil(p*len(values))-1]
for meta_path in sorted((root/'results/raw').glob('*/metadata.json')):
    d=meta_path.parent; meta=json.loads(meta_path.read_text())
    records=[]
    rp=d/'results.jsonl'
    if rp.exists():
        for line in rp.read_text().splitlines():
            try: records.append(json.loads(line))
            except json.JSONDecodeError: pass
    lat=[r['elapsed_us'] for r in records if isinstance(r.get('elapsed_us'),int)]
    time=(d/'time.txt').read_text() if (d/'time.txt').exists() else ''
    def field(label):
        m=re.search(rf'{re.escape(label)}:\s*([0-9:.]+)',time); return m.group(1) if m else ''
    elapsed=field('Elapsed (wall clock) time (h:mm:ss or m:ss)')
    parts=[float(x) for x in elapsed.split(':')] if elapsed else []
    wall=sum(v * (60 ** i) for i, v in enumerate(reversed(parts))) if parts else 0
    rows.append({**meta,'request_count':len(records),'success_count':sum(r.get('match') is True for r in records),'mismatch_count':sum(r.get('match') is False for r in records),'error_count':sum('error_type' in r for r in records),'wall_seconds':wall,'throughput_rps':round(len(records)/wall,3) if wall else '', 'first_us':lat[0] if lat else '', 'warm_us':lat[1] if len(lat)>1 else '', 'p50_us':pct(lat,.50),'p95_us':pct(lat,.95),'p99_us':pct(lat,.99),'max_us':max(lat) if lat else '', 'peak_rss_kib':field('Maximum resident set size (kbytes)'),'cache_before_kib':meta.get('cache_before_kib',''),'cache_after_kib':meta.get('cache_after_kib',''),'rx_bytes':meta.get('rx_bytes',''),'tx_bytes':meta.get('tx_bytes',''),'network_connect_attempts':meta.get('network_connect_attempts','')})
fields=['case','mode','platform','emulated','network_disabled','toolkit_commit','image_digest','utc_start','utc_end','exit_code','request_count','success_count','mismatch_count','error_count','wall_seconds','throughput_rps','first_us','warm_us','p50_us','p95_us','p99_us','max_us','peak_rss_kib','cache_before_kib','cache_after_kib','rx_bytes','tx_bytes','network_connect_attempts']
with (root/'results/metrics.csv').open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore'); w.writeheader(); w.writerows(rows)
