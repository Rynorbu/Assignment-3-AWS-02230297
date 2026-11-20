# Assignment 3: to-do list (updated 2026-11-20)

✅ done · ⏳ in progress / next · ⬜ not started

**Your values (use these everywhere):**

| What | Value |
|---|---|
| GitHub repo | `Rynorbu/Assignment-3-AWS-02230297` |
| AWS account / Region | `363242104805` / `ap-southeast-1` (Singapore). WAF metrics are in `us-east-1`. |
| Stack name prefix | `exam-platform-a3-prod` |
| State bucket | `exam-platform-a3-tfstate-363242104805` |
| App URL | `https://d2tat6wr6b099o.cloudfront.net` |
| Tutor / Student / Admin | `02230297.cst+tutor@rub.edu.bt` / `02230297.cst+student@rub.edu.bt` / `02230297.cst+admin@rub.edu.bt`, password `Passw0rd1234` |
| Load-test accounts | `loadtest001…200@example.com`, password `LoadTest#2026pass` |
| Exam ID | `64bd5ba8-04f0-4abc-a634-7891448ae697` |
| Account plan | **AWS Free plan.** RDS Proxy, AWS FIS and DB sizes above `db.t4g.micro` are blocked, so we use **Path B**. |

**Screenshot rules:**
- Show the **Region** in the top right and the **date/time**: either the taskbar clock or the console time range.
- Use **Win + Shift + S → Window**.
- Save each screenshot with the **exact file name** below. `evidence/README.md` already shows every one of these names.

---

## Phase 0: Preparation ✅

| Step | Status | Evidence |
|---|---|---|
| A2 stack checked, account and Region set | ✅ | `aws-account/aws-account.png`, `aws-account/set-region.png` |
| Lambda quota = 1,000 in Singapore | ✅ | `quotas/lambda-quota.png` |
| SES production access request | ⬜ optional | `quotas/ses-request.png` |
| $30 safety budget | ⬜ optional (recommended) | `quotas/budget.png` |

## Phase 1: A3 repository ✅

Pushed to `Rynorbu/Assignment-3-AWS-02230297`.

## Phase 2: Pricing Calculator ⬜ (you chose to do this last; see Phase 10)

## Phase 3: Latency from Bhutan ✅

- `latency/latency-terminal.png` ✅, `latency/cloudping.png` ✅, `latency/latency-20261120-1418.csv` ✅
- Result (already written into `docs/cost-report.md` §5): **Singapore 145 ms** median, Mumbai 165 ms, Hyderabad 155 ms, N. Virginia 364 ms.

## Phase 4: Architecture diagram PNG ⬜

