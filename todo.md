# Assignment 3: complete step-by-step plan (screenshots instead of a video)

Your tutor agreed that **screenshots replace the video**. Every screenshot below has:
- an **ID** (S01, S02, …),
- an **exact file name**,
- the **folder** it goes in.

`evidence/README.md` already embeds every file name. When you save a screenshot with the right name in the right folder, it appears in the report automatically.

**Screenshot rules (markers check these):**
1. Show the **Region selector (Asia Pacific (Singapore))** in every AWS console screenshot.
2. Show the **date and time**: the Windows clock in the taskbar, or the console time range.
3. Use full-window screenshots (`Win + Shift + S` → *Window*), not tiny crops. Zoom into a widget only when the ID asks for it.
4. Never write an expected value into a "Measured" cell. Only numbers you saw on screen.

---

## Do I need to deploy Terraform again and set GitHub variables? **Yes.**

| Question | Answer | Why |
|---|---|---|
| Deploy again? | **Yes**, in **Singapore** | Assignment 2 ran in us-east-1 and was torn down. The A3 rubric needs **measured** failure tests and a load test **proven with CloudWatch**, and both need a running stack. |
| New GitHub repo? | **Yes**, e.g. `DSO303-Assignment-03` | The brief says "submit in your own repository". Keep A2 untouched. |
| GitHub variables again? | **Yes** | Variables belong to a repo, so the new repo starts empty. |
| Bootstrap again? | **Yes**, with a different project name | The A2 deploy role only trusts the **A2 repo**. Bootstrapping with `project=exam-platform-a3` creates a new state bucket and role, with no name clash with A2. |

---

## Phase 0: Preparation (day 1, about 40 min). Start early: some approvals take days.

- [ ] **0.1 Check the A2 stack is really gone.** In the console, Region **N. Virginia**, check that nothing named `exam-platform-a3-prod` remains in RDS, Lambda or IAM → Roles.
  - The A3 stack reuses the same resource names, and IAM role names are global, so leftovers would clash.
  - If something remains, run the A2 repo's **Tear down** workflow first.
- [ ] **0.2 Check your tools** (Git Bash):
  ```bash
  aws --version && terraform -version && node -v && git --version
  aws sts get-caller-identity        # must be the account you will use
  aws configure set region ap-southeast-1
  ```
- [ ] **0.3 Request the Lambda concurrency quota.**
  1. Console → **Service Quotas** → AWS services → **AWS Lambda** → *Concurrent executions*, Region **Singapore**.
  2. If it is under 1,000, click *Request increase at account level* and ask for **1,000**.
  - 📸 **S01** `evidence/quotas/S01-lambda-quota.png`: the quota value, or the open request
- [ ] **0.4 (Optional, improves bottleneck B3) Request SES production access.** SES → *Account dashboard* → *Request production access*.
  - 📸 **S02** `evidence/quotas/S02-ses-request.png`
- [ ] **0.5 Set a safety budget:** Billing → **Budgets** → *Create* → Monthly cost budget **$30**, with an email alert.
  - 📸 **S03** `evidence/quotas/S03-budget.png`
- [ ] **0.6 Decide your path.**
  - In Singapore, try RDS → **Proxies → Create proxy** (just open the page).
  - If your plan blocks it (the Free plan does), use **Path B**. Otherwise use **Path A**.

  | | Path A (paid account) | Path B (Free plan) |
  |---|---|---|
  | Load-test fix | RDS Proxy + `db.t4g.large` | `API_RESERVED_CONCURRENCY=60` + the largest instance allowed (`db.t4g.small` or `medium`) |

## Phase 1: Create the A3 repository (about 15 min)

- [ ] **1.1** On GitHub, create an **empty** repo `DSO303-Assignment-03`: no README, no .gitignore.
- [ ] **1.2** In Git Bash:
  ```bash
  cd "/c/Users/HP/OneDrive/Desktop/Assigment-3-AWS"
  git init -b main
  git add .
  git commit -m "Assignment 3: starting point from A2 + cost/resilience work [skip ci]"
  git remote add origin https://github.com/<your-user>/DSO303-Assignment-03.git
  git push -u origin main
  ```
  `[skip ci]` stops the deploy from running before the variables exist.

