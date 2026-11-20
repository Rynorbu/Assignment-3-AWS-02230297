#!/usr/bin/env bash
# Shared helpers for the Assignment 3 failure tests. Source it from the repo root:
#   source scripts/failure-tests/lib.sh
# Needs: aws CLI v2, terraform (state initialised in infra/), curl, node.
# Env for tests that write data: FT_STUDENT_EMAIL, FT_PASSWORD, FT_EXAM_ID
set -euo pipefail

# Windows AWS CLI ends lines with \r\n. Bash keeps the \r inside variables, and AWS then rejects
# the value ("Input can't contain control characters"), so strip it from every aws call.
aws() { command aws "$@" | tr -d '\r'; }
tfo() { terraform -chdir=infra output -raw "$1" | tr -d '\r'; }
APP_URL=$(tfo app_url)
REGION=$(tfo region)
DB_ID=$(tfo db_instance_id)
CLIENT_ID=$(tfo user_pool_client_id)
UPLOADS_BUCKET=$(tfo uploads_bucket)
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
EVID="evidence/failure-tests"
mkdir -p "$EVID"

json() { node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const o=JSON.parse(s);const v=($1);console.log(typeof v==='object'?JSON.stringify(v):v)})"; }
now() { date +%s; }
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

student_token() {
  aws cognito-idp initiate-auth --client-id "$CLIENT_ID" --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters "USERNAME=${FT_STUDENT_EMAIL:?set FT_STUDENT_EMAIL},PASSWORD=${FT_PASSWORD:?set FT_PASSWORD}" \
    --query 'AuthenticationResult.IdToken' --output text
}

# POST /start returns (or resumes) the attempt; prints the attempt id
start_attempt() {
  curl -s -X POST -H "Authorization: Bearer $1" "$APP_URL/api/exams/${FT_EXAM_ID:?set FT_EXAM_ID}/start" | json 'o.attemptId'
}

# Autosave a marker answer; prints the HTTP status
save_marker() {
  curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Authorization: Bearer $1" -H 'Content-Type: application/json' \
    --max-time 10 -d "{\"answers\":{\"q1\":\"Amazon S3\",\"q3\":\"$3\"}}" "$APP_URL/api/attempts/$2/answers" || echo 000
}

# Prints the saved answers of the attempt (start resumes the same attempt)
read_answers() {
  curl -s -X POST -H "Authorization: Bearer $1" "$APP_URL/api/exams/$FT_EXAM_ID/start" | json 'o.answers'
}

# probe <seconds> <csv>: GET /api/health every 2 s, log t,status,latency; prints first-failure and recovery times
probe() {
  local dur=$1 out=$2 start t code lat
  echo "epoch,t_seconds,http_status,latency_ms" > "$out"
  start=$(now)
  while [ $(( $(now) - start )) -lt "$dur" ]; do
    t=$(( $(now) - start ))
    read -r code lat < <(curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 5 "$APP_URL/api/health" || echo "000 5")
    echo "$(now),$t,$code,${lat}" >> "$out"
    printf '\r t+%4ss  /api/health=%s ' "$t" "$code"
    sleep 2
  done
  echo
  summarize_probe "$out"
}

# Downtime = first failed probe -> first good probe after the LAST failed probe
summarize_probe() {
  node -e "
    const rows=require('fs').readFileSync('$1','utf8').trim().split('\n').slice(1).map(l=>l.split(','));
    const bad=rows.filter(r=>r[2]!=='200');
    if(!bad.length){console.log('failed_probes=0 downtime_s=0 (no user-visible impact)');process.exit(0)}
    const first=+bad[0][1], last=+bad[bad.length-1][1];
    const next=rows.find(r=>+r[1]>last&&r[2]==='200');
    console.log('failed_probes='+bad.length+'/'+rows.length+' first_failure_t='+first+'s downtime_s='+((next?+next[1]:last)-first));"
}
