#!/bin/sh
# Server overload check. Prints "<level> <reasons>" (level ok|warn|crit). ~5ms, no deps.
# ponytail: fixed thresholds; tune here.
awk -v ncpu="$(nproc)" -v disk="$(df -P / | awk 'NR==2{gsub("%","",$5);print $5}')" '
  FILENAME=="/proc/loadavg" { load=$1 }
  /^MemTotal:/ { mt=$2 } /^MemAvailable:/ { ma=$2 } /^SwapTotal:/ { st=$2 } /^SwapFree:/ { sf=$2 }
  END {
    lvl=0; msg=""
    l=load/ncpu; mem=100*ma/mt; swap=(st>0)?100*(st-sf)/st:0
    if (l>=2)        { lvl=2; msg=msg sprintf(" CPU load %.0f%%", l*100) } else if (l>=1) { if(lvl<1)lvl=1; msg=msg sprintf(" CPU load %.0f%%", l*100) }
    if (mem<10)      { lvl=2; msg=msg sprintf(" RAM free %.0f%%", mem) }   else if (mem<20) { if(lvl<1)lvl=1; msg=msg sprintf(" RAM free %.0f%%", mem) }
    if (swap>=90 && mem<30) { if(lvl<1)lvl=1; msg=msg sprintf(" swap %.0f%%", swap) }
    if (disk>=95)    { lvl=2; msg=msg " disk " disk "%" }                   else if (disk>=90) { if(lvl<1)lvl=1; msg=msg " disk " disk "%" }
    print (lvl==2?"crit":lvl==1?"warn":"ok") msg
  }' /proc/loadavg /proc/meminfo
