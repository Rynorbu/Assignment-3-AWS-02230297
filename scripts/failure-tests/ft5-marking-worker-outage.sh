#!/usr/bin/env bash
# FT5 – The marking worker stops (bad deploy / throttled) while submissions keep arriving.
# Sets the marking Lambda's reserved concurrency to 0, sends 50 probe messages to the
# marking queue, waits, restores the worker and measures how long the backlog takes to drain
# and whether any message ended in the dead-letter queue (and redrives it).
# Probe messages use an unknown "type", which the worker logs and acknowledges without DB writes.
# Usage (repo root):  scripts/failure-tests/ft5-marking-worker-outage.sh [outage_seconds=180]
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft5-$(date +%Y%m%d-%H%M%S)"
OUTAGE=${1:-180}
FN="exam-platform-a3-prod-marking"
Q=$(aws sqs get-queue-url --queue-name exam-platform-a3-prod-marking --query QueueUrl --output text)
DLQ=$(aws sqs get-queue-url --queue-name exam-platform-a3-prod-marking-dlq --query QueueUrl --output text)
depth() { aws sqs get-queue-attributes --queue-url "$1" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query 'sum(values(Attributes)[].to_number(@))' --output text 2>/dev/null || echo "?"; }

aws lambda put-function-concurrency --function-name "$FN" --reserved-concurrent-executions 0 >/dev/null
echo "$(ts) worker stopped (reserved concurrency 0)" | tee "$OUT-summary.txt"
for i in $(seq 1 50); do aws sqs send-message --queue-url "$Q" --message-body "{\"type\":\"ft5-probe\",\"n\":$i}" >/dev/null; done
echo "$(ts) 50 messages queued; depth=$(depth "$Q")" | tee -a "$OUT-summary.txt"

echo "t_seconds,queue_depth,dlq_depth" > "$OUT-depth.csv"
S=$(now); while [ $(( $(now) - S )) -lt "$OUTAGE" ]; do echo "$(( $(now) - S )),$(depth "$Q"),$(depth "$DLQ")" >> "$OUT-depth.csv"; sleep 15; done

aws lambda delete-function-concurrency --function-name "$FN"
R=$(now); echo "$(ts) worker restored" | tee -a "$OUT-summary.txt"
while [ "$(depth "$Q")" != "0" ] && [ $(( $(now) - R )) -lt 600 ]; do echo "$(( $(now) - S )),$(depth "$Q"),$(depth "$DLQ")" >> "$OUT-depth.csv"; sleep 5; done
echo "Backlog drained $(( $(now) - R )) s after restore; DLQ depth=$(depth "$DLQ")" | tee -a "$OUT-summary.txt"

if [ "$(depth "$DLQ")" != "0" ]; then
  echo "Messages reached the DLQ -> redriving them to the source queue" | tee -a "$OUT-summary.txt"
  DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names QueueArn --query Attributes.QueueArn --output text)
  aws sqs start-message-move-task --source-arn "$DLQ_ARN" | tee -a "$OUT-summary.txt"
fi
echo "Evidence: $OUT-*  (screenshot the 'Queue depth' dashboard widget and the DLQ alarm email)"
