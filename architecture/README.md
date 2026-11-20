# Revised architecture (Assignment 3): cost-optimised, Singapore

**Region:** ap-southeast-1 (Singapore), across 2 Availability Zones.

**What changed from Assignment 2:** see [CHANGELOG.md](CHANGELOG.md). Every change is tied to a cost finding (`docs/cost-report.md`), a failure test (`infra/failure-tests/`) or the load test (`docs/load-test.md`).

**Diagram legend:**
- 🔴 **SPOF accepted**: a single point of failure kept on purpose, with the reason.
- 🟢 **SPOF removed**: a single point of failure the design eliminates.
- ✂️ **Removed for cost**: in Assignment 2, gone now.
- 🆕 **New in A3**

```mermaid
flowchart TB
  subgraph Users["Users: 8,000 students · 400 staff (Bhutan / region)"]
    STU["Student"]
    TUT["Tutor / Admin"]
  end

  subgraph Edge["Edge (global, many PoPs) 🟢 no SPOF"]
    R53["Route 53<br/>100% SLA DNS"]
    WAF["AWS WAF<br/>managed rules<br/>rate limit per student 🆕"]
    CF["CloudFront<br/>HTTPS · static cache"]
  end

  COG["Cognito user pool<br/>regional, multi-AZ 🟢<br/>8,400 MAU < 10k free"]
  WEB[("S3 frontend bucket<br/>private, OAC")]

  subgraph Region["AWS Region ap-southeast-1 (Singapore)  🔴 Region = accepted SPOF (see FT6)"]
    APIGW["API Gateway HTTP API<br/>JWT authorizer · throttling<br/>multi-AZ managed 🟢"]
    NOTIFYFN["λ notify / λ admin<br/>(outside VPC)"]
    SES["SES 🔴 accepted<br/>(emails only delayed)"]
    UPL[("S3 uploads · KMS · versioned<br/>Std → IA 30d → Glacier IR 180d<br/>→ Deep Archive 365d → delete 5y")]
    subgraph Async["SQS queues + DLQs 🟢 (durable, multi-AZ)"]
      QM["marking"]
      QU["uploads"]
      QN["notify"]
    end
    EB["EventBridge 1-min auto-submit"]

    subgraph VPC["VPC 10.20.0.0/16 · ✂️ NO NAT gateways (A2 had 2)"]
      subgraph AZA["AZ ap-southeast-1a"]
        subgraph APPA["Private app subnet"]
          LA["λ api · marking · upload<br/>arm64"]
        end
        subgraph DATAA["Private data subnet"]
          DBA[("RDS PostgreSQL PRIMARY<br/>t4g.medium → t4g.large in exam months 🆕")]
        end
      end
      subgraph AZB["AZ ap-southeast-1b"]
        subgraph APPB["Private app subnet"]
          LB["λ api · marking · upload<br/>arm64"]
        end
        subgraph DATAB["Private data subnet"]
          DBB[("RDS STANDBY (sync)<br/>🟢 DB primary SPOF removed")]
        end
      end
      PROXY["RDS Proxy (multi-AZ) 🆕 always on<br/>fixes load-test bottleneck"]
      VPCE["S3 gateway endpoint (free)<br/>SQS + Secrets Manager<br/>interface endpoints ×2 AZ"]
    end
  end

  subgraph Ops["Security · operations"]
    KMS["KMS CMK 🔴 accepted<br/>(regional, multi-AZ service)"]
    SM["Secrets Manager"]
    CW["CloudWatch: 30-day logs 🆕<br/>alarms · load-test dashboard 🆕"]
    BK["AWS Backup daily 35d + monthly 5y<br/>🆕 optional copy → ap-south-1"]
    FIS["FT3 fault: deny-all NACL 🆕<br/>(AWS FIS blocked on Free plan)"]
  end

  subgraph DR["ap-south-1 Mumbai (optional DR) 🆕"]
    DRV[("Backup vault copy")]
  end

  subgraph CICD["CI/CD"]
    GHA["GitHub Actions → OIDC → Terraform<br/>DB_INSTANCE_CLASS switch for exam months 🆕"]
  end

  STU & TUT --> R53 --> CF
  WAF -. protects .- CF
  CF --> WEB
  CF -- "/api/*" --> APIGW
  STU & TUT -. sign-in .-> COG
  APIGW -. JWT .- COG
  APIGW --> LA & LB
  APIGW --> NOTIFYFN
  LA & LB --> PROXY --> DBA
  DBA == "synchronous replication" ==> DBB
  LA & LB --> VPCE
  VPCE --> UPL & QM & QN
  STU -- "presigned POST (50 MB)" --> UPL
  UPL --> QU --> LA
  QM --> LB
  QN --> NOTIFYFN --> SES
  EB --> LA
  BK --> DBA
  BK -.-> DRV
  KMS -.- UPL & DBA & BK
  FIS -. fault .-> APPA
  GHA --> Region
```

