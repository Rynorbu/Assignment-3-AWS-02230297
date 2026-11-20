#!/usr/bin/env bash
# Measures network round-trip time from THIS computer (run it in Bhutan) to AWS Regions.
# TCP connect time ~= 1 round trip. 20 samples per Region, prints min / median / p90.
# Usage: bash scripts/measure-latency.sh [samples=20]   -> also saves evidence/latency/latency-<date>.csv
set -euo pipefail
N=${1:-20}
REGIONS="ap-southeast-1 ap-south-1 ap-south-2 us-east-1"
mkdir -p evidence/latency
OUT="evidence/latency/latency-$(date +%Y%m%d-%H%M).csv"
echo "region,sample,tcp_connect_ms,tls_done_ms" > "$OUT"
echo "Measured on $(date) - note your city and ISP in the evidence file name or README"
for r in $REGIONS; do
  for i in $(seq 1 "$N"); do
    read -r c t < <(curl -s -o /dev/null -w '%{time_connect} %{time_appconnect}\n' --max-time 10 "https://dynamodb.$r.amazonaws.com/ping" || echo "10 10")
    echo "$r,$i,$(awk "BEGIN{printf \"%.1f\", $c*1000}"),$(awk "BEGIN{printf \"%.1f\", $t*1000}")" >> "$OUT"
  done
done
node -e "
const rows=require('fs').readFileSync('$OUT','utf8').trim().split('\n').slice(1).map(l=>l.split(','));
const by={};rows.forEach(([r,,c])=>(by[r]=by[r]||[]).push(+c));
console.log('Region          min    median  p90   (TCP round trip, ms)');
for(const [r,v] of Object.entries(by)){v.sort((a,b)=>a-b);const q=p=>v[Math.min(v.length-1,Math.floor(p*v.length))];console.log(r.padEnd(15),String(v[0]).padStart(6),String(q(0.5)).padStart(7),String(q(0.9)).padStart(6))}"
echo "Saved $OUT"