- [ ] Copy the ` ```mermaid ` block from `architecture/README.md` into <https://mermaid.live>, then **Actions → PNG**.
- [ ] Save it as **`architecture/architecture-a3.png`**, and a copy as **`evidence/architecture/architecture-a3.png`**.
- [ ] Under the title of `architecture/README.md`, add the line `![Revised architecture](architecture-a3.png)`.

## Phase 5: Deploy to Singapore ✅

All taken: `deploy/bootstrap-outputs.png`, `github-variables.png`, `pipeline-green.png`, `terraform-apply-log.png`, `terraform-init.png`, `terraform-output-1.png`, `vpc-no-nat.png`, `vpc-endpoints.png`, `subnets-2az.png`, `rds-multi-az.png`, `lambda-arm64.png`, `backup-plan.png` (+ daily/monthly), `s3-lifecycle.png`, `dashboard.png`, `users-created.png`, `tutor-exam-created.png`, `app-autosave.png`, `autosave-after-refresh.png`, `notify/subscribe.png`, `notify/email_sns.png`.

**Deployment findings, already in `architecture/CHANGELOG.md`:**
- **C13:** name clash with an old `exam-platform-prod` stack, so A3 was renamed `exam-platform-a3-prod`.
- **C9:** AWS FIS is blocked on the Free plan, so FT3 uses a deny-all network ACL instead.

## Phase 6: Load test BEFORE ✅ (one screenshot left)

- ✅ Run on 2026-11-20 at 11:30–11:41 UTC: **68.48 % success, 11,750 × HTTP 403, p95 10.2 s.** Results in `load-test/before-2026-11-20T11-30-13-758Z.json/.csv`.
- ✅ Metrics exported to `cloudwatch/before-metrics.json`.
- ✅ Screenshots: `load-test/before-terminal.png`, `before-dashboard.png`, `before-rds-connections.png`, `before-api-errors.png`, `before-waf-sampled.png`
- ✅ Analysis written in `docs/load-test.md` §2.
  - **B1, proven:** the WAF per-IP rate limit blocked 11,762 requests.
  - **B2, building up:** the database reached 67 connections and 57 MB of free memory.
- [ ] ⏳ **`load-test/before-waf-blocked.png`**: the WAF `BlockedRequests` graph. Easiest way, as a terminal table:
  ```bash
  aws cloudwatch get-metric-statistics --region us-east-1 --namespace AWS/WAFV2 --metric-name BlockedRequests --dimensions Name=WebACL,Value=exam-platform-a3-prod-waf Name=Rule,Value=ratelimit --start-time 2026-11-20T11:29:00Z --end-time 2026-11-20T11:43:00Z --period 60 --statistics Sum --query "sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]" --output table
  ```
  Or in the console: **N. Virginia → CloudWatch → All metrics → WAFV2 → Rule, WebACL → `ratelimit` / `BlockedRequests` (CloudWatch uses the rule's metric name `ratelimit`, not `RateLimitPerIp`)**, statistic **Sum**, period **1 min**, time range **11:29–11:43 UTC**.

## Phase 7: Fix and load test AFTER ✅ (screenshots left)

> **Result (12:55:48–13:06:19 UTC):** **100 % of 47,273 requests OK, p95 885 ms, 0 WAF blocks, 0 throttles, DB connections 28 (was 67).** Already written into `docs/load-test.md` §4, `README.md` and `docs/cost-report.md` §6. Metrics are in `cloudwatch/after-metrics.json`.
> **For the AFTER screenshots, use the window `2026-11-20 12:54:00` → `13:08:00` UTC.**

- ✅ **The fix in code:** a WAF per-student rate limit (`RateLimitPerStudent`, 1,000 requests per 5 min per token), and the per-IP backstop raised to 150,000 (`infra/edge.tf`). The WAF part is already deployed.
- ✅ `db.t4g.small` was refused with `FreeTierRestrictionError`: `load-test/free-plan-error.png` ✅, `load-test/fix-variables.png` ✅
- [x] **7.1 DONE** (concurrency = 40 confirmed). In GitHub variables, check that `DB_INSTANCE_CLASS=db.t4g.micro`, `API_RESERVED_CONCURRENCY=40` and `DB_USE_RDS_PROXY=false` are set. Then wait for the **Deploy** run from commit *"Free plan: keep db.t4g.micro, cap API concurrency at 40"* to go **green**. If it didn't run, use **Actions → Deploy → Run workflow**.
  - Check it applied (Git Bash). It must print `40`:
    ```bash
    aws lambda get-function-concurrency --region ap-southeast-1 --function-name exam-platform-a3-prod-api
    ```
    If it prints nothing, the variable or the deploy didn't apply yet.
  - 📸 **`load-test/fix-waf-rules.png`**: **N. Virginia → WAF & Shield → Web ACLs → Global (CloudFront) → `exam-platform-a3-prod-waf` → Rules** tab. Both `RateLimitPerIp` and `RateLimitPerStudent` must be visible.
  - 📸 **`load-test/fix-api-concurrency.png`**: **Singapore → Lambda → `exam-platform-a3-prod-api` → Configuration → Concurrency**, showing reserved concurrency **40**.
- [x] **7.2 DONE.** Wait **10 minutes after the deploy**, then:
  ```bash
  cd "/c/Users/HP/OneDrive/Desktop/Assigment-3-AWS"
  date -u +%Y-%m-%dT%H:%M:%SZ
  node scripts/peak-load-test.mjs --label after --exam-id 64bd5ba8-04f0-4abc-a634-7891448ae697 --domain example.com --accounts 200 --password 'LoadTest#2026pass'
  date -u +%Y-%m-%dT%H:%M:%SZ
  ```
  - Write down both `date -u` times.
  - 📸 **`load-test/after-terminal.png`**: the final summary JSON
- [ ] **7.3** Wait 3 minutes. On the dashboard, set **Custom → Absolute → UTC timezone** to START − 1 min through END + 2 min, then take:
  - 📸 **`load-test/after-dashboard.png`**: the whole dashboard (zoom out with Ctrl + −)
  - 📸 **`load-test/after-rds-connections.png`**: *RDS connections / memory / write latency* → ⋮ → **Enlarge**
  - 📸 **`load-test/after-api-errors.png`**: *API requests / errors* → ⋮ → **Enlarge**
  - 📸 **`load-test/after-waf.png`**: the same WAF command as in Phase 6 with the AFTER times. It should show about 0 blocked.
- [x] **7.4 DONE.** Send Claude the terminal summary and the two times. Claude exports the metrics and fills in `docs/load-test.md` §4 and the verdict.

## Phase 8: Failure tests ✅ ALL DONE: FT1 RTO 66 s · FT2 RTO about 22 min, RPO 154 s · FT3 120 s, self-healed · FT4 73 s, RPO 0 · FT5 drained in 96 s, 0 lost (recorded in `infra/failure-tests/README.md`)

Run these once in Git Bash before starting:

```bash
cd "/c/Users/HP/OneDrive/Desktop/Assigment-3-AWS"
export FT_STUDENT_EMAIL=02230297.cst+student@rub.edu.bt FT_PASSWORD='Passw0rd1234' FT_EXAM_ID=64bd5ba8-04f0-4abc-a634-7891448ae697
```

> The student's attempt from Phase 5 may have expired (120 minutes). If FT1 says it cannot save the marker:
> 1. Sign in as the tutor and create a **new** exam (duration 120, *Load sample questions*, Publish).
> 2. Copy its ID from the address bar (`#/exams/<id>`) into `FT_EXAM_ID`.
> 3. Do **not** submit the student's exam.

