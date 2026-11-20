#!/usr/bin/env bash
# FT1 – Loss of the Availability Zone that hosts the primary database.
# Forces an RDS Multi-AZ failover (reboot --force-failover), probes /api/health every 2 s,
# and proves RPO by writing a marker answer just before the failover and reading it after.
# Usage (repo root):  FT_STUDENT_EMAIL=... FT_PASSWORD=... FT_EXAM_ID=... scripts/failure-tests/ft1-az-db-failover.sh
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft1-$(date +%Y%m%d-%H%M%S)"

TOKEN=$(student_token); ATTEMPT=$(start_attempt "$TOKEN")
MARKER="ft1-before-failover-$(ts)"
echo "Marker save: HTTP $(save_marker "$TOKEN" "$ATTEMPT" "$MARKER")  ($MARKER)"

aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone]' --output text | tee "$OUT-before-az.txt"
T_FAIL=$(ts); echo "Failover started at $T_FAIL"
aws rds reboot-db-instance --db-instance-identifier "$DB_ID" --force-failover --query 'DBInstance.DBInstanceStatus' --output text

probe 240 "$OUT-probe.csv" | tee "$OUT-summary.txt"

aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone]' --output text | tee "$OUT-after-az.txt"
aws rds describe-events --source-identifier "$DB_ID" --source-type db-instance --duration 30 \
  --query 'Events[].[Date,Message]' --output table | tee "$OUT-rds-events.txt"

TOKEN=$(student_token)
if read_answers "$TOKEN" | grep -q "$MARKER"; then
  echo "RPO check: marker FOUND after failover -> answers lost = 0 (RPO 0 s)" | tee -a "$OUT-summary.txt"
else
  echo "RPO check: marker NOT found -> data loss, investigate" | tee -a "$OUT-summary.txt"
fi
echo "Evidence: $OUT-*  (also screenshot the RDS 'Logs & events' tab and the CloudWatch dashboard)"
