# Exam platform on AWS: cost, resilience and load (Singapore)

**DSO303 – Assignment 3.** This builds on [Assignment 2](https://github.com/Rynorbu/DSO303-Assignment-02).

The university wants to know three things about running the Assignment 2 exam platform in **ap-southeast-1 (Singapore)**:
- what it will cost,
- whether that is affordable within **USD 1,000 a month**,
- where it will fail or slow down.

There are 8,000 students and 400 staff. Normal months have 300–500 concurrent users. In the 2 exam months, 3,000 students start one exam within 5 minutes.

## Summary

| | |
|---|---|
| **Final design** | CloudFront + WAF → API Gateway HTTP API → Lambda arm64 in 2 AZs → **RDS Proxy** → RDS PostgreSQL **Multi-AZ** (`t4g.medium`, or `t4g.large` in exam months). S3 with lifecycle to Deep Archive, SQS + DLQ, Cognito, KMS, AWS Backup. **No NAT gateways.** |
| **Cost** | Normal month **$325.48**, exam month **$521.74**. Annual **$4,298.28**. Average **$358.19/month**. **$0.54 per student per year.** |
| **Saving vs Assignment 2** (moved to Singapore unchanged) | $7,347.68 → $4,298.28 a year (**−42 %**) from removing the NATs, seasonal sizing, a Reserved Instance and shorter log retention |
| **Biggest costs** | RDS instance (38 %), VPC interface endpoints (11 %), CloudFront (10 %) |
| **Where it breaks** | DB connections at the exam peak without a proxy (load test B1); Lambda concurrency quota (B2); SES rate when results are released (B3); loss of the whole Region (FT6, accepted) |

## Feasibility verdict: **FEASIBLE**

| Requirement | Result |
|---|---|
| Budget ≤ $1,000/month (yearly average) | ✅ $358.19 (36 % of budget). Exam month $521.74. |
| Peak: 3,000 students start within 5 min | ✅ after the fix: RDS Proxy + `t4g.large` + Lambda quota ≥ 1,000. Re-test: ☐ % success, p95 ☐ ms ([load test](docs/load-test.md)) |
| RPO 5 min | ✅ AZ loss 0 s (FT1) · data corruption ☐ s (FT2) · files 0 s (FT4) |
| RTO 1 h | ✅ AZ failover ☐ s (FT1) · point-in-time restore ☐ min (FT2) · AZ network ☐ s (FT3) |
| Survive loss of one AZ | ✅ FT1, FT3 |
| Region loss | ⚠️ accepted risk. Optional backup copy to Mumbai gives RTO 2–4 h (FT6). |

## Links

| | |
|---|---|
| 📸 **Evidence: screenshots** (agreed with the tutor in place of the video): load test, failure tests, calculator, deployment | [`evidence/README.md`](evidence/README.md) |
| AWS Pricing Calculator: **normal month** | ☐ *paste share link* |
| AWS Pricing Calculator: **exam month** | ☐ *paste share link* |
| AWS Pricing Calculator: **A2 baseline** (to show the savings) | ☐ *paste share link* |
| Prices checked on | **2026-11-19** (Price List API) · calculator: ☐ *date* |

## Deliverables

| Deliverable | Where |
|---|---|
| Revised architecture, SPOF markings | [`architecture/README.md`](architecture/README.md) |
| Change log against Assignment 2 | [`architecture/CHANGELOG.md`](architecture/CHANGELOG.md) |
| Cost and service report | [`docs/cost-report.md`](docs/cost-report.md) |
| Calculator inputs (to reproduce the estimates) | [`docs/calculator-inputs.md`](docs/calculator-inputs.md) |
| Load test (bottleneck, fix, re-test) | [`docs/load-test.md`](docs/load-test.md) |
| Failure test scenarios, expected impact and solutions | [`infra/failure-tests/README.md`](infra/failure-tests/README.md) |
| Calculator exports, CloudWatch, test output | [`evidence/`](evidence/README.md) |
| Terraform (updated for Singapore) | [`infra/`](infra) |
| Scripts: cost model, load test, failure tests, latency | [`scripts/`](scripts) |

## Deploy (changes from Assignment 2)

The pipeline is the same as Assignment 2: bootstrap, then GitHub variables, then push to `main`. The A2 steps are in [`architecture/assignment-2-architecture.md`](architecture/assignment-2-architecture.md) and the A2 repo. What is new:

| GitHub variable | Value | Why |
|---|---|---|
| `AWS_REGION` | `ap-southeast-1` | Singapore |
| `TF_STATE_REGION` | `us-east-1` | Only if you reuse the A2 state bucket. Leave it out if you bootstrap again in Singapore. |
| `DB_INSTANCE_CLASS` | `db.t4g.medium` (normal) / `db.t4g.large` (exam month) | Seasonal sizing (O2) |
| `DB_USE_RDS_PROXY` | `true` on a paid plan (`false` on the AWS Free plan) | Load-test fix |
| `API_RESERVED_CONCURRENCY` | `60` only when there is no RDS Proxy | Free-plan load-test fix |
| `ENABLE_FIS` | leave **unset** (`false`) | AWS FIS is blocked on the Free plan; FT3 uses a deny-all network ACL instead |
| `ENABLE_DR_BACKUP_COPY` | `true` (optional) | Cross-Region backup copy to Mumbai |


**From a laptop:**

```bash
cd backend && npm ci --omit=dev && cd ../infra
cp example.tfvars terraform.tfvars                                   # edit the emails
terraform init -backend-config="bucket=<state_bucket>" -backend-config="region=<bucket region>"
terraform apply                                                      # normal month
terraform apply -var-file=terraform.tfvars -var-file=exam-month.tfvars   # exam month
```

## Tear down

Run **Actions → Tear down → `DESTROY`** (or `terraform destroy`). Then check in **Singapore**, and in **Mumbai** if the DR copy was on, that nothing named `exam-platform-a3-prod` is left: RDS, Lambda, CloudFront, the VPC endpoint, Backup vaults. The RDS Proxy and the Multi-AZ database cost about **$5 a day**, so destroy the stack as soon as the evidence is captured.

## Repository layout

```
architecture/   README.md (revised diagram + SPOFs) · CHANGELOG.md · assignment-2-architecture.md
docs/           cost-report.md · calculator-inputs.md · load-test.md · services-assignment-2.md
infra/          Terraform (+ fis.tf, exam-month.tfvars, load-test-baseline.tfvars) · failure-tests/README.md
scripts/        cost-model.mjs · peak-load-test.mjs · seed-load-users.sh · export-metrics.sh
                measure-latency.sh · failure-tests/ft1..ft5 · seed-users.sh · ci-settings.sh
evidence/       calculator/ · load-test/ · cloudwatch/ · failure-tests/ · latency/
backend/ frontend/ .github/   unchanged application code and CI/CD from Assignment 2
todo.md         step-by-step plan to finish the assignment
```