## Phase 2: Pricing Calculator. **No AWS deployment needed** (about 1.5 h) → rubric "costed estimate" (2 marks)

Follow `docs/calculator-inputs.md` line by line. **Region = Asia Pacific (Singapore)** for every service.

- [ ] **2.1 Estimate 1, normal month.** Add all services, then **Save and share** → copy the link.
  - 📸 **S04** `evidence/calculator/S04-normal-month-summary.png`: the *My Estimate* page with the monthly total and the list of services
  - Also save **Export → CSV** as `evidence/calculator/normal-month.csv` and **Export → PDF** as `evidence/calculator/normal-month.pdf`
- [ ] **2.2 Estimate 2, exam month.**
  - 📸 **S05** `evidence/calculator/S05-exam-month-summary.png`, plus `exam-month.csv` and `exam-month.pdf`
- [ ] **2.3 Estimate 3, A2 design in Singapore (baseline):** 2 NAT gateways, `db.m6g.large` On-Demand, 90-day logs.
  - 📸 **S06** `evidence/calculator/S06-a2-baseline-summary.png`, plus `a2-baseline.csv` and `a2-baseline.pdf`
- [ ] **2.4 Optimisations, one change at a time.** Duplicate estimate 3, apply each change, and screenshot the new total *after each step*:

  | ID | File | Change applied |
  |---|---|---|
  | S07 | `evidence/calculator/S07-O1-remove-nat.png` | NAT gateways 2 → 0, add the Secrets Manager endpoint |
  | S08 | `evidence/calculator/S08-O2-right-size.png` | `db.m6g.large` → `db.t4g.medium` |
  | S09 | `evidence/calculator/S09-O3-reserved.png` | On-Demand → 1-yr Reserved, partial upfront |
  | S10 | `evidence/calculator/S10-O5-logs.png` | logs stored 33 GB → 11 GB |
  | S11 | `evidence/calculator/S11-O4-s3-standard.png` | (separately) S3 all in Standard 7,220 GB, to show what lifecycle saves |

  Each saving = previous total − new total. Write them into `docs/cost-report.md` §7.
- [ ] **2.5** Copy the calculator totals into `docs/cost-report.md` §2 and §6, and into the `README.md` Summary. If they differ from my model by a few dollars, **the calculator wins**.
- [ ] **2.6** Paste the 3 share links into `README.md` (*Links*) and the top of `docs/cost-report.md`. Add the date you checked.

## Phase 3: Latency from Bhutan (about 15 min) → rubric "Region comparison"

- [ ] **3.1** In Git Bash: `bash scripts/measure-latency.sh`. It runs 20 samples per Region and saves a CSV in `evidence/latency/`.
  - 📸 **S12** `evidence/latency/S12-latency-terminal.png`: the printed min/median/p90 table
- [ ] **3.2** Open <https://www.cloudping.info> and click **HTTP Ping** twice.
  - 📸 **S13** `evidence/latency/S13-cloudping.png`, with Singapore, Mumbai and N. Virginia visible
- [ ] **3.3** Put the medians in `docs/cost-report.md` §5 and note your town and ISP (e.g. "Thimphu, Bhutan Telecom fibre").

## Phase 4: Architecture diagram (about 20 min) → rubric "architecture" (2 marks)

