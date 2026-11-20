# Change log: Assignment 2 → Assignment 3

Each row names the finding that caused the change.
- **Cost:** `docs/cost-report.md`
- **Load:** `docs/load-test.md`
- **FTn:** `infra/failure-tests/README.md`

| # | Area | Assignment 2 | Assignment 3 | Why (finding) | Effect |
|---|---|---|---|---|---|
| C1 | Region | us-east-1 (N. Virginia) | **ap-southeast-1 (Singapore)** | Brief, plus latency from Bhutan: median round trip **364 ms to N. Virginia vs 145 ms to Singapore** (20 samples, `evidence/latency/`, 2026-11-20) | Every price re-checked for Singapore on 2026-11-19 |
| C2 | Outbound network | 2 NAT gateways (one per AZ) + SQS endpoint | **0 NAT gateways.** S3 gateway endpoint plus SQS and **Secrets Manager** interface endpoints (the proxy reads its secret privately). | Cost: in the A2 design moved to Singapore, the NAT gateways are the 2nd most expensive item ($86/month) and carried no traffic the endpoints could not carry | −$809/year. One less SPOF |
| C3 | Database size | `db.t4g.micro` demo, `db.m6g.large` "for exam week" all year | **`db.t4g.medium` in normal months, `db.t4g.large` in exam months** (`exam-month.tfvars` / `DB_INSTANCE_CLASS`) | Load: micro collapses at the peak (B1). Cost: m6g.large all year is the biggest single cost | −$1,789/year vs m6g.large all year |
| C4 | Database pricing | On-Demand | **1-year Reserved Instance, `db.t4g.medium` Multi-AZ, partial upfront**. Size-flexible, so it covers half of the `t4g.large` in exam months. | Cost: RDS is the #1 cost and runs 24/7 | −$443/year |
| C5 | Connection pooling | RDS Proxy optional (off in the demo) | **RDS Proxy always on.** Free-plan fallback: `API_RESERVED_CONCURRENCY` cap. | Load test B1 (connection exhaustion); FT1 (faster failover) | Peak is survivable; failover impact drops to seconds |
| C6 | Logs | 90-day retention | **30-day** retention | Cost: logs are not needed after marking; CloudTrail keeps the audit trail | Small saving; less personal data stored |
| C7 | Monitoring | Generic dashboard | **Load-test rows added:** Lambda throttles/concurrency/p95, RDS connections/memory/credits, Proxy borrow latency | Rubric: the bottleneck must be *proven* with CloudWatch | Evidence for the load test |
| C8 | AZ evacuation | Lambda subnets fixed | **`lambda_subnet_indexes`** variable | FT3: Lambda keeps using a subnet whose network is broken | RTO for a partial AZ fault ≈ 3 min |
| C9 | Chaos testing | Manual failover script only | **5 failure-test scripts.** FT3 uses a deny-all network ACL, because AWS FIS returned `SubscriptionRequiredException` on this account. The FIS template (`infra/fis.tf`) is kept, switched off. | Rubric: at least 4 measured scenarios | Repeatable tests |
| C10 | Disaster recovery | Backups in one Region | **Optional cross-Region copy to ap-south-1** (`ENABLE_DR_BACKUP_COPY`) | FT6: Region loss would lose every backup | RPO 24 h / RTO 2–4 h for Region loss, ≈ $3–5/month |
| C11 | Backups (cost note) | `cold_storage_after = 90` on monthly backups | Kept, but **documented as having no effect for RDS** | Cost: RDS snapshots cannot move to cold storage, so the 5-year monthlies stay warm | Costed honestly |
| C14 | WAF rate limiting | 20,000 requests / 5 min **per IP** | **1,000 / 5 min per student token** (`RateLimitPerStudent`) + 150,000 / 5 min per-IP flood backstop | Load test B1: WAF blocked 11,762 requests (26 %) because the whole peak came from one IP, just as a campus behind one NAT would | Peak no longer blocked at the edge; +$1/month |
| C13 | Resource names | `exam-platform-prod-*` | **`exam-platform-a3-prod-*`** (`project = "exam-platform-a3"`) | The first Singapore deploy failed: global names (IAM roles, S3 buckets, WAF, CloudFront OAC) clashed with an existing `exam-platform-prod` stack in the shared account | A3 can be deployed and destroyed without touching any other stack |
| C12 | Deploy settings | — | New GitHub variables: `DB_INSTANCE_CLASS`, `API_RESERVED_CONCURRENCY`, `ENABLE_FIS`, `ENABLE_DR_BACKUP_COPY` | Seasonal sizing must be a one-line change | Exam-month switch through CI |

## Kept from Assignment 2 (re-checked and still the best choice)

- **Lambda (arm64) behind an HTTP API.** It is cheapest at this traffic level, needs no idle servers, and scales instantly. See comparison 1 in the cost report.
- **RDS PostgreSQL Multi-AZ.** It is relational, cheaper than Aurora at a constant baseline, and meets the RPO. See comparison 2.
- **S3 lifecycle to Deep Archive.** It saves about $1,838/year at steady state compared with S3 Standard. See comparison 5.
- **CloudFront + WAF, Cognito, SQS + DLQ, KMS, and Terraform with GitHub OIDC.**
