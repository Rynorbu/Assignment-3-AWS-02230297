# Evidence

As agreed with the tutor, **screenshots replace the demo video**.

- Every AWS console screenshot was taken in **Asia Pacific (Singapore) `ap-southeast-1`**.
- File names match the step IDs in [`todo.md`](../todo.md).
- Machine-generated output (CSV/JSON) is saved next to the screenshots by the scripts.

**Contents:**
1. [Quotas and safety](#1-quotas-and-safety)
2. [Pricing Calculator](#2-pricing-calculator-costed-estimate)
3. [Latency from Bhutan](#3-latency-from-bhutan)
4. [Architecture](#4-architecture)
5. [Deployment in Singapore](#5-deployment-in-singapore)
6. [Load test](#6-load-test-bottleneck-proven-fixed-re-tested)
7. [Failure tests](#7-failure-tests)
8. [Actual cost and tear down](#8-actual-cost-and-tear-down)

---

## 1. Quotas and safety

| S01 Lambda concurrency quota | S02 SES production access request | S03 Safety budget |
|---|---|---|
| ![](quotas/S01-lambda-quota.png) | ![](quotas/S02-ses-request.png) | ![](quotas/S03-budget.png) |

## 2. Pricing Calculator (costed estimate)

Links: see the [README](../README.md#links). Exports:
- normal month: [`normal-month.csv`](calculator/normal-month.csv) · [`normal-month.pdf`](calculator/normal-month.pdf)
- exam month: [`exam-month.csv`](calculator/exam-month.csv) · [`exam-month.pdf`](calculator/exam-month.pdf)
- A2 baseline: [`a2-baseline.csv`](calculator/a2-baseline.csv) · [`a2-baseline.pdf`](calculator/a2-baseline.pdf)

| S04 Normal month | S05 Exam month | S06 A2 design in Singapore (baseline) |
|---|---|---|
| ![](calculator/S04-normal-month-summary.png) | ![](calculator/S05-exam-month-summary.png) | ![](calculator/S06-a2-baseline-summary.png) |

**Optimisations, applied one at a time** (saving = previous total − new total):

| S07 O1 Remove NAT gateways | S08 O2 Right-size the DB | S09 O3 Reserved Instance |
|---|---|---|
| ![](calculator/S07-O1-remove-nat.png) | ![](calculator/S08-O2-right-size.png) | ![](calculator/S09-O3-reserved.png) |

| S10 O5 Log retention 30 days | S11 O4 S3 Standard vs lifecycle |
|---|---|
| ![](calculator/S10-O5-logs.png) | ![](calculator/S11-O4-s3-standard.png) |

## 3. Latency from Bhutan

| S12 `measure-latency.sh` (20 samples per Region) | S13 cloudping.info |
|---|---|
| ![](latency/S12-latency-terminal.png) | ![](latency/S13-cloudping.png) |

## 4. Architecture

**S14 Revised, cost-optimised architecture with SPOF markers**

![](architecture/S14-architecture-a3.png)

## 5. Deployment in Singapore

| S15 Bootstrap outputs | S16 GitHub variables | S17 Pipeline green |
|---|---|---|
| ![](deploy/S15-bootstrap-outputs.png) | ![](deploy/S16-github-variables.png) | ![](deploy/S17-pipeline-green.png) |

| S18 Terraform apply log | S19 Terraform outputs | S20 No NAT gateways (O1) |
|---|---|---|
| ![](deploy/S18-terraform-apply-log.png) | ![](deploy/S19-terraform-outputs.png) | ![](deploy/S20-vpc-no-nat.png) |

| S21 VPC endpoints | S22 Subnets in 2 AZs | S23 RDS Multi-AZ |
|---|---|---|
| ![](deploy/S21-vpc-endpoints.png) | ![](deploy/S22-subnets-2az.png) | ![](deploy/S23-rds-multi-az.png) |

| S24 Lambda arm64 | S25 Backup plan (5 years) | S26 S3 lifecycle |
|---|---|---|
| ![](deploy/S24-lambda-arm64.png) | ![](deploy/S25-backup-plan.png) | ![](deploy/S26-s3-lifecycle.png) |

| S27 CloudWatch dashboard (A3 rows) | S28 App running, autosave |
|---|---|
| ![](deploy/S27-dashboard.png) | ![](deploy/S28-app-autosave.png) |

## 6. Load test: bottleneck proven, fixed, re-tested

Raw results: [`load-test/`](load-test) (JSON + CSV from the script) · [`cloudwatch/`](cloudwatch) (metric exports). Analysis: [`docs/load-test.md`](../docs/load-test.md).

| | **BEFORE** (A2 sizing: `t4g.micro`, no proxy) | **AFTER** (fix applied) |
|---|---|---|
| Script summary | ![](load-test/S29-before-terminal.png) | ![](load-test/S36-after-terminal.png) |
| Whole dashboard | ![](load-test/S30-before-dashboard.png) | ![](load-test/S37-after-dashboard.png) |
| RDS connections / memory | ![](load-test/S31-before-rds-connections.png) | ![](load-test/S38-after-rds-connections.png) |
| API + Lambda errors | ![](load-test/S32-before-api-errors.png) | ![](load-test/S39-after-api-errors.png) |
| Logs Insights: error cause | ![](load-test/S33-before-logs-insights.png) | ![](load-test/S40-after-logs-insights.png) |

| S34 Fix: changed variables | S35 Fix applied (new class / proxy) |
|---|---|
| ![](load-test/S34-fix-variables.png) | ![](load-test/S35-fix-applied.png) |

## 7. Failure tests

Scenarios, expected impact, measurements and fixes: [`infra/failure-tests/README.md`](../infra/failure-tests/README.md). Raw output: [`failure-tests/`](failure-tests).

**FT1: loss of the AZ that hosts the primary database**

| S41 Primary AZ before | S42 Downtime + RPO check | S43 Primary AZ after |
|---|---|---|
| ![](failure-tests/S41-ft1-before-az.png) | ![](failure-tests/S42-ft1-terminal.png) | ![](failure-tests/S43-ft1-after-az.png) |

| S44 RDS failover events | S45 Alarm email |
|---|---|
| ![](failure-tests/S44-ft1-rds-events.png) | ![](failure-tests/S45-ft1-sns-email.png) |

**FT2: point-in-time restore after logical data loss**

| S46 RPO exposure | S47 Restored instance | S48 Restore time (RTO) |
|---|---|---|
| ![](failure-tests/S46-ft2-rpo.png) | ![](failure-tests/S47-ft2-restored-instance.png) | ![](failure-tests/S48-ft2-rto.png) |

**FT3: network loss in one AZ (AWS FIS)**

| S49 FIS experiment | S50 Probe results | S51 Errors on the dashboard | S52 Re-test after the fix (optional) |
|---|---|---|---|
| ![](failure-tests/S49-ft3-fis-experiment.png) | ![](failure-tests/S50-ft3-terminal.png) | ![](failure-tests/S51-ft3-dashboard.png) | ![](failure-tests/S52-ft3-fix-retest.png) |

**FT4: deleted assignment file**

| S53 Recovered, checksum identical | S54 S3 versions + delete marker |
|---|---|
| ![](failure-tests/S53-ft4-terminal.png) | ![](failure-tests/S54-ft4-s3-versions.png) |

**FT5: marking worker outage**

| S55 Worker stopped | S56 Backlog drained | S57 Queue depth | S58 DLQ alarm |
|---|---|---|---|
| ![](failure-tests/S55-ft5-concurrency-zero.png) | ![](failure-tests/S56-ft5-terminal.png) | ![](failure-tests/S57-ft5-queue-depth.png) | ![](failure-tests/S58-ft5-dlq-alarm.png) |

## 8. Actual cost and tear down

| S59 Cost Explorer: actual spend during testing | S60 Tear-down workflow | S61 Nothing left |
|---|---|---|
| ![](teardown/S59-cost-explorer.png) | ![](teardown/S60-teardown-green.png) | ![](teardown/S61-nothing-left.png) |
