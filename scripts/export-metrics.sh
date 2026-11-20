#!/usr/bin/env bash
# Exports the CloudWatch metrics that prove (or disprove) the load-test bottleneck to JSON,
# so the numbers sit in evidence/ next to the dashboard screenshots.
# Usage (repo root):  scripts/export-metrics.sh <label> <start ISO-8601> <end ISO-8601>
#   e.g. scripts/export-metrics.sh before 2026-11-25T09:00:00Z 2026-11-25T09:20:00Z
set -euo pipefail
LABEL=${1:?label}; START=${2:?start}; END=${3:?end}
REGION=$(terraform -chdir=infra output -raw region)
DB_ID=$(terraform -chdir=infra output -raw db_instance_id)
API_ID=$(terraform -chdir=infra output -raw api_endpoint | sed -E 's#https://([^.]+)\..*#\1#')
FN="exam-platform-prod-api"
mkdir -p evidence/cloudwatch
cat > /tmp/queries.json <<EOF
[
 {"Id":"dbconn","MetricStat":{"Metric":{"Namespace":"AWS/RDS","MetricName":"DatabaseConnections","Dimensions":[{"Name":"DBInstanceIdentifier","Value":"$DB_ID"}]},"Period":60,"Stat":"Maximum"}},
 {"Id":"dbcpu","MetricStat":{"Metric":{"Namespace":"AWS/RDS","MetricName":"CPUUtilization","Dimensions":[{"Name":"DBInstanceIdentifier","Value":"$DB_ID"}]},"Period":60,"Stat":"Maximum"}},
 {"Id":"dbmem","MetricStat":{"Metric":{"Namespace":"AWS/RDS","MetricName":"FreeableMemory","Dimensions":[{"Name":"DBInstanceIdentifier","Value":"$DB_ID"}]},"Period":60,"Stat":"Minimum"}},
 {"Id":"lconc","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"ConcurrentExecutions","Dimensions":[{"Name":"FunctionName","Value":"$FN"}]},"Period":60,"Stat":"Maximum"}},
 {"Id":"lthr","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"Throttles","Dimensions":[{"Name":"FunctionName","Value":"$FN"}]},"Period":60,"Stat":"Sum"}},
 {"Id":"lerr","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"Errors","Dimensions":[{"Name":"FunctionName","Value":"$FN"}]},"Period":60,"Stat":"Sum"}},
 {"Id":"ldur","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"Duration","Dimensions":[{"Name":"FunctionName","Value":"$FN"}]},"Period":60,"Stat":"p95"}},
 {"Id":"api5xx","MetricStat":{"Metric":{"Namespace":"AWS/ApiGateway","MetricName":"5xx","Dimensions":[{"Name":"ApiId","Value":"$API_ID"}]},"Period":60,"Stat":"Sum"}},
 {"Id":"api4xx","MetricStat":{"Metric":{"Namespace":"AWS/ApiGateway","MetricName":"4xx","Dimensions":[{"Name":"ApiId","Value":"$API_ID"}]},"Period":60,"Stat":"Sum"}},
 {"Id":"apicount","MetricStat":{"Metric":{"Namespace":"AWS/ApiGateway","MetricName":"Count","Dimensions":[{"Name":"ApiId","Value":"$API_ID"}]},"Period":60,"Stat":"Sum"}},
 {"Id":"apip95","MetricStat":{"Metric":{"Namespace":"AWS/ApiGateway","MetricName":"Latency","Dimensions":[{"Name":"ApiId","Value":"$API_ID"}]},"Period":60,"Stat":"p95"}}
]
EOF
OUT="evidence/cloudwatch/${LABEL}-metrics.json"
aws cloudwatch get-metric-data --region "$REGION" --metric-data-queries file:///tmp/queries.json \
  --start-time "$START" --end-time "$END" --output json > "$OUT"
node -e "
const d=require('./$OUT');
for(const r of d.MetricDataResults){const v=r.Values;console.log(r.Id.padEnd(9),'max',v.length?Math.max(...v).toFixed(1):'-','points',v.length)}"
echo "Saved $OUT"
