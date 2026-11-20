#!/usr/bin/env bash
# FT3 – Network loss in ONE Availability Zone for the Lambda (app) subnet.
# AWS FIS is not available on this account (SubscriptionRequiredException), so the same fault
# that FIS "aws:network:disrupt-connectivity" injects is reproduced by hand: the app subnet in
# the first AZ is moved to a new network ACL that denies all traffic, for 5 minutes, then the
# original ACL is put back (also on Ctrl+C or any error, via trap).
# Usage (repo root):  scripts/failure-tests/ft3-az-network-loss.sh [fault_seconds=300]
source "$(dirname "$0")/lib.sh"
OUT="$EVID/ft3-$(date +%Y%m%d-%H%M%S)"
FAULT=${1:-300}
NAME_PREFIX=${NAME_PREFIX:-exam-platform-a3-prod}
AZ="${REGION}a"

SUBNET=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=${NAME_PREFIX}-app-${AZ}" --query 'Subnets[0].SubnetId' --output text)
[ "$SUBNET" != "None" ] || { echo "App subnet ${NAME_PREFIX}-app-${AZ} not found"; exit 1; }
VPC=$(aws ec2 describe-subnets --subnet-ids "$SUBNET" --query 'Subnets[0].VpcId' --output text)
read -r ASSOC ORIG_ACL < <(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "NetworkAcls[0].[Associations[?SubnetId=='$SUBNET']|[0].NetworkAclAssociationId, NetworkAclId]" --output text)

DENY_ACL=$(aws ec2 create-network-acl --vpc-id "$VPC" \
  --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=${NAME_PREFIX}-ft3-deny-all}]" \
  --query 'NetworkAcl.NetworkAclId' --output text)   # a new custom NACL denies everything by default

restore() {
  if [ -n "${NEW_ASSOC:-}" ]; then
    aws ec2 replace-network-acl-association --association-id "$NEW_ASSOC" --network-acl-id "$ORIG_ACL" >/dev/null && \
      echo "$(ts) restored original network ACL $ORIG_ACL on $SUBNET" | tee -a "$OUT-summary.txt"
    NEW_ASSOC=""
  fi
  aws ec2 delete-network-acl --network-acl-id "$DENY_ACL" 2>/dev/null || true
}
trap restore EXIT INT TERM

echo "Subnet $SUBNET ($AZ) in $VPC: original ACL $ORIG_ACL, deny-all ACL $DENY_ACL" | tee "$OUT-summary.txt"
NEW_ASSOC=$(aws ec2 replace-network-acl-association --association-id "$ASSOC" --network-acl-id "$DENY_ACL" \
  --query NewAssociationId --output text)
echo "$(ts) FAULT START: all traffic blocked in the $AZ app subnet for ${FAULT}s" | tee -a "$OUT-summary.txt"
echo ">>> Screenshot S49 now: VPC console -> Subnets -> $SUBNET -> Network ACL tab (shows ${NAME_PREFIX}-ft3-deny-all)"

# Probe during the fault, restore, then keep probing 2 more minutes to see recovery
probe "$FAULT" "$OUT-probe-fault.csv" | tee -a "$OUT-summary.txt"
restore
echo "$(ts) FAULT END" | tee -a "$OUT-summary.txt"
probe 120 "$OUT-probe-recovery.csv" | sed 's/^/recovery: /' | tee -a "$OUT-summary.txt"
echo "Evidence: $OUT-*  (screenshot the dashboard: API 5xx + Lambda errors during the fault window)"