- [ ] **4.1** Copy the ` ```mermaid ` block from `architecture/README.md` into <https://mermaid.live>, then **Actions → PNG**. Save it as:
  - `architecture/architecture-a3.png`
  - 📸 **S14** a copy at `evidence/architecture/S14-architecture-a3.png`
- [ ] **4.2** Under the title of `architecture/README.md`, add: `![Revised architecture](architecture-a3.png)`
- [ ] *(Optional, looks better)* Redraw it in draw.io with AWS icons. **Keep the 🔴 / 🟢 / ✂️ / 🆕 markers.** "Failure points marked" is in the rubric.

## Phase 5: Bootstrap and deploy to Singapore in the BASELINE configuration (about 1 h, mostly waiting)

- [ ] **5.1 Bootstrap** (state bucket + GitHub OIDC role for the **new** repo):
  ```bash
  cd infra/bootstrap
  terraform init
  terraform apply -var="region=ap-southeast-1" -var="project=exam-platform-a3" \
                  -var="github_repo=<your-user>/DSO303-Assignment-03" -var="create_oidc_provider=false"
  cd ../..
  ```
  - Use `create_oidc_provider=false` because A2 already created the GitHub OIDC provider in this account. If you get *"provider not found"*, run the command again without that option.
  - Write down the outputs `state_bucket` and `deploy_role_arn`.
  - 📸 **S15** `evidence/deploy/S15-bootstrap-outputs.png`
- [ ] **5.2 GitHub variables:** repo → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**:

  | Name | Value |
  |---|---|
  | `AWS_REGION` | `ap-southeast-1` |
  | `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` from 5.1 |
  | `TF_STATE_BUCKET` | `state_bucket` from 5.1 |
  | `SES_SENDER_EMAIL` | your email |
  | `SES_TEST_RECIPIENTS` | `["you+student@gmail.com","you+tutor@gmail.com"]` (JSON list) |
  | `ALARM_EMAIL` | your email |
  | `DB_INSTANCE_CLASS` | `db.t4g.micro` ← **baseline for the "before" load test** |
  | `DB_USE_RDS_PROXY` | `false` ← baseline |
  | `DB_BACKUP_RETENTION_DAYS` | `1` (Free plan) or leave out (7) |

  Do **not** set `TF_STATE_REGION` (the new bucket is in Singapore).
  - 📸 **S16** `evidence/deploy/S16-github-variables.png`
- [ ] **5.3 Deploy:** Actions → **Deploy** → *Run workflow* (or push any commit without `[skip ci]`). It takes about 25 min.
  - 📸 **S17** `evidence/deploy/S17-pipeline-green.png`: all steps green
  - 📸 **S18** `evidence/deploy/S18-terraform-apply-log.png`: the end of the apply step showing `Apply complete!` and the outputs (region `ap-southeast-1`)
- [ ] **5.4** Confirm the emails: the SES verification links and the **SNS subscription** link.
- [ ] **5.5 Connect your laptop to the state** (needed by every script):
  ```bash
  cd backend && npm ci --omit=dev && cd ../infra
  terraform init -backend-config="bucket=<state_bucket>" -backend-config="region=ap-southeast-1"
  terraform output
  cd ..
  ```
  - 📸 **S19** `evidence/deploy/S19-terraform-outputs.png`
- [ ] **5.6 Prove that the design was built as documented.** Console, Region Singapore:

  | ID | File | Where in the console | Must show |
  |---|---|---|---|
  | S20 | `evidence/deploy/S20-vpc-no-nat.png` | VPC → **NAT gateways** | *No NAT gateways* (optimisation O1) |
  | S21 | `evidence/deploy/S21-vpc-endpoints.png` | VPC → **Endpoints** | S3 (Gateway), SQS + Secrets Manager (Interface) |
  | S22 | `evidence/deploy/S22-subnets-2az.png` | VPC → **Subnets**, filter `exam-platform` | 6 subnets in `ap-southeast-1a` and `1b` |
  | S23 | `evidence/deploy/S23-rds-multi-az.png` | RDS → database → **Configuration** | Multi-AZ **Yes**, class, primary AZ + secondary AZ |
  | S24 | `evidence/deploy/S24-lambda-arm64.png` | Lambda → Functions | functions listed with **arm64** |
  | S25 | `evidence/deploy/S25-backup-plan.png` | AWS Backup → Backup plans → plan | daily 35 d + monthly 1,825 d rules |
  | S26 | `evidence/deploy/S26-s3-lifecycle.png` | S3 → uploads bucket → **Management** | lifecycle rule (IA → Glacier IR → Deep Archive → expire) |
  | S27 | `evidence/deploy/S27-dashboard.png` | CloudWatch → Dashboards → `exam-platform-a3-prod` | the dashboard with the new A3 rows |
- [ ] **5.7 Users and test exam:**
  ```bash
  bash scripts/seed-users.sh admin@<you>.com tutor@<you>.com student@<you>.com 'Passw0rd1234'
  bash scripts/seed-load-users.sh 200 <you>.com 'LoadTest#2026pass'
  ```
  1. Open the app URL and sign in as the **tutor**.
  2. Create an exam with **duration 120 minutes**, open now.
  3. Note the **exam id**: browser **F12 → Network**, click the exam, look at the `/api/exams/<id>` call.
  4. Sign in as the **student**, start the exam and type an answer. Wait for "Saved hh:mm:ss".
  - 📸 **S28** `evidence/deploy/S28-app-autosave.png`: the app running from Singapore with the autosave tick

## Phase 6: Load test BEFORE, to find and prove the bottleneck (about 30 min) → rubric "load test" (2 marks)

- [ ] **6.1** Write down the **start time in UTC** (`date -u`). Then run:
  ```bash
  node scripts/peak-load-test.mjs --label before --exam-id <id> --domain <you>.com --accounts 200 --password 'LoadTest#2026pass'
  ```
  It runs for about 10 min and prints a line every 10 s. If your laptop or Wi-Fi cannot keep up, use `--students 1500 --autosave 15`: same requests per second, half the sockets. Write down that you did this.
  - 📸 **S29** `evidence/load-test/S29-before-terminal.png`: the last screen, showing the summary JSON (success %, p95, statuses)
- [ ] **6.2 Prove it with CloudWatch.** Set the dashboard time range to the test window (*Custom → Absolute*).
  - 📸 **S30** `evidence/load-test/S30-before-dashboard.png`: the whole dashboard
  - 📸 **S31** `evidence/load-test/S31-before-rds-connections.png`: enlarge the *RDS connections / memory / write latency* widget (click ⋮ → *View in metrics*)
  - 📸 **S32** `evidence/load-test/S32-before-api-errors.png`: enlarge *API requests / errors* and *API Lambda throttles / errors*
- [ ] **6.3 Prove the cause from the logs.** CloudWatch → **Logs Insights**, log group `/aws/lambda/exam-platform-a3-prod-api`, same time range:
  ```
  fields @timestamp, @message
  | filter @message like /too many|remaining connection slots|timeout|ECONNREFUSED|Connection terminated/
  | stats count() as errors by bin(1m)
  ```
  - 📸 **S33** `evidence/load-test/S33-before-logs-insights.png`
  - This is the strongest proof: it shows *why* the requests failed.
- [ ] **6.4** Export the metrics to JSON: `bash scripts/export-metrics.sh before <startUTC> <endUTC>`, then fill in the **before** columns of `docs/load-test.md`.
  - **If nothing broke:** re-run with `--ramp 60` (everyone starts within 1 minute) and use that run. Explain honestly that the 5-minute ramp alone did not reach the limit.

## Phase 7: Apply the fix and re-test (about 45 min)

- [ ] **7.1** Change the GitHub variables, then re-run **Deploy**. The database resize takes about 10–15 min.
  - **Path A:** `DB_USE_RDS_PROXY=true`, `DB_INSTANCE_CLASS=db.t4g.large`
  - **Path B:** `API_RESERVED_CONCURRENCY=60`, `DB_INSTANCE_CLASS=db.t4g.small` (or the largest your plan allows)
  - 📸 **S34** `evidence/load-test/S34-fix-variables.png`: the changed variables
  - 📸 **S35** `evidence/load-test/S35-fix-applied.png`: RDS *Configuration* showing the new class, and Path A: RDS → **Proxies** showing the proxy *Available*
- [ ] **7.2** Run the same command with `--label after`.
  - 📸 **S36** `evidence/load-test/S36-after-terminal.png`
- [ ] **7.3** Take the same CloudWatch views for the new time window:
  - 📸 **S37** `evidence/load-test/S37-after-dashboard.png`
  - 📸 **S38** `evidence/load-test/S38-after-rds-connections.png`
  - 📸 **S39** `evidence/load-test/S39-after-api-errors.png`
  - 📸 **S40** `evidence/load-test/S40-after-logs-insights.png` (the same query, about 0 errors)
- [ ] **7.4** Run `bash scripts/export-metrics.sh after <startUTC> <endUTC>`. Fill in the **after** columns and the conclusion in `docs/load-test.md`. Update the "Peak load" row in `README.md` and `docs/cost-report.md` §6.

## Phase 8: Failure tests, four or more, measured against RPO and RTO (about 1.5–2 h) → rubric "failure tests" (2 marks)

Run these in Git Bash from the repo root after setting the variables:
```bash
export FT_STUDENT_EMAIL=student@<you>.com FT_PASSWORD='Passw0rd1234' FT_EXAM_ID=<id>
```

- [ ] **8.1 FT1: AZ loss of the primary database.** First take 📸 **S41**, then run `bash scripts/failure-tests/ft1-az-db-failover.sh`.

  | ID | File | Must show |
  |---|---|---|
  | S41 | `evidence/failure-tests/S41-ft1-before-az.png` | RDS Configuration: primary AZ **before** |
  | S42 | `evidence/failure-tests/S42-ft1-terminal.png` | script output: `downtime_s=…` and `RPO check: marker FOUND` |
  | S43 | `evidence/failure-tests/S43-ft1-after-az.png` | RDS Configuration: primary now in the **other** AZ |
  | S44 | `evidence/failure-tests/S44-ft1-rds-events.png` | RDS → *Logs & events*: "Multi-AZ instance failover started / completed" with times |
  | S45 | `evidence/failure-tests/S45-ft1-sns-email.png` | the failover email in your inbox |

- [ ] **8.2 FT2: point-in-time restore (logical data loss).** Run `bash scripts/failure-tests/ft2-pitr-restore.sh` (15–30 min).

  | ID | File | Must show |
  |---|---|---|
  | S46 | `evidence/failure-tests/S46-ft2-rpo.png` | terminal line `RPO exposure = …s` |
  | S47 | `evidence/failure-tests/S47-ft2-restored-instance.png` | RDS → Databases: `…-ft2-restore` **Available** (take it *before* pressing Enter to delete) |
  | S48 | `evidence/failure-tests/S48-ft2-rto.png` | terminal line `Restore available after …s` |

- [ ] **8.3 FT3: network loss in one AZ (deny-all network ACL; FIS is blocked on this account).** Run `bash scripts/failure-tests/ft3-az-network-loss.sh` (7 min). It restores the network automatically, even if you press Ctrl+C.

  | ID | File | Must show |
  |---|---|---|
  | S49 | `evidence/failure-tests/S49-ft3-nacl-fault.png` | VPC → Subnets → the `…-app-ap-southeast-1a` subnet → **Network ACL** tab showing `exam-platform-a3-prod-ft3-deny-all` (take it while the fault runs; the script prompts you) |
  | S50 | `evidence/failure-tests/S50-ft3-terminal.png` | `failed_probes=… downtime_s=…` |
  | S51 | `evidence/failure-tests/S51-ft3-dashboard.png` | API 5xx / Lambda errors rising during the 5 min, then back to 0 |

  *(Optional, extra credit)* Apply the fix by setting `lambda_subnet_indexes = [1]` with `terraform apply` from your laptop. Run FT3 again and show far fewer failures.
  - 📸 **S52** `evidence/failure-tests/S52-ft3-fix-retest.png`

- [ ] **8.4 FT4: deleted assignment file.** Run `bash scripts/failure-tests/ft4-s3-delete-recover.sh`.

  | ID | File | Must show |
  |---|---|---|
  | S53 | `evidence/failure-tests/S53-ft4-terminal.png` | `Recovered after …s, checksum IDENTICAL` |
  | S54 | `evidence/failure-tests/S54-ft4-s3-versions.png` | S3 → bucket → `assignments/ft4-test/` with **Show versions** on: object versions and the delete marker. The script pauses and asks you to take it. |

- [ ] **8.5 FT5: marking worker outage.** Run `bash scripts/failure-tests/ft5-marking-worker-outage.sh` (about 5 min).

  | ID | File | Must show |
  |---|---|---|
  | S55 | `evidence/failure-tests/S55-ft5-concurrency-zero.png` | Lambda `exam-platform-a3-prod-marking` → Configuration → Concurrency = **0** (during the outage) |
  | S56 | `evidence/failure-tests/S56-ft5-terminal.png` | `Backlog drained … s after restore; DLQ depth=…` |
  | S57 | `evidence/failure-tests/S57-ft5-queue-depth.png` | dashboard *Queue depth* widget rising and then falling |
  | S58 | `evidence/failure-tests/S58-ft5-dlq-alarm.png` | DLQ alarm email or CloudWatch alarm *In alarm* (if messages reached the DLQ) |

- [ ] **8.6** Fill in every **Measured** and **Pass?** cell in `infra/failure-tests/README.md`. Then copy the RPO/RTO numbers into the verdict tables in `README.md` and `docs/cost-report.md` §6.

## Phase 9: Real cost check and tear down (same day, about 30 min)

- [ ] **9.1** Billing → **Cost Explorer**, *Daily*, grouped by **Service**, for the test days.
  - 📸 **S59** `evidence/teardown/S59-cost-explorer.png`
  - This shows what the tests actually cost. Mention it in the cost report: "actual spend during testing: $X".
- [ ] **9.2** Commit the evidence:
  ```bash
  git add -A && git commit -m "Assignment 3 evidence [skip ci]" && git push
  ```
- [ ] **9.3** Actions → **Tear down** → *Run workflow* → type `DESTROY`. Wait about 20 min.
  - 📸 **S60** `evidence/teardown/S60-teardown-green.png`
- [ ] **9.4** Check in Singapore that RDS (including any `-ft2-restore`), Lambda, the VPC endpoints and the CloudFront distribution are gone.
  - 📸 **S61** `evidence/teardown/S61-nothing-left.png`: RDS → Databases, empty
- [ ] **9.5** Keep the bootstrap (state bucket + role) until the assignment is marked. It costs nothing.

## Phase 10: Finish the documents (about 1 h)

- [ ] **10.1** Search the repo for `☐` (VS Code: `Ctrl + Shift + F`). Replace each one with your measured value, or remove the row and explain why.
- [ ] **10.2** In `README.md`, replace the video row with: *"Evidence: screenshots (agreed with the tutor in place of the video) – see `evidence/README.md`"*. This is already done for you; just check it.
- [ ] **10.3** Re-read the **feasibility verdict** in `README.md` and `docs/cost-report.md` §6 and make sure every ✅ cites a number you measured.
- [ ] **10.4** Final push: `git add -A && git commit -m "Assignment 3 final [skip ci]" && git push`. Open the repo on GitHub in a private window and check that every screenshot shows in `evidence/README.md`.

## Final check against the rubric (10 marks)

| Criterion | Full-marks requirement | Your evidence |
|---|---|---|
| Architecture (2) | Design reflects cost **and** test findings; failure points marked; clear change log | S14, `architecture/README.md` SPOF table, `CHANGELOG.md` (C2 → S20/S21, C5 → S29–S40, C8 → S49–S52) |
| Documentation (2) | Full cost breakdown with hidden costs; 4 strong comparisons; Region comparison; verdict backed by numbers | `docs/cost-report.md` §2–6, S12–S13, calculator totals |
| Costed estimate (2) | Both profiles in the calculator; 3+ optimisations with savings | S04–S11 + CSV/PDF exports + links |
| Failure tests (2) | 4 scenarios **measured** against RPO/RTO, with fixes | S41–S58, filled tables in `infra/failure-tests/README.md` |
| Load test (2) | Bottleneck **proven with CloudWatch**, fixed, **re-tested**; two more reasoned | S29–S40, `docs/load-test.md` (B2, B3) |
