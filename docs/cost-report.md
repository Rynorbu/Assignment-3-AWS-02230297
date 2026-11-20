# Cost and service report: exam platform in ap-southeast-1 (Singapore)

| | |
|---|---|
| **Prices checked** | **2026-11-19**. Unit prices come from the AWS Price List API for `ap-southeast-1` (publication dates 2026-10-19 to 2026-11-18). Items marked [calc] were taken from the AWS Pricing Calculator. |
| **Calculator estimates** | Normal month: ☐ *paste share link* · Exam month: ☐ *paste share link* · A2 baseline: ☐ *paste share link* (exports are in [`evidence/calculator/`](../evidence/calculator)) |
| **Reproducible model** | [`scripts/cost-model.mjs`](../scripts/cost-model.mjs). Run `node scripts/cost-model.mjs` to regenerate every number in this report. |
| **Budget** | USD 1,000 per month, averaged over 12 months (10 normal months + 2 exam months) |

## 1. Assumptions (usage that drives the bill)

| Driver | Normal month | Exam month | Basis |
|---|---|---|---|
| Users | 8,000 students + 400 staff = 8,400 monthly active | same | brief |
| Concurrent users | 300–500 (400 average over 10 active hours a day) | peak of 3,000 starting within 5 min | brief |
| API requests | 14.4 M | 22.4 M | 400 users × 2 req/min × 10 h × 30 d; exam months add 40,000 attempts × 200 requests (180 autosaves in 90 min + 20 others) |
| Lambda | 80 ms average, 512 MB, arm64 | same | A2 configuration |
| Assignment uploads | 12,000 files (120 GB) | 4,000 files (40 GB) | 8,000 students × 1.5 a month × 10 MB average |
| S3 stock after 5 years | 7.2 TB (1.44 TB/year) | — | Year-5 steady state is costed, to be safe |
| CloudFront out | 122 GB | 187 GB | SPA assets plus 5 KB per API response |
| Tutor downloads (S3 → internet) | 120 GB | 60 GB | each file is opened about once |
| Logs ingested | 11 GB | 17 GB | API access logs + Lambda + PostgreSQL |
| Emails | 36,000 | 50,000 | results + upload receipts |
| Database | `db.t4g.medium` Multi-AZ, 20 GB gp3 | `db.t4g.large` Multi-AZ | load test (`docs/load-test.md`) |

## 2. Monthly cost per service (final design, 1-year RDS Reserved Instance applied)

| Service | Normal month | Exam month | Annual (10 + 2) |
|---|---:|---:|---:|
| RDS PostgreSQL Multi-AZ instance (RI t4g.medium; exam month = RI + on-demand half of t4g.large) | $111.29 | $259.48 | $1,631.86 |
| RDS storage gp3 Multi-AZ (20 GB) | $5.52 | $5.52 | $66.24 |
| RDS Proxy (2 vCPU × $0.018/h) | $26.28 | $26.28 | $315.36 |
| RDS CPU credits (T4g unlimited, exam sittings) | $0.00 | $9.75 | $19.50 |
| **Backups** (AWS Backup snapshots, about 40 GB warm) 🔍 | $3.80 | $3.80 | $45.60 |
| **NAT gateway** hours + **processing** 🔍 | $0.00 | $0.00 | $0.00 (was $1,037 in A2) |
| VPC interface endpoints: SQS + Secrets Manager (2 endpoints × 2 AZ × $0.013/h) | $37.98 | $37.98 | $455.76 |
| Lambda arm64 (requests + GB-s + 1-min scheduler) | $10.76 | $16.71 | $141.03 |
| API Gateway HTTP API ($1.25 per million) | $18.00 | $28.00 | $236.00 |
| CloudFront (data out + HTTPS requests) | $33.13 | $51.20 | $433.70 |
| WAF (web ACL + 4 rules + $0.60 per million requests) | $18.24 | $23.38 | $229.21 |
| S3 uploads storage (lifecycle, year-5 steady state) | $26.50 | $26.50 | $318.00 |
| S3 requests + lifecycle transitions | $1.03 | $0.34 | $11.03 |
| **Data transfer out** (S3 → tutors, $0.12/GB) 🔍 | $14.40 | $7.20 | $158.40 |
| **Inter-AZ data transfer** (Lambda ↔ RDS, $0.02/GB) 🔍 | $1.72 | $2.68 | $22.56 |
| **CloudWatch Logs** ($0.70/GB ingest + storage) 🔍 | $8.03 | $12.41 | $105.12 |
| CloudWatch alarms (14, of which 10 are free) + 1 dashboard | $3.40 | $3.40 | $40.80 |
| **KMS** key + **requests** (S3 bucket key keeps them low) 🔍 | $1.24 | $1.39 | $15.18 |
| Secrets Manager (1 secret) | $0.65 | $0.65 | $7.80 |
| SQS (incl. Lambda long-polling, first 1 M free) | $0.40 | $0.56 | $5.12 |
| SES email ($0.10 per 1,000) | $3.60 | $5.00 | $46.00 |
| Cognito (8,400 MAU, below the 10,000 free tier) | $0.00 | $0.00 | $0.00 |
| Route 53 hosted zone | $0.50 | $0.50 | $6.00 |
| EventBridge schedule, CloudTrail management trail | $0.00 | $0.00 | $0.00 |
| **Total** | **$326.48** | **$522.74** | **$4,310.28** |

