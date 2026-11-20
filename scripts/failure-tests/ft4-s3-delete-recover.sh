#!/usr/bin/env bash
# FT4 – A submitted assignment file is deleted (mistake, bad script or compromised credentials).
# Uploads a test object, deletes it, then recovers it from S3 versioning and times the recovery.
# Usage (repo root):  scripts/failure-tests/ft4-s3-delete-recover.sh
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft4-$(date +%Y%m%d-%H%M%S)"
KEY="assignments/ft4-test/ft4-$(date +%s).pdf"
TMP=$(mktemp)
head -c 2097152 /dev/urandom > "$TMP"   # 2 MB stand-in for a student PDF
ORIG=$(sha256sum "$TMP" | cut -d' ' -f1)

aws s3 cp "$TMP" "s3://$UPLOADS_BUCKET/$KEY" --only-show-errors
echo "Uploaded $KEY sha256=$ORIG" | tee "$OUT-summary.txt"
aws s3 rm "s3://$UPLOADS_BUCKET/$KEY" --only-show-errors
T_DEL=$(now); echo "Deleted at $(ts) (a delete marker is created, data is kept)" | tee -a "$OUT-summary.txt"
aws s3api list-object-versions --bucket "$UPLOADS_BUCKET" --prefix "$KEY" \
  --query '{versions:Versions[].[VersionId,IsLatest],deleteMarkers:DeleteMarkers[].[VersionId,IsLatest]}' --output json | tee "$OUT-versions-before.json"

read -r -p "Screenshot S54 now: S3 console -> bucket -> assignments/ft4-test/ -> Show versions ON. Press Enter to recover... " _
T_DEL=$(now)   # recovery clock starts after the screenshot pause
# Recovery = remove the delete marker
MARKER=$(aws s3api list-object-versions --bucket "$UPLOADS_BUCKET" --prefix "$KEY" --query 'DeleteMarkers[0].VersionId' --output text)
aws s3api delete-object --bucket "$UPLOADS_BUCKET" --key "$KEY" --version-id "$MARKER" >/dev/null
aws s3 cp "s3://$UPLOADS_BUCKET/$KEY" "$TMP.back" --only-show-errors
T_OK=$(now)
BACK=$(sha256sum "$TMP.back" | cut -d' ' -f1)
[ "$ORIG" = "$BACK" ] && R="IDENTICAL (RPO 0)" || R="DIFFERENT"
echo "Recovered after $((T_OK - T_DEL)) s, checksum $R" | tee -a "$OUT-summary.txt"
aws s3 rm "s3://$UPLOADS_BUCKET/$KEY" --only-show-errors   # clean up (versions expire after 30 days)
rm -f "$TMP" "$TMP.back"
echo "Evidence: $OUT-*"
