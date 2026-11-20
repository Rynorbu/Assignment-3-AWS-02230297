# Load test: exam peak (3,000 students start one exam within 5 minutes)

**Tool:** [`scripts/peak-load-test.mjs`](../scripts/peak-load-test.mjs) (Node, no install).

**Traffic shape:**
- 3,000 virtual students start the exam, spread evenly over 300 s. That is about **10 starts per second**.
- After starting, each student autosaves every 30 s until the end. At steady state that is about **100 requests per second**.
- The test then holds that load for 5 minutes.

**Evidence:**
- Script output: `evidence/load-test/*.json|csv`
- CloudWatch export: `evidence/cloudwatch/*-metrics.json` (made with [`scripts/export-metrics.sh`](../scripts/export-metrics.sh))
- Screenshots of the CloudWatch dashboard (the rows added in Assignment 3)

> Fill in every `☐` from your own runs. Do not copy the expected values into the measured columns.

## 1. Method

| Step | Configuration | Command |
|---|---|---|
| Baseline (**before**) | A2 demo sizing: `db.t4g.micro`, **no RDS Proxy**, API Lambda unreserved | `terraform apply -var-file=terraform.tfvars -var-file=load-test-baseline.tfvars`, or set the GitHub variables `DB_INSTANCE_CLASS=db.t4g.micro` and `DB_USE_RDS_PROXY=false` |
| Run 1 | 3,000 students / 300 s ramp / 300 s hold | `node scripts/peak-load-test.mjs --label before --exam-id <id> --domain <domain> --accounts 200 --password '<pw>'` |
| Prove it | Export CloudWatch for the run window, then screenshot the dashboard | `scripts/export-metrics.sh before <start> <end>` |
| Fix | See section 3 | — |
| Run 2 (**after**) | Same command, with `--label after` | — |
| Prove it | Export and screenshot again | `scripts/export-metrics.sh after <start> <end>` |

The 200 load-test accounts come from:

```bash
scripts/seed-load-users.sh 200 <domain> '<pw>'
```

**Do this first:** check the Lambda concurrency quota. New accounts often have only **10** concurrent executions.
- Open Service Quotas → AWS Lambda → *Concurrent executions*.
- If it is below 1,000, request 1,000 **several days before testing**. See bottleneck B2 below.

## 2. Bottleneck B1 (expected and tested): database connections and memory on `db.t4g.micro` without a proxy

**Why it should break:**
- Without RDS Proxy, every warm API Lambda environment holds its own PostgreSQL connection.
- During the ramp, Lambda scales out quickly. VPC cold starts take 1–2 s, so concurrency jumps while the new environments start.
- `db.t4g.micro` has 1 GiB of RAM, so `max_connections` is about 80–110 (`DBInstanceClassMemory / 9531392`).
- Once connections hit that limit, new environments get `FATAL: too many connections` (or a connect timeout after 5 s). The API returns **500/503**.
- Each connection also uses about 5–10 MB of RAM, so `FreeableMemory` collapses and `WriteLatency` rises. Requests get slower, which raises concurrency even further.

**CloudWatch proof to capture (the dashboard rows added in A3):**

| Metric | Expected *before* | Measured *before* | Expected *after* | Measured *after* |
|---|---|---|---|---|
| `DatabaseConnections` (max) | flat at the ceiling, about 80–110 | ☐ | < 40 (proxy pools them) | ☐ |
| `FreeableMemory` (min) | < 100 MB | ☐ | > 3 GB | ☐ |
| API Lambda `ConcurrentExecutions` (max) | 100–300 during the ramp | ☐ | 20–60 | ☐ |
| API Lambda `Errors` (sum) | > 0 | ☐ | 0 | ☐ |
| API Gateway `5xx` (sum) | hundreds | ☐ | 0 | ☐ |
| API `Latency` p95 | > 3,000 ms | ☐ | < 300 ms | ☐ |
| Script success rate | < 95 % | ☐ | ≥ 99.9 % | ☐ |
| Script p95 latency | > 2,000 ms | ☐ | < 500 ms | ☐ |

## 3. The fix (re-test with the production exam-month configuration)

| Change | Why | How |
|---|---|---|
| **RDS Proxy** on (paid plan) | Thousands of Lambda connections are multiplexed onto a few database connections. It also makes failover faster (FT1). | `DB_USE_RDS_PROXY=true` |
| **`db.t4g.large`** for the exam month | 8 GiB RAM, about 900 connections, and burstable CPU with unlimited credits | `DB_INSTANCE_CLASS=db.t4g.large` or `-var-file=exam-month.tfvars` |
| **AWS Free plan** (no proxy allowed) | Cap API concurrency below `max_connections`. Overflow is throttled (a fast error that autosave simply retries 30 s later) instead of crashing the database for everyone. | `API_RESERVED_CONCURRENCY=60` plus `DB_INSTANCE_CLASS=db.t4g.small` or larger |

Write down which fix you applied and why. If you are on the Free plan, the concurrency cap plus a bigger instance is the fix. Explain that RDS Proxy is the production fix.

## 4. Two more bottlenecks (reasoned, not load-tested)

**B2: Lambda account concurrency and scaling rate.**
- Concurrency ≈ requests per second × duration. At 100 req/s × 0.08 s that is about 8 when warm, but during the cold-start ramp it reaches **100–300**.
- The default account quota is 1,000. Many new accounts have **10**, which would throttle the very first exam (throttled invocations show up as API errors).
- Lambda scales by 1,000 environments every 10 s per function, which is enough.
- **Fix:**
  1. Raise the quota to 1,000 before the first exam month.
  2. Alarm on `Throttles` (it already exists).
  3. Optionally add *provisioned concurrency* (for example 50) for the 2 hours around each exam start, at about $0.70 per exam window. This removes cold starts.

**B3: Result-release emails (SES sending rate) and Cognito sign-in rate.**
- **SES:** releasing results for 3,000 students creates 3,000 emails.
  - In sandbox mode SES allows 1 email per second, which would take 50 minutes. After production access the default is 14 per second, so about 3.6 minutes.
  - The notify queue absorbs the burst (`maximum_concurrency = 5`), so nothing is lost, only delayed.
  - **Fix:** request SES production access and a 50/s rate before the exam month.
- **Cognito:** about 3,000 sign-ins in 5 minutes is about 10/s, well below the default `UserAuthentication` quota of 120 requests per second. But if everyone signs in during the last 60 s, that is 50/s, which is still under the limit. No change needed; monitor `ThrottleCount`.

## 5. Results summary (fill after the runs)

| Run | Config | Requests | Success % | p95 ms | Peak RPS | DB conn max | 5xx |
|---|---|---|---|---|---|---|---|
| before | t4g.micro, no proxy | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| after | t4g.large + proxy (or cap) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

**Conclusion:** ☐ (one sentence: was the bottleneck proven, and did the fix remove it?)