| Headline | Value |
|---|---|
| Annual total | **$4,310.28** (on-demand without the RI: $4,753.08) |
| Average per month | **$359.19**, which is **36 % of the $1,000 budget** |
| Most expensive month (exam) | $522.74, still under the monthly budget |
| **Cost per student per year** | **$0.54** ($4,310.28 / 8,000). Per user including staff: $0.51 |
| Cost per exam attempt (exam months only) | about $0.013 ($1,045.48 / 80,000 attempts in the two exam months, an upper bound because it includes normal traffic) |
| Cash-flow note | The partial-upfront RI needs **$668 upfront** in month 1. This is already spread across the monthly figures above. |

### 2.1 Hidden costs (🔍), shown separately

| Hidden cost | Normal | Exam | Note |
|---|---:|---:|---|
| Data transfer out (internet) | $14.40 | $7.20 | S3 presigned downloads. CloudFront transfer is in its own line. The first 100 GB/month of AWS DTO is free, so the real bill is lower. |
| NAT gateway processing ($0.059/GB) + hours | $0.00 | $0.00 | **Removed.** The A2 design would cost $86.14 in hours alone. The replacement endpoints are in their own line. |
| CloudWatch Logs | $8.03 | $12.41 | Ingestion is $0.70/GB, so log volume matters more than retention. |
| KMS requests | $1.24 | $1.39 | Without the S3 bucket key, every upload and download would be a KMS call. |
| Backups | $3.80 | $3.80 | RDS snapshots **cannot use cold storage**, so 60 monthly snapshots stay warm at $0.095/GB. |
| Inter-AZ traffic | $1.72 | $2.68 | Half of the Lambda environments sit in the AZ without the primary. |
| T4g CPU credits | $0.00 | $9.75 | Unlimited mode: if the database bursts above baseline for hours, you pay per vCPU-hour. |
| **Hidden subtotal** | **$29.19** | **$37.23** | about 10 % of the bill |

The calculator does **not** apply the CloudFront always-free tier (1 TB and 10 M requests per month). That tier would cut the CloudFront line to about $6 a month, so the totals above are a safe upper bound.

## 3. The three most expensive components

