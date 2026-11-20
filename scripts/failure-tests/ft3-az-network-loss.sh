#!/usr/bin/env bash
# FT3 – Network loss in ONE Availability Zone for the Lambda (app) subnet, using AWS FIS.
# Needs the template: deploy with ENABLE_FIS=true (GitHub variable) or -var enable_fis=true.
# Runs a 5-minute experiment, probes /api/health every 2 s and records the error rate.
# Usage (repo root):  scripts/failure-tests/ft3-az-network-loss.sh
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft3-$(date +%Y%m%d-%H%M%S)"

TEMPLATE=$(aws fis list-experiment-templates \
  --query "experimentTemplates[?tags.Name && contains(tags.Name,'ft3-az-network-loss')].id | [0]" --output text)
[ "$TEMPLATE" != "None" ] || { echo "FIS template not found - deploy with enable_fis=true"; exit 1; }

EXP=$(aws fis start-experiment --experiment-template-id "$TEMPLATE" --query 'experiment.id' --output text)
echo "Started FIS experiment $EXP at $(ts)" | tee "$OUT-summary.txt"
probe 420 "$OUT-probe.csv" | tee -a "$OUT-summary.txt"
aws fis get-experiment --id "$EXP" --query 'experiment.state' --output json | tee -a "$OUT-summary.txt"
echo "Evidence: $OUT-*  (screenshot FIS experiment timeline + dashboard: API 5xx and Lambda errors)"
