#!/usr/bin/env python3
"""Aggregate independent group launches; no extra Python packages required."""
import argparse
import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean, median, stdev
import re

PATTERN = re.compile(r'^(Windows|Docker|WSL)_(int_(?:add|sub|mul|div)|double_(?:add|sub|mul|div))_n(\d+)_r(\d+)_i(\d+)\.csv$')

parser = argparse.ArgumentParser()
parser.add_argument('results', nargs='?', default='results')
args = parser.parse_args()
folder = Path(args.results)
groups = defaultdict(list)
for path in folder.glob('*.csv'):
    m = PATTERN.match(path.name)
    if not m: continue
    env, test, n, round_no, idx = m.groups()
    with path.open(encoding='utf-8-sig', newline='') as file:
        rows = list(csv.DictReader(file))
    if len(rows) != 1:
        print('WARNING invalid CSV:',path)
        continue
    row = rows[0]
    try:
        groups[(env,test,int(n),int(round_no))].append({
          'index':int(idx), 'iters':int(row['iterations']),
          'wall':float(row['wall_sec']), 'cpu':float(row['cpu_sec']),
          'start':int(row['start_unix_ms']), 'end':int(row['end_unix_ms']),
          'target':int(row['target_unix_ms']), 'checksum':row['checksum']
        })
    except (ValueError,KeyError) as e:
        print('WARNING invalid CSV:',path,e)

session_rows=[]
for (env,test,n,round_no), rows in sorted(groups.items()):
    complete = len(rows)==n
    late = max(0,max(r['start']-r['target'] for r in rows))
    checksums = len({r['checksum'] for r in rows})
    iters_set = {r['iters'] for r in rows}
    span_s = (max(r['end'] for r in rows)-min(r['start'] for r in rows))/1000.0
    total_mops = (len(rows)*rows[0]['iters']/(span_s*1e6)) if span_s else 0
    session_rows.append({
      'environment':env, 'test':test, 'count':n, 'round':round_no,
      'received_instances':len(rows), 'complete':int(complete),
      'mean_wall_sec':mean(r['wall'] for r in rows),
      'median_wall_sec':median(r['wall'] for r in rows),
      'mean_cpu_sec':mean(r['cpu'] for r in rows),
      'mean_cpu_wall_ratio':mean(r['cpu']/r['wall'] for r in rows),
      'group_span_sec':span_s, 'group_throughput_mops':total_mops,
      'max_start_late_ms':late,'distinct_checksums':checksums,'distinct_iteration_counts':len(iters_set)
    })
    if not complete or late>1000 or checksums!=1 or len(iters_set)!=1:
      print('REVIEW SESSION',env,test,n,round_no,'complete=',complete,'late=',late,'checksums=',checksums,'iters=',iters_set)

def write_csv(name, rows):
    if not rows: return
    with (folder/name).open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)

write_csv('session_summary.csv', session_rows)
by_key=defaultdict(list)
for row in session_rows:
    if row['complete'] and row['max_start_late_ms']<=1000 and row['distinct_checksums']==1:
        by_key[(row['environment'],row['test'],row['count'])].append(row)
summary=[]
for (env,test,n),rows in sorted(by_key.items()):
    vals=[r['mean_wall_sec'] for r in rows]
    vals_cpu=[r['mean_cpu_sec'] for r in rows]
    summary.append({'environment':env,'test':test,'count':n,'independent_rounds':len(rows),
       'mean_session_wall_sec':mean(vals), 'sd_session_wall_sec':stdev(vals) if len(vals)>1 else '',
       'median_session_wall_sec':median(vals),
       'mean_session_cpu_sec':mean(vals_cpu),
       'mean_group_throughput_mops':mean(r['group_throughput_mops'] for r in rows),
       'mean_cpu_wall_ratio':mean(r['mean_cpu_wall_ratio'] for r in rows)})
write_csv('condition_summary.csv',summary)
print('Recorded independent sessions:',len(session_rows))
for row in summary:
    print(f"{row['environment']:7s} {row['test']:12s} N={row['count']:2d} rounds={row['independent_rounds']:2d} wall={row['mean_session_wall_sec']:.5f}s cpu={row['mean_session_cpu_sec']:.5f}s throughput={row['mean_group_throughput_mops']:.1f} MOPS")
print('Saved:',folder/'session_summary.csv',folder/'condition_summary.csv')