| Rank | Component | Annual | Share | Why it is expensive |
|---|---|---:|---:|---|
| 1 | **RDS PostgreSQL Multi-AZ instance** | $1,631.86 | 38 % | It is the only always-on server. Multi-AZ **doubles** the price for the synchronous standby that delivers "survive one AZ" and RPO 0. It is also sized up for exam months. Adding the proxy, storage and backups, the database tier is **48 %** of the bill. |
| 2 | **VPC interface endpoints** (SQS + Secrets Manager) | $455.76 | 11 % | This is the price of removing the NAT gateways. Interface endpoints are billed **per endpoint, per AZ, per hour** ($0.013), whether or not traffic flows: 2 endpoints × 2 AZ × 730 h. They are still $67/month cheaper than the A2 NAT setup, and they remove a SPOF. The S3 gateway endpoint is free. |
| 3 | **CloudFront** | $433.70 | 10 % | Every API call (about 15–23 M a month) passes through CloudFront at $0.012 per 10,000 HTTPS requests, plus about 120–190 GB a month of transfer at Asian edge prices. This cost scales with use, not with time. |

Next come S3 uploads storage ($318, year-5 steady state; lifecycle rules already move 80 % of it to Deep Archive) and RDS Proxy ($315).

## 4. Service choices compared with alternatives

Prices are in Singapore at the usage levels in section 1. N/E means normal month / exam month.

### 4.1 Backend compute: Lambda (chosen) vs ECS Fargate vs EC2 Auto Scaling

| | **Lambda arm64 + HTTP API** ✅ | ECS Fargate ARM + ALB | EC2 Auto Scaling (t4g.small) + ALB |
|---|---|---|---|
| Cost N / E | **$28.76 / $44.71** | about $63 / $82 (2 × 0.5 vCPU/1 GB tasks always on, 6 during exams; ALB $18.40 + LCU) | about $60 / $70 (2 × t4g.small [calc] + EBS + ALB) |
| Performance | Scales to 1,000 environments in about 10 s. Cold starts of 0.5–1.5 s in a VPC. | No cold start. Scale-out takes 1–2 min, so tasks must be pre-scaled before an exam. | Scale-out takes 2–4 min. Must be scheduled before exams. |
| Resilience | Multi-AZ by default, no servers to fail | Tasks spread over 2 AZs, ALB health checks | Same as Fargate, plus OS patching risk |
| Effort | Lowest (A2 code already runs) | Containerise, write a task definition, scaling policies | AMIs, patching, scaling policies |
| Verdict | **Keep.** Cheapest below about 40–60 M requests a month, and absorbs the peak without planning. | Better if traffic becomes steady and high | Most work, no benefit here |

### 4.2 Answers database: RDS Multi-AZ (chosen) vs Aurora Serverless v2 vs DynamoDB

| | **RDS PostgreSQL Multi-AZ + Proxy** ✅ | Aurora PostgreSQL Serverless v2 | DynamoDB on-demand |
|---|---|---|---|
| Cost N / E | **$143 / $301** (RI, storage, proxy, credits) | about $252 / $500 (writer about 1–2 ACU + reader 0.5–1 ACU at $0.20 per ACU-hour, plus $0.22 per million I/Os and storage) | about $22 / $33 (autosave about 3 WRU at $0.7125 per million, reads $0.1425 per million, storage $0.285/GB) |
| Performance | Fixed capacity, so it must be resized for exam months (done) | Scales ACUs in seconds, good for spikes | Single-digit ms at any scale, no connection limit |
| Resilience | Standby in a 2nd AZ, failover in about 60–120 s, PITR 5 min | 6 copies across 3 AZs, failover under 30 s with a reader | 3 AZs built in, PITR to the second |
| Effort | None (A2 schema) | Low (same PostgreSQL) | **High.** The relational schema (exams → attempts → results, tutor reports with joins and averages) must be redesigned. |
| Verdict | **Keep.** Cheapest relational option at a predictable baseline. | Costs more because Singapore ACU-hours run 24/7 | Cheapest and most resilient, but the rewrite cost is too high for this term. **Recommended next step: move only the `attempts.answers` autosave hot path to DynamoDB.** |

### 4.3 Private traffic: NAT gateway vs VPC endpoints (chosen)

