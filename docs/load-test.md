# Load test: exam peak (3,000 students start one exam within 5 minutes)

**Tool:** [`scripts/peak-load-test.mjs`](../scripts/peak-load-test.mjs) (Node, no install), run from a laptop in Bhutan against the Singapore stack.

**Traffic shape:**
- 3,000 virtual students start the exam, spread evenly over 300 s. That is about **10 starts per second**.
- After starting, each student autosaves every 30 s. At steady state that is about **100 requests per second**.
- The test then holds that load for 5 minutes.
- The virtual students are spread over 200 Cognito load-test accounts.

**Evidence:**
- Script output: [`evidence/load-test/`](../evidence/load-test)
- CloudWatch export: [`evidence/cloudwatch/`](../evidence/cloudwatch), made with [`scripts/export-metrics.sh`](../scripts/export-metrics.sh)
- Screenshots S29–S40: [`evidence/README.md` §6](../evidence/README.md#6-load-test-bottleneck-proven-fixed-re-tested)

## 1. Method

| Step | Configuration | Command |
|---|---|---|
| Baseline (**before**) | A2 sizing: `db.t4g.micro`, **no RDS Proxy**, API Lambda unreserved, WAF **20,000 requests / 5 min per IP** | GitHub variables `DB_INSTANCE_CLASS=db.t4g.micro`, `DB_USE_RDS_PROXY=false` |
| Run 1 | 3,000 students / 300 s ramp / 300 s hold | `node scripts/peak-load-test.mjs --label before --exam-id <id> --domain example.com --accounts 200 --password '<pw>'` |
| Prove it | CloudWatch export + dashboard + WAF metrics + Logs Insights | `bash scripts/export-metrics.sh before 2026-11-20T11:29:00Z 2026-11-20T11:43:00Z` |
| Fix | Section 3 | — |
| Run 2 (**after**) | Same command, with `--label after` | — |
| Prove it | Same exports for the new window | `bash scripts/export-metrics.sh after <start> <end>` |

**Lambda quota checked first:** 1,000 concurrent executions in Singapore (S01), so the Lambda quota (B3 below) did not limit this test.

## 2. BEFORE run: results (2026-11-20, 11:30:13–11:40:50 UTC)

**Script result** ([`before-2026-11-20T11-30-13-758Z.json`](../evidence/load-test/before-2026-11-20T11-30-13-758Z.json), S29):

| Measure | Value |
|---|---|
| Requests sent | 45,079 (peak 153.5 per second) |
| HTTP 200 | 30,869 |
| **HTTP 403** | **11,750** |
| Network errors / timeouts (client side) | 2,370 / 90 |
| **Success rate** | **68.48 %** |
| Latency p50 / p95 / p99 | 511 ms / **10,198 ms** / 10,682 ms |

**CloudWatch, same window** ([`before-metrics.json`](../evidence/cloudwatch/before-metrics.json), S30–S32):

| Metric | Value | Reading |
|---|---|---|
| **WAF `BlockedRequests`, rule `RateLimitPerIp`** (us-east-1, CloudFront scope) | **11,762** (5,635 + 5,300 + 791 + 36 per minute) | **Matches the 11,750 HTTP 403s. WAF blocked them.** |
| API Gateway `4xx` / `5xx` | 0 / 0 | The blocked requests never reached the API |
| API Gateway `Count` (max per minute) | 5,621 | |
| API Gateway `Latency` p95 (max) | 214.9 ms | The backend was fast when requests got through |
| API Lambda `ConcurrentExecutions` (max) | 133 | |
| API Lambda `Errors` / `Throttles` | 0 / 0 | |
| RDS `DatabaseConnections` (max) | **67** | About 80 % of the about-80 usable connections on `t4g.micro` |
| RDS `FreeableMemory` (min) | **57 MB** of 1 GiB | The database was close to running out of memory |
| RDS `CPUUtilization` (max) | 10.2 % | CPU was not the limit |

### Bottleneck B1 (proven): WAF rate limit per IP

- The WAF rule `RateLimitPerIp` allowed **20,000 requests per 5 minutes per source IP**.
- At the exam peak, 3,000 students produce about 100 requests per second, which is **about 30,000–46,000 requests per 5 minutes**.
- The load test came from one IP address. **So does a whole campus** behind one internet connection (NAT). That is the normal case for students sitting an exam in a university lab in Bhutan.
- WAF therefore blocked **26 % of all requests** (11,762) with HTTP 403. Students would see their exam fail to load and their autosaves fail.
- **Proof:**
  - S32 / WAF metric: `BlockedRequests` for `RateLimitPerIp` equals the 403 count.
  - S30 / S32: API Gateway shows **0** 4xx and 5xx errors, which proves the requests were stopped at the edge, before the API.
  - S33: the sampled requests in the WAF console show the rule that blocked them.

### Bottleneck B2 (observed, building up): database connections and memory on `db.t4g.micro`

- Even with a quarter of the traffic blocked at the edge, the database was already at **67 connections** and **57 MB of free memory**.
- Without RDS Proxy, every warm Lambda environment holds its own connection: 133 concurrent Lambdas at peak.
- Once WAF stops blocking, about 33 % more traffic reaches the database. That would push `t4g.micro` past its connection limit (`FATAL: remaining connection slots are reserved`) or out of memory.
- So B2 is fixed together with B1, and the re-test shows whether the fix holds.

## 3. The fix (applied before the AFTER run)

| # | Change | Why | How |
|---|---|---|---|
| F1 | **WAF: per-student rate limit** (1,000 requests / 5 min per sign-in token). The per-IP rule becomes a flood backstop at **150,000 / 5 min**. | An abusive client is still blocked, but 3,000 honest students sharing one campus IP are not. | `infra/edge.tf`: new rule `RateLimitPerStudent` (`CUSTOM_KEYS` on the `Authorization` header). `infra/variables.tf`: `waf_rate_limit_per_ip = 150000`. Cost: +$1 a month for one more WAF rule. |
| F2 | **Bigger database** | 2–4× the RAM, so 2–4× the connection limit and room for the buffer cache | `DB_INSTANCE_CLASS=db.t4g.small` (Free plan) or `db.t4g.large` (production exam month) |
| F3 | **Cap API Lambda concurrency** (Free plan, because RDS Proxy is blocked) | The total number of DB connections can never exceed the cap. Overflow gets a fast throttle that autosave retries 30 s later, instead of crashing the database. | `API_RESERVED_CONCURRENCY=60` |
| F3-prod | **RDS Proxy** (production, paid plan) | Multiplexes hundreds of Lambda connections onto a few database connections and speeds up failover (FT1) | `DB_USE_RDS_PROXY=true` |

## 4. AFTER run: results (fill in after the re-test)

| Measure | Before | After |
|---|---|---|
| Success rate | 68.48 % | ☐ |
| HTTP 403 (WAF) | 11,750 | ☐ |
| WAF `BlockedRequests` | 11,762 | ☐ |
| Latency p95 (script) | 10,198 ms | ☐ |
| API `Latency` p95 (CloudWatch) | 214.9 ms | ☐ |
| RDS `DatabaseConnections` max | 67 | ☐ |
| RDS `FreeableMemory` min | 57 MB | ☐ |
| API Lambda `ConcurrentExecutions` max | 133 | ☐ |
| Lambda `Throttles` (sum) | 0 | ☐ (with F3, a few are fine) |

**Conclusion:** ☐ (one sentence: did the fix remove B1 and keep B2 under its limit?)

## 5. More bottlenecks (reasoned, not load-tested)

**B3: Lambda account concurrency and scaling rate.**
- Peak concurrency in the test was 133, against a quota of **1,000** (S01) and 800 unreserved. That leaves about 6× headroom.
- A new account limited to 10 would have throttled the very first exam.
- **Fix:**
  - Check the quota before each exam month.
  - Keep the `Throttles` alarm.
  - Optionally add provisioned concurrency for the hour around each exam start, at about $0.70 per exam window, to remove cold starts.

**B4: Result-release emails (SES sending rate) and Cognito sign-in rate.**
- **SES:** releasing 3,000 results means 3,000 emails.
  - The SES sandbox sends 1 per second, which would take 50 minutes. With production access the default is 14 per second, about 3.6 minutes.
  - The notify queue absorbs the burst (consumer `maximum_concurrency = 5`), so emails are delayed but never lost.
  - **Fix:** request SES production access before the exam month.
- **Cognito:** 3,000 sign-ins in 5 minutes is about 10 per second, below the default `UserAuthentication` quota of about 120 per second. Even if everyone signs in within the last minute (50 per second), it is still under the limit. No change needed; monitor `ThrottleCount`.