> Export a PNG for the submission: paste the block into <https://mermaid.live>, choose *Actions → PNG*, and save it as `architecture/architecture-a3.png`. Or redraw it in draw.io, keeping the same labels and SPOF markers.

## Single points of failure

| # | Component | Status | How it is handled | Evidence |
|---|---|---|---|---|
| 1 | RDS primary instance / its AZ | 🟢 removed | Multi-AZ synchronous standby. Automatic failover in about 1–2 min. RDS Proxy keeps client connections open. | FT1 |
| 2 | NAT gateway (A2 had one per AZ) | ✂️ removed entirely | Lambdas reach S3 through the gateway endpoint and SQS through an interface endpoint. RDS Proxy reads the DB secret through the Secrets Manager interface endpoint. Each interface endpoint has one ENI per AZ. | cost O1 |
| 3 | Lambda subnet in one AZ | 🟢 removed (with runbook) | Lambdas run in both AZs. Lambda does not health-check subnets, so a partial AZ network fault becomes a partial error rate. The runbook sets `lambda_subnet_indexes=[1]`. | FT3 |
| 4 | DB connection limit at peak (capacity SPOF) | 🟢 removed | RDS Proxy pools connections, and the instance is `t4g.large` in exam months. Free-plan alternative: `API_RESERVED_CONCURRENCY`. | load test |
| 5 | Logical corruption (affects the primary and standby together) | 🟢 mitigated | PITR (RPO ≤ 5 min) plus a rename-swap runbook. | FT2 |
| 6 | Single uploads bucket | 🟢 mitigated | S3 stores data in at least 3 AZs. Versioning protects against deletes. Noncurrent versions are kept 30 days (finding: raise to 90 days). | FT4 |
| 7 | Marking/notify worker | 🟢 mitigated | SQS keeps messages for 4 days, failures go to a DLQ, a DLQ alarm fires, and the DLQ can be redriven. | FT5 |
| 8 | Region ap-southeast-1 | 🔴 accepted | A warm standby would add about $150–300/month. The optional cross-Region backup copy gives RPO 24 h and RTO 2–4 h. | FT6 |
| 9 | SES (single Region) | 🔴 accepted | Emails are not critical. The notify queue holds them until SES returns. | — |
| 10 | KMS key (single, regional) | 🔴 accepted | KMS is a multi-AZ managed service. Deletion takes a 7-day waiting period, and key rotation is on. | — |
| 11 | WAF / CloudFront config in us-east-1 control plane | 🔴 accepted | Only the *control plane* lives in us-east-1. Serving keeps working from the edge. | — |
| 12 | CI/CD (GitHub) | 🔴 accepted | Not in the request path. Terraform can be run from a laptop with the same state bucket. | — |

## How the design handles the exam peak (after the A3 fixes)

1. Two days before an exam month, CI applies `DB_INSTANCE_CLASS=db.t4g.large`. Multi-AZ resizes the standby first, then fails over, so the downtime is about 1 minute and happens out of hours.
2. 3,000 starts in 5 minutes is about 10 req/s; autosaves are about 100 req/s. CloudFront and WAF absorb the static load.
3. API Gateway's throttles (burst 5,000) are far above that. Lambda scales out (with a quota of at least 1,000), and RDS Proxy multiplexes hundreds of Lambda connections onto a few dozen database connections.
4. Marking and emails go through SQS with capped consumer concurrency, so the database is never flooded.
5. After the exam month, the instance goes back to `t4g.medium`, which the 1-year Reserved Instance covers.
