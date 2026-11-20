#!/usr/bin/env bash
# Creates N load-test student accounts (loadtest001@<domain> ... ) with one shared password,
# so the peak load test does not hammer a single attempt row.
# Usage (repo root, after deploy):
#   scripts/seed-load-users.sh 200 example.com 'LoadTest#2026pass'
# Remove them afterwards with: scripts/seed-load-users.sh 200 example.com '' --delete
set -euo pipefail

COUNT=${1:?number of users, e.g. 200}
DOMAIN=${2:?email domain, e.g. example.com}
PASSWORD=${3:-}
MODE=${4:-create}

POOL_ID=$(terraform -chdir=infra output -raw user_pool_id)
REGION=$(terraform -chdir=infra output -raw region)

for i in $(seq -w 1 "$COUNT"); do
  EMAIL="loadtest${i}@${DOMAIN}"
  if [ "$MODE" = "--delete" ]; then
    aws cognito-idp admin-delete-user --region "$REGION" --user-pool-id "$POOL_ID" --username "$EMAIL" 2>/dev/null && echo "deleted $EMAIL" || true
    continue
  fi
  aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$POOL_ID" --username "$EMAIL" \
    --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
    --message-action SUPPRESS >/dev/null 2>&1 || true
  aws cognito-idp admin-set-user-password --region "$REGION" --user-pool-id "$POOL_ID" --username "$EMAIL" \
    --password "$PASSWORD" --permanent
  aws cognito-idp admin-add-user-to-group --region "$REGION" --user-pool-id "$POOL_ID" --username "$EMAIL" \
    --group-name students
  echo "ready $EMAIL"
done