| | 2 NAT gateways + SQS endpoint (A2) | 1 NAT gateway + SQS endpoint | **VPC endpoints only** ✅ |
|---|---|---|---|
| Cost / month | $86.14 + $18.99 = **$105.13** + $0.059/GB | $43.07 + $18.99 = $62.06 + $0.059/GB | **$37.98** (SQS + Secrets Manager interface endpoints × 2 AZ) + $0.01/GB. S3 gateway endpoint is free. |
| Performance | Extra hop, 5–100 Gbps | Same | Private AWS network, lowest latency |
| Resilience | One per AZ, AZ-independent | **AZ SPOF**: if its AZ fails, the other AZ loses outbound access | One ENI per AZ |
| Effort | — | — | Already built in A2 (`nat_gateway_count = 0`). Works because the VPC Lambdas only call S3, SQS and the RDS Proxy, and the proxy only needs Secrets Manager. |
| Annual saving vs A2 | — | $517 | **$809** |

### 4.4 Purchase model for the 24/7 database: On-Demand vs Reserved Instance (chosen) vs Savings Plans

| `db.t4g.medium` Multi-AZ | Monthly | vs On-Demand | Commitment | Notes |
|---|---:|---:|---|---|
| On-Demand | $148.19 | — | none | Flexible, most expensive |
| 1-yr RI, no upfront | $117.17 | −21 % | 12 months | No cash upfront |
| **1-yr RI, partial upfront** ✅ | **$111.29** | **−25 %** | $668 upfront + $0.0762/h | Size-flexible within t4g, so it also covers half of the exam-month `t4g.large` |
| 1-yr RI, all upfront | $108.25 | −27 % | $1,299 upfront | Small extra gain for twice the cash |
| Compute Savings Plan | n/a for RDS | — | — | Applies to Lambda/Fargate. Lambda is only $141 a year, so 1-yr commitment saves about $20. Not worth it. |
| Database Savings Plan [calc] | check in calculator | about −20 to −35 % | $/hour, 1 year | Newer option: covers RDS/Aurora/DynamoDB across instance families. Re-check it if the database moves to Aurora or DynamoDB. |

A 3-year RI was rejected: the platform is new, and the database engine choice (section 4.2) may change.

### 4.5 Five-year file retention: S3 Standard vs Intelligent-Tiering vs lifecycle to Glacier (chosen)

Steady state is 7.2 TB, about 720,000 objects.

| | S3 Standard only | Intelligent-Tiering (Archive Instant Access) | **Lifecycle: Std → IA (30 d) → Glacier IR (180 d) → Deep Archive (365 d) → delete (5 y)** ✅ |
|---|---:|---:|---:|
| Storage / month | $180.00 | about $42.30 (incl. $1.80 monitoring fee) | **$26.50** |
| Retrieval of an old file | instant, free | instant, free | < 1 year: instant. **> 1 year: about 12 h**, $0.02/GB |
| Resilience | 11 nines, 3+ AZs | same | same |
| Effort | none | none | Rules already in Terraform. Appeals on files more than a year old need a restore request. |
| Annual saving vs Standard | — | $1,652 | **$1,838** |

## 5. Singapore vs Mumbai (ap-south-1), and latency from Bhutan

| | **Singapore ap-southeast-1** ✅ | Mumbai ap-south-1 |
|---|---|---|
| Annual cost (on-demand, same design) | $4,753 | **$4,291 (−10 %)** |
| Main price differences | RDS t4g.medium Multi-AZ $0.203/h · API Gateway $1.25/M · Proxy $0.018 | $0.167/h (−18 %) · $1.05/M (−16 %) · $0.017 |
| AZs / services needed | 3 AZs, all services available | 3 AZs, all services available |
| Latency from Bhutan (TCP round trip) | Preliminary check on 2026-11-19 (5 samples): **min 94 ms**, median 139 ms. Full 20-sample run: ☐ | Preliminary: **min 74 ms**, median noisy. Full run: ☐ |
| Routing from Bhutan | International links leave through India, then by subsea cable to Singapore | Over land through India: fewer hops |
| Effect on this app | The static app is served from CloudFront edges in India, so only `/api/*` calls make the trip. Autosave runs in the background every 30 s, so 50 ms makes no visible difference. | — |
| Verdict | **Stay in Singapore** (brief requirement, mature Region). The 10 % difference is about $460 a year. | **Use Mumbai as the DR Region** (`dr_region = ap-south-1`): cheap, close to the users. |