| Test | Command | Screenshots (folder `evidence/failure-tests/`) |
|---|---|---|
| **FT1** AZ loss of the DB primary | `bash scripts/failure-tests/ft1-az-db-failover.sh` | `ft1-before-az.png` (RDS → Configuration, take it **before** the run) · `ft1-terminal.png` (`downtime_s=…`, `marker FOUND`) · `ft1-after-az.png` · `ft1-rds-events.png` (RDS → Logs & events) · `ft1-sns-email.png` |
| **FT2** point-in-time restore | `bash scripts/failure-tests/ft2-pitr-restore.sh` (15–30 min) | `ft2-rpo.png` (`RPO exposure = …s`) · `ft2-restored-instance.png` (take it **before** you press Enter) · `ft2-rto.png` (`Restore available after …s`) |
| **FT3** network loss in one AZ (deny-all NACL) | `bash scripts/failure-tests/ft3-az-network-loss.sh` (7 min) | `ft3-nacl-fault.png` (VPC → Subnets → `…-app-ap-southeast-1a` → **Network ACL** tab, when the script prompts) · `ft3-terminal.png` · `ft3-dashboard.png` (5xx/errors during the fault) |
| **FT4** deleted assignment file | `bash scripts/failure-tests/ft4-s3-delete-recover.sh` | `ft4-s3-versions.png` (when the script pauses: S3 → uploads bucket → `assignments/ft4-test/` → **Show versions**) · `ft4-terminal.png` |
| **FT5** marking worker outage | `bash scripts/failure-tests/ft5-marking-worker-outage.sh` (about 5 min) | `ft5-concurrency-zero.png` (Lambda `…-marking` → Concurrency = 0, **during** the 3-min outage) · `ft5-terminal.png` · `ft5-queue-depth.png` · `ft5-dlq-alarm.png` (if messages reached the DLQ) |

