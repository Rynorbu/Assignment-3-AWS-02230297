#!/usr/bin/env bash
# FT2 – Accidental data loss / corruption (e.g. a bad migration wipes answers).
# Measures RPO  = now - LatestRestorableTime  (how much could be lost)
# and      RTO  = time to restore a new DB instance from point-in-time + switch the app to it.
# The restore goes to a NEW single-AZ instance (cheaper); it is deleted at the end.
# Usage (repo root):  scripts/failure-tests/ft2-pitr-restore.sh
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft2-$(date +%Y%m%d-%H%M%S)"
RESTORED="${DB_ID}-ft2-restore"

read -r LRT CLASS SUBNETS SG < <(aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].[LatestRestorableTime,DBInstanceClass,DBSubnetGroup.DBSubnetGroupName,VpcSecurityGroups[0].VpcSecurityGroupId]' --output text)
NOW=$(ts)
RPO=$(node -e "console.log(Math.round((Date.parse('$NOW')-Date.parse('$LRT'))/1000))")
echo "now=$NOW latest_restorable=$LRT  => RPO exposure = ${RPO}s (target <= 300 s)" | tee "$OUT-summary.txt"

START=$(now)
echo "Restoring $DB_ID to $LRT as $RESTORED ..."
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier "$DB_ID" \
  --target-db-instance-identifier "$RESTORED" --use-latest-restorable-time \
  --db-instance-class "$CLASS" --db-subnet-group-name "$SUBNETS" --vpc-security-group-ids "$SG" \
  --no-multi-az --no-publicly-accessible --query 'DBInstance.DBInstanceStatus' --output text
aws rds wait db-instance-available --db-instance-identifier "$RESTORED"
END=$(now)
echo "Restore available after $((END - START)) s" | tee -a "$OUT-summary.txt"
echo "RTO estimate = restore $((END - START)) s + repoint app (terraform apply with the restored endpoint, ~5 min) (target <= 3600 s)" | tee -a "$OUT-summary.txt"
aws rds describe-events --source-identifier "$RESTORED" --source-type db-instance --duration 120 \
  --query 'Events[].[Date,Message]' --output table | tee "$OUT-rds-events.txt"

read -r -p "Screenshot the restored instance in the console, then press Enter to DELETE it ... " _
aws rds delete-db-instance --db-instance-identifier "$RESTORED" --skip-final-snapshot --delete-automated-backups \
  --query 'DBInstance.DBInstanceStatus' --output text
echo "Evidence: $OUT-*"