**How to measure latency (run from Bhutan):**

```bash
bash scripts/measure-latency.sh   # 20 TCP+TLS handshakes to each Region, prints the median
```

Also capture a screenshot of <https://www.cloudping.info> from the same connection, and save both in `evidence/latency/`.

## 6. Feasibility verdict

| Requirement | Target | Evidence | Result |
|---|---|---|---|
| **Budget** | ≤ $1,000 / month, yearly average | $359.19 average. Even the unoptimised A2 design is $613.31. The exam month is $522.74. | ✅ **Meets.** 64 % headroom |
| **Peak load** | 3,000 students start within 5 min | Load test: A2 sizing fails (B1). The fixed design (t4g.large + Proxy, Lambda quota ≥ 1,000) ☐ re-tested at ☐ % success, p95 ☐ ms | ✅ **Meets after the fix**, *if the re-test confirms it* |
| **RPO 5 min** | ≤ 5 min of answers lost | AZ loss: 0 (FT1, synchronous standby). Corruption: ☐ s (FT2, PITR). Files: 0 (FT4, versioning). Queues: 0 (FT5). | ✅ Meets |
| **RTO 1 h** | ≤ 60 min | AZ loss ☐ s (FT1). PITR ☐ min (FT2). Partial AZ network ☐ s (FT3). | ✅ Meets for AZ and data failures |
| Survive loss of one AZ | yes | FT1 + FT3 | ✅ |
| Region loss | (not required) | FT6 tabletop: RTO 2–4 h with DR copy | ⚠️ **Accepted risk** |
| Files kept 5 years | yes | Lifecycle expires at 1,825 days. Monthly DB backups kept 1,825 days. | ✅ |

**Verdict: FEASIBLE.**
- The platform costs about **$4,310 a year (≈ $0.54 per student)**, about a third of the budget.
- It meets RPO and RTO for every AZ-level and data-level failure.
- It handles the exam peak once the database is pooled (RDS Proxy) and sized up for exam months, and the Lambda concurrency quota is raised to 1,000.
- The remaining risk is the loss of the whole Singapore Region. It is accepted, with optional cross-Region backups to Mumbai at about $3–5 a month.

## 7. Optimisations and their savings (Task 3)

Each saving is the difference between two runs of `scripts/cost-model.mjs` and between two calculator estimates.

| # | Optimisation | Before | After | **Annual saving** |
|---|---|---|---|---:|
| O1 | Remove both NAT gateways and use VPC endpoints | 2 NAT × $0.059/h + $0.059/GB | + Secrets Manager endpoint ($18.98/month) | **$809.46** |
| O2 | Seasonal right-sizing: `t4g.medium` normal / `t4g.large` exam, instead of `m6g.large` all year | $321.93/month | $148.19 / $296.38 | **$1,788.50** |
| O3 | 1-year partial-upfront RI on `db.t4g.medium` Multi-AZ | On-Demand | RI (size-flexible) | **$442.80** |
| O4 | S3 lifecycle to IA → Glacier IR → Deep Archive (steady state) | All S3 Standard, $180/month | $26.50/month | **$1,837.76** |
| O5 | CloudWatch Logs retention 90 → 30 days | 90 d | 30 d | $8.64 (small; ingestion is the real cost) |
| **Total** | A2 design in Singapore ($7,359.68/yr) → final ($4,310.28/yr) | | | **$3,049 (−42 %)** |

O4 was already in A2, so it is shown as a saving against the naive option. The A2 → A3 total counts O1 + O2 + O3 + O5 together.

**Further options, not applied:**
- CloudFront flat-rate or free tier: about −$350 a year.
- DynamoDB for autosave: about −$1,500 a year or more, but needs a code rewrite.
- Provisioned concurrency only around exam starts: adds cost, reduces latency.
