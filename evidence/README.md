# Evidence

As agreed with the tutor, **these screenshots replace the demo video**.

- Every AWS console screenshot was taken in **Asia Pacific (Singapore)**. The exception is the WAF metrics, which AWS keeps in us-east-1.
- The raw output (CSV / JSON / text) sits next to the screenshots in each folder.

**Contents**
1. [Account and quotas](#1-account-and-quotas)
2. [Pricing Calculator](#2-pricing-calculator)
3. [Latency from Bhutan](#3-latency-from-bhutan)
4. [Architecture](#4-architecture)
5. [Deployment in Singapore](#5-deployment-in-singapore)
6. [Load test](#6-load-test)
7. [Failure tests](#7-failure-tests)
8. [Tear down](#8-tear-down)

---

## 1. Account and quotas

**AWS account**

![AWS account](aws-account/aws-account.png)

**Region set to Singapore**

![Region set to Singapore](aws-account/set-region.png)

**Lambda quota: 1,000**

![Lambda quota: 1,000](quotas/lambda-quota.png)

## 2. Pricing Calculator

Explained in the [cost report §8](../docs/cost-report.md#8-aws-pricing-calculator-check). Share links are in the [README](../README.md#2-reports).

| Estimate | Calculator total | Exports |
|---|---|---|
| Normal month | $268.85 / month + $668 upfront | [csv](calculator/normal-month.csv) · [pdf](calculator/normal-month.pdf) · [json](calculator/normal-month.json) |
| Exam month | $460.54 / month + $668 upfront | [csv](calculator/exam-month.csv) · [pdf](calculator/exam-month.pdf) · [json](calculator/exam-month.json) |
| A2 design in Singapore | $602.61 / month | [csv](calculator/a2-baseline.csv) · [pdf](calculator/a2-baseline.pdf) · [json](calculator/a2-baseline.json) |

**Normal month**

![Normal month](calculator/normal-month-summary.png)

**Exam month**

![Exam month](calculator/exam-month-summary.png)

**A2 design in Singapore**

![A2 design in Singapore](calculator/a2-baseline-summary.png)

**Optimisation steps:**

**O1 NAT gateways back (+$67.46)**

![O1 NAT gateways back (+$67.46)](calculator/O1-remove-nat.png)

**O2 `m6g.large` (+$173.74)**

![O2 `m6g.large` (+$173.74)](calculator/O2-right-size.png)

**O3 On-Demand (+$442.72 a year)**

![O3 On-Demand (+$442.72 a year)](calculator/O3-reserved.png)

**O4 all S3 Standard (+$152.83)**

![O4 all S3 Standard (+$152.83)](calculator/O4-s3-standard.png)

**O5 logs: the calculator only supports 1-month retention**

![O5 logs: the calculator only supports 1-month retention](calculator/O5-logs.png)

## 3. Latency from Bhutan

Raw data: [`latency-20261120-1418.csv`](latency/latency-20261120-1418.csv). Median: Singapore **145 ms** · Hyderabad 155 ms · Mumbai 165 ms · N. Virginia 364 ms.

**`measure-latency.sh` (20 samples per Region)**

![`measure-latency.sh` (20 samples per Region)](latency/latency-terminal.png)

**cloudping.info**

![cloudping.info](latency/cloudping.png)

## 4. Architecture

![](../architecture/overall-architecture.png)

The simulator run of a student autosave: **13 steps, HTTP 200 in 160 ms.**

**Steps 1–4**

![Steps 1–4](../architecture/timeline-1.png)

**Steps 5–8**

![Steps 5–8](../architecture/timeline-2.png)

**Steps 9–12**

![Steps 9–12](../architecture/timeline-3.png)

**Step 13**

![Step 13](../architecture/timeline-4.png)

## 5. Deployment in Singapore

**Bootstrap**

![Bootstrap](deploy/bootstrap-outputs.png)

**GitHub variables**

![GitHub variables](deploy/github-variables.png)

**Pipeline green**

![Pipeline green](deploy/pipeline-green.png)

**Terraform init**

![Terraform init](deploy/terraform-init.png)

**Terraform apply**

![Terraform apply](deploy/terraform-apply-log.png)

**Terraform outputs**

![Terraform outputs](deploy/terraform-output-1.png)

**No NAT gateways**

![No NAT gateways](deploy/vpc-no-nat.png)

**VPC endpoints**

![VPC endpoints](deploy/vpc-endpoints.png)

**Subnets in 2 AZs**

![Subnets in 2 AZs](deploy/subnets-2az.png)

**RDS Multi-AZ**

![RDS Multi-AZ](deploy/rds-multi-az.png)

**Lambda arm64**

![Lambda arm64](deploy/lambda-arm64.png)

**S3 lifecycle (5 years)**

![S3 lifecycle (5 years)](deploy/s3-lifecycle.png)

**Backup plan**

![Backup plan](deploy/backup-plan.png)

**Daily rule (35 days)**

![Daily rule (35 days)](deploy/backup-plan-daily.png)

**Monthly rule (5 years)**

![Monthly rule (5 years)](deploy/backup-plan-monthly.png)

**CloudWatch dashboard**

![CloudWatch dashboard](deploy/dashboard.png)

**Alarm subscription**

![Alarm subscription](notify/subscribe.png)

**Alarm email**

![Alarm email](notify/email_sns.png)

**The app working:**

**Users created**

![Users created](deploy/users-created.png)

**Tutor created an exam**

![Tutor created an exam](deploy/tutor-exam-created.png)

**Student autosave**

![Student autosave](deploy/app-autosave.png)

**Answers kept after refresh**

![Answers kept after refresh](deploy/autosave-after-refresh.png)

## 6. Load test

Explained in the [load-test report](../docs/load-test.md). Raw output: [`load-test/`](load-test) and [`cloudwatch/`](cloudwatch).

**Before (WAF 20,000 per IP) — Script result**

![Before (WAF 20,000 per IP) — Script result](load-test/before-terminal.png)

**After (fix applied) — Script result**

![After (fix applied) — Script result](load-test/after-terminal.png)

**Before (WAF 20,000 per IP) — Dashboard**

![Before (WAF 20,000 per IP) — Dashboard](load-test/before-dashboard.png)

**After (fix applied) — Dashboard**

![After (fix applied) — Dashboard](load-test/after-dashboard.png)

**Before (WAF 20,000 per IP) — Database and Lambda**

![Before (WAF 20,000 per IP) — Database and Lambda](load-test/before-rds-connections.png)

**After (fix applied) — Database and Lambda**

![After (fix applied) — Database and Lambda](load-test/after-rds-connections.png)

**Before (WAF 20,000 per IP) — API requests and errors**

![Before (WAF 20,000 per IP) — API requests and errors](load-test/before-api-errors.png)

**After (fix applied) — API requests and errors**

![After (fix applied) — API requests and errors](load-test/after-api-errors.png)

**Before (WAF 20,000 per IP) — WAF blocked requests**

![Before (WAF 20,000 per IP) — WAF blocked requests](load-test/before-waf-blocked.png)

**After (fix applied) — WAF blocked requests**

![After (fix applied) — WAF blocked requests](load-test/after-waf.png)

**The fix:**

**Variables changed**

![Variables changed](load-test/fix-variables.png)

**Free plan refused a bigger database**

![Free plan refused a bigger database](load-test/free-plan-error.png)

**WAF rules after the fix**

![WAF rules after the fix](load-test/fix-waf-rules.png)

**API concurrency cap = 40**

![API concurrency cap = 40](load-test/fix-api-concurrency.png)

## 7. Failure tests

Explained in the [failure-test report](../infra/failure-tests/README.md). Raw output: [`failure-tests/`](failure-tests).

**FT1: losing the database AZ** (RTO 66 s, RPO 0)

**Primary in 1a**

![Primary in 1a](failure-tests/ft1-before-az.png)

**Test output**

![Test output](failure-tests/ft1-terminal.png)

**Primary in 1b**

![Primary in 1b](failure-tests/ft1-after-az.png)

**RDS events**

![RDS events](failure-tests/ft1-rds-events.png)

**Alarm email**

![Alarm email](failure-tests/ft1-sns-email.png)

**FT2: point-in-time restore** (RPO 154 s, RTO ≈ 22 min)

**RPO reading**

![RPO reading](failure-tests/ft2-rpo.png)

**Restored database**

![Restored database](failure-tests/ft2-restored-instance.png)

**Restore time**

![Restore time](failure-tests/ft2-rto.png)

**FT3: losing the network of one AZ** (healed itself in 120 s)

**Deny-all ACL**

![Deny-all ACL](failure-tests/ft3-nacl-fault.png)

**Test output**

![Test output](failure-tests/ft3-terminal.png)

**Dashboard**

![Dashboard](failure-tests/ft3-dashboard.png)

**FT4: deleted file** (recovered in 73 s, identical)

**Versions with the delete marker**

![Versions with the delete marker](failure-tests/ft4-s3-versions.png)

**Recovered**

![Recovered](failure-tests/ft4-terminal.png)

**FT5: marking worker stopped** (backlog cleared in 96 s, 0 lost)

**Worker stopped**

![Worker stopped](failure-tests/ft5-concurrency-zero.png)

**Test output**

![Test output](failure-tests/ft5-terminal.png)

**Queue depth**

![Queue depth](failure-tests/ft5-queue-depth.png)

## 8. Tear down

**Tear-down workflow**

![Tear-down workflow](teardown/teardown-green.png)

**Nothing left in the account**

![Nothing left in the account](teardown/nothing-left.png)

Cost Explorer was not available, because the class account gives students no Billing access. The cost of the test stack is estimated from its running time in the [cost report §10](../docs/cost-report.md#10-what-the-testing-itself-cost) (≈ $1.41).
