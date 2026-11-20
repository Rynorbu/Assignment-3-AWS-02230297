# AWS Pricing Calculator: exact inputs

Use these entries so the calculator matches `docs/cost-report.md` and `scripts/cost-model.mjs`.

**Before you start:**
- Open <https://calculator.aws/#/estimate>.
- For **every** service, set the Region to **Asia Pacific (Singapore)**. The one exception is WAF and CloudFront, which are *global*.

**Build three estimates:**
1. **Exam platform – Normal month (A3)**
2. **Exam platform – Exam month (A3)**
3. **Exam platform – A2 design in Singapore (baseline)**. Make it by duplicating estimate 1, then changing the items listed in the last section of this file. This estimate is what proves the optimisation savings.

For each estimate:
1. Click **Share** and copy the link into `README.md` and `docs/cost-report.md`.
2. Click **Export → CSV** and **Export → PDF**, and save both into `evidence/calculator/`.
3. Take a screenshot showing the date.

## Estimate 1: Normal month

| # | Service in the calculator | Settings |
|---|---|---|
| 1 | **Amazon RDS for PostgreSQL** | Instances: 1 · `db.t4g.medium` · Deployment **Multi-AZ** · Pricing **Reserved, 1 year, Partial Upfront** · Storage **General Purpose SSD (gp3) 20 GB** · Backup storage: additional 40 GB · RDS Proxy: **on** (2 vCPU) |
| 2 | **Amazon VPC** | Interface endpoints: **2 endpoints (SQS, Secrets Manager) × 2 ENIs (AZs)** · data processed 2 GB/month · NAT gateways: **0** |
| 3 | **AWS Lambda** | Architecture **Arm** · Requests 15,120,000 (14.4 M × 1.05 for workers) · Duration 80 ms · Memory 512 MB · Ephemeral storage 512 MB · *Free tier: untick* (if the option is shown) |
| 4 | **Amazon API Gateway** | HTTP API · Requests 14.4 million/month · Average size ≤ 512 KB |
| 5 | **Amazon CloudFront** | Data transfer out, **India** 60 GB + **Asia Pacific** 62 GB · HTTPS requests 15,400,000 |
| 6 | **AWS WAF** | Web ACLs 1 · Rules 3 · Requests 15.4 million |
| 7 | **Amazon S3** | S3 Standard 120 GB · Standard-IA 600 GB · Glacier Instant Retrieval 740 GB · **Glacier Deep Archive 5,760 GB** · PUT requests 12,000 · GET requests 36,000 · Lifecycle transitions: 24,000 (to IA/GIR) + 12,000 (to Deep Archive) · Data transfer out to internet: **120 GB** |
| 8 | **Data Transfer** | Intra-Region (inter-AZ) 86 GB |
| 9 | **Amazon CloudWatch** | Logs ingested 11 GB · Logs stored 11 GB · Standard alarms 14 · Dashboards 1 |
| 10 | **AWS Key Management Service** | Customer managed keys 1 · Symmetric requests 100,000 |
| 11 | **AWS Secrets Manager** | Secrets 1 · API calls 50,000 |
| 12 | **Amazon SQS** | Standard queue requests 2 million |
| 13 | **Amazon Simple Email Service** | Email messages 36,000 (sent from Lambda) |
| 14 | **Amazon Cognito** | Monthly active users 8,400 (Essentials/Lite tier: 10,000 free) |
| 15 | **Amazon Route 53** | Hosted zones 1 |
| 16 | **AWS Backup** | RDS snapshot warm storage 40 GB *(skip this item if you already added backup storage under RDS, so it is not counted twice)* |

## Estimate 2: Exam month (change these from estimate 1)

| # | Service | Change |
|---|---|---|
| 1 | RDS | Add a 2nd line: `db.t4g.medium` Multi-AZ **On-Demand** × 1 (the RI covers the other half of a `t4g.large`). If your calculator version does not do size flexibility, enter `db.t4g.large` Multi-AZ On-Demand and add a note. |
| 3 | Lambda | Requests 23,520,000 |
| 4 | API Gateway | 22.4 million |
| 5 | CloudFront | India 90 GB + Asia Pacific 97 GB · requests 23,970,000 |
| 6 | WAF | 23.97 million requests |
| 7 | S3 | PUT 4,000 · GET 12,000 · data transfer out 60 GB |
| 8 | Data Transfer | inter-AZ 134 GB |
| 9 | CloudWatch | Logs 17 GB |
| 10 | KMS | 150,000 requests |
| 12 | SQS | 2.4 million |
| 13 | SES | 50,000 |
| + | RDS CPU credits | Add $9.75 manually as a note: 130 vCPU-hours × $0.075 |

## Estimate 3: A2 design in Singapore (baseline for the savings)

Duplicate estimate 1, then make these changes:
- RDS → `db.m6g.large` Multi-AZ **On-Demand**
- VPC → **NAT gateways: 2**, 5 GB processed, interface endpoints: **1** (SQS only, × 2 AZ)
- CloudWatch → logs stored 33 GB (90-day retention)

**The savings to read off:**
- Estimate 3 total − Estimate 1 total ≈ **$279/month in a normal month**.
- Split that into O1 (NAT), O2 (instance size), O3 (RI) and O5 (logs) by changing **one item at a time** and writing down the total after each change. Screenshot each step. That gives you the "three optimisations with the saving of each" evidence.
- For O4, change S3 to **Standard 7,220 GB** and note the difference (≈ $153/month).

> Calculator totals can differ from `scripts/cost-model.mjs` by a few dollars: rounding, the free tiers it applies, and CloudFront regional splits. **The calculator figures are the official ones.** Copy them into `docs/cost-report.md` sections 2 and 7 if they differ.