- After each test, send Claude the terminal output. Claude fills in the **Measured** and **Pass?** cells in `infra/failure-tests/README.md`.

## Phase 9: Actual cost and tear down ⏳ ← you are here

- [x] ~~Cost Explorer~~: no Billing access on the class account. Skipped; the test cost is estimated in `docs/cost-report.md` §8 instead.
- [ ] Commit the evidence:
  ```bash
  git add -A && git commit -m "A3 evidence [skip ci]" && git push
  ```
- [ ] **Actions → Tear down → Run workflow → type `DESTROY`**, then wait about 20 min.
  - 📸 **`teardown/teardown-green.png`**
- [ ] In Singapore, check that nothing named `exam-platform-a3-prod` is left in RDS (including any `…-ft2-restore`), Lambda or VPC → Endpoints.
  - 📸 **`teardown/nothing-left.png`**
- [ ] Keep the bootstrap (state bucket + role) until the assignment is marked. It costs $0.

## Phase 10: Pricing Calculator and finish ⬜ (no AWS needed)

Follow `docs/calculator-inputs.md`. Region **Asia Pacific (Singapore)**; WAF has **4 rules**.

| Estimate / step | Screenshot (folder `evidence/calculator/`) | Export |
|---|---|---|
| Normal month | `normal-month-summary.png` | `normal-month.csv`, `normal-month.pdf` |
| Exam month | `exam-month-summary.png` | `exam-month.csv`, `exam-month.pdf` |
| A2 baseline (2 NAT, `db.m6g.large` On-Demand, 90-day logs) | `a2-baseline-summary.png` | `a2-baseline.csv`, `a2-baseline.pdf` |
| O1 NAT 2 → 0 (+ Secrets Manager endpoint) | `O1-remove-nat.png` | — |
| O2 `m6g.large` → `t4g.medium` | `O2-right-size.png` | — |
| O3 On-Demand → 1-yr Reserved, partial upfront | `O3-reserved.png` | — |
| O5 logs 33 GB → 11 GB | `O5-logs.png` | — |
| O4 S3 all Standard (to show the lifecycle saving) | `O4-s3-standard.png` | — |

- [ ] Paste the 3 **share links** into `README.md` (*Links*) and the top of `docs/cost-report.md`.
- [ ] Send Claude the 3 totals. Claude updates §2, §6 and §7 and the README if they differ from the model.
- [ ] Search the repo for `☐` (VS Code: **Ctrl + Shift + F**). Every one must be filled or explained.
- [ ] Final push:
  ```bash
  git add -A && git commit -m "Assignment 3 final [skip ci]" && git push
  ```
  Then open `evidence/README.md` on GitHub and check that every image shows.

## Rubric check (10 marks)

| Criterion | Evidence | Status |
|---|---|---|
| Architecture (2) | diagram PNG + SPOF table + change log C1–C14 (with real findings: names, FIS, WAF, Free plan) | ⏳ PNG missing |
| Documentation (2) | `docs/cost-report.md`: costs, hidden costs, 5 comparisons, **measured** latency, verdict | ⏳ needs calculator totals |
| Costed estimate (2) | 3 calculator estimates + O1–O5 screenshots + exports | ⬜ |
| Failure tests (2) | FT1–FT5 measured + FT6 tabletop | ⬜ |
| Load test (2) | before ✅ · proven with CloudWatch + WAF ✅ · fix ✅ · re-test ✅ (100 %) · B3/B4 reasoned ✅ | ✅ (screenshots left) |
