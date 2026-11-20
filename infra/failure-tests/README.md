# Failure tests: scenarios, expected impact, measurements and fixes

Targets: **RPO ≤ 5 minutes**, **RTO ≤ 1 hour**, and the platform must **survive the loss of one AZ**.
Region: ap-southeast-1 (Singapore).

Every scenario has a script in [`scripts/failure-tests/`](../../scripts/failure-tests). Each script writes CSV and text evidence to `evidence/failure-tests/`.

- **Expected** is what the design predicts *before* the test.
- **Measured** is filled in from the script output after the run.
- Any measured value still showing `☐` has not been run yet.

| # | Scenario | Layer | How it is caused | RPO target | RTO target | Measured result |
|---|---|---|---|---|---|---|
| FT1 | AZ hosting the primary DB is lost | Database | `reboot-db-instance --force-failover` | 5 min | 1 h | ✅ RTO 66 s · RPO 0 |
| FT2 | Answers wiped by a bad change (logical corruption) | Database | Point-in-time restore | 5 min | 1 h | ✅ RTO about 22 min · RPO 154 s (worst reading 308 s ⚠️) |
| FT3 | Network of one AZ lost for the Lambda subnet | Compute / network | Deny-all network ACL on the AZ-a app subnet (the same fault FIS `aws:network:disrupt-connectivity` injects) | 5 min | 1 h | ✅ RTO 120 s (self-healed) · RPO 0 |
| FT4 | Submitted assignment file deleted | Storage | `aws s3 rm` on a versioned object | 5 min | 1 h | ✅ RTO 73 s · RPO 0 |
| FT5 | Marking worker down during submissions | Async | Lambda reserved concurrency = 0 | 5 min | 1 h | ✅ backlog drained 96 s after restore · 0 lost |
| FT6 | Whole Singapore Region unavailable (tabletop exercise, not executed) | Region | — | 5 min | 1 h | tabletop: not met for Region loss (accepted) |

Before you start:

1. Deploy the stack.
2. Create a test exam with a **120-minute** duration.
3. Seed one student. Then export the test variables:

```bash
export FT_STUDENT_EMAIL=student1@example.com FT_PASSWORD='YourPass123' FT_EXAM_ID=1
```

---

## FT1: Loss of the AZ that hosts the primary database

**Script:** `scripts/failure-tests/ft1-az-db-failover.sh`

**What happens:**
1. The script saves a marker answer.
2. It forces a Multi-AZ failover.
3. It calls `/api/health` every 2 seconds for 4 minutes.
4. It reads the marker back.

**Expected impact:**
- RDS promotes the synchronous standby in the other AZ. The DNS name stays the same and its TTL is 5 seconds.
- Without RDS Proxy, Lambdas holding a connection to the old primary fail until they reconnect. `db.js` retries once on a connection error.
- With RDS Proxy, the proxy keeps client connections open and only pauses them.
- The API returns 5xx or slow responses for about **60–120 s without the proxy**, or **under 30 s with it**.
- Students see "Offline – kept on this device, retrying". Answers stay in `localStorage` and are sent on the next 30-second autosave.

**Measured on 2026-11-20 at 13:33 UTC** (no RDS Proxy, `db.t4g.micro` Multi-AZ). Evidence: `evidence/failure-tests/ft1-20261120-193247-*`, plus screenshots `ft1-*.png`.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| RDS failover duration (events: *failover started* 13:33:07 → *completed* 13:33:46) | 60–120 s | **39 s** | — | — |
| Health-check impact window (first failed probe → stable again) | 60–120 s (no proxy) | **66 s** (`downtime_s=66`) | ≤ 3600 s | ✅ |
| Failed probes | 15–60 | **4 of 64**: t+7 s (timeout), t+15 s and t+19 s (HTTP 500), t+65 s (one late timeout while DNS settled). Healthy again from t+23 s. | — | — |
| Real user-visible outage | — | about **16 s**, plus one blip at t+65 s | — | — |
| Marker answer present after failover (RPO) | yes, so 0 s lost | **yes: `RPO check: marker FOUND`**, 0 answers lost | ≤ 300 s | ✅ |
| Primary AZ before → after | `ap-southeast-1a` → `1b` | **`ap-southeast-1a` → `ap-southeast-1b`** (standby now in 1a) | different AZ | ✅ |

**Result:**
- **Pass.** The platform survived the loss of the AZ holding the primary database.
- **RTO 66 s** against a 1-hour target (1.8 % of the budget). **RPO 0 s** against a 5-minute target.
- It recovered faster than expected even without RDS Proxy, because the API's `db.query` retries once on a broken connection.
- During those seconds, students would have seen "Offline – kept on this device" and their next 30-second autosave would have gone through.

**Likely fix and improvements:**
1. Turn on RDS Proxy (`DB_USE_RDS_PROXY=true`) on a paid plan. It cuts failover impact to seconds.
2. The client already retries autosave. Keep the retry in the API's `db.query`.
3. The RDS event subscription emails the team about the failover. Check that the email arrived.

---

## FT2: Logical data loss, recovered with point-in-time restore

**Script:** `scripts/failure-tests/ft2-pitr-restore.sh`

**What happens:**
1. The script reads `LatestRestorableTime`. Now minus that time is the real RPO exposure.
2. It restores a new instance from that point and times how long the restore takes.
3. It deletes the restored instance at the end.

**Expected impact:**
- Multi-AZ does **not** protect against this case, because the standby faithfully copies the bad change.
- RDS uploads transaction logs every 5 minutes, so the RPO exposure is **1–5 min**.
- Restoring a 20 GB gp3 instance takes about **10–25 min**.
- Switching the app to the restored instance takes about **5 min**: rename the identifiers so the endpoint name stays the same.

**Measured on 2026-11-20** (`db.t4g.micro`, 20 GB gp3). Evidence: `evidence/failure-tests/ft2-20261120-195054-*` (the full run), `ft2-*.png`, plus the RPO readings of two other runs.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| RPO exposure (now − LatestRestorableTime), main run | 60–300 s | **154 s** (13:50:56 vs 13:48:22) | ≤ 300 s | ✅ |
| RPO exposure, all 3 readings | — | 165 s · **154 s** · **308 s** | ≤ 300 s | ⚠️ 1 of 3 just over |
| Restore until `available` | 600–1500 s | **1,015 s (16.9 min)** (RDS event "Restored from … to 13:48:22" at 13:58:08) | — | — |
| Total RTO (restore + rename swap, about 5 min) | 15–35 min | **about 22 min** | ≤ 60 min | ✅ |

**Result:**
- **RTO passes with a wide margin:** about 22 min against 60 min.
- **RPO is at the edge.** RDS uploads transaction logs every 5 minutes, so `LatestRestorableTime` lags the present by anything from 0 to just over 300 s. One reading (308 s) was 8 s over the target, measured just before the next log upload.
- **What this means for students:**
  - **AZ failures** (FT1): RPO = 0, because of the synchronous standby.
  - **Logical corruption** (this test): the database alone can lose up to about 5 minutes.
  - The browser keeps every answer in `localStorage` and autosaves every 30 s. After a restore, the next autosave re-sends whatever the restore point missed, so for an exam in progress the effective loss is about 0.
- **Fix, if a strict ≤ 5 min database-only RPO is required:** use **Aurora PostgreSQL** (continuous backup to S3, restore point about 1 s behind), or a read replica / logical replication to a delayed copy. The cost of each is in `docs/cost-report.md` §4.2.

**Recovery runbook (the fix):**

```bash
aws rds modify-db-instance --db-instance-identifier exam-platform-a3-prod-db --new-db-instance-identifier exam-platform-a3-prod-db-broken --apply-immediately
aws rds modify-db-instance --db-instance-identifier exam-platform-a3-prod-db-ft2-restore --new-db-instance-identifier exam-platform-a3-prod-db --apply-immediately
aws rds modify-db-instance --db-instance-identifier exam-platform-a3-prod-db --multi-az --apply-immediately   # online
```

- Because the endpoint name is unchanged, there is no redeploy, and Terraform state still matches.
- **Residual risk:** answers autosaved between the bad change and the restore point must be re-sent. Clients keep them locally until the exam is submitted.

---

## FT3: Network loss in one AZ for the Lambda subnet (deny-all network ACL)

**Script:** `scripts/failure-tests/ft3-az-network-loss.sh`.

**Why not AWS FIS:** the first deploy with `ENABLE_FIS=true` failed with `SubscriptionRequiredException`, because the AWS Free plan account cannot use Fault Injection Service. The script injects the same fault by hand, and its `trap` puts the original network ACL back even if the script is interrupted. `infra/fis.tf` is kept, switched off, for a paid account.

**What happens:**
- The script moves the **app subnet in the first AZ** (`ap-southeast-1a`) to a new network ACL that denies all traffic, for 5 minutes, then restores the original ACL.
- The script calls `/api/health` every 2 seconds during the fault and for 2 minutes after it.

**Expected impact:**
- Lambda does **not** health-check its subnets. Execution environments in the broken subnet cannot reach RDS or the SQS endpoint, so their requests time out after 5 seconds (`connectionTimeout`).
- Expect a **partial failure**: roughly **20–50 % of API calls fail** for the 5 minutes. Environments in the healthy AZ keep working.
- Autosave retries every 30 seconds and keeps answers locally. The answers that actually reach the database are, in the worst case, 30–60 s behind the student's screen. Nothing is lost while the browser stays open.

**Measured on 2026-11-20, fault from 14:54:14 to 14:59:26 UTC** (subnet `subnet-0a50b7ce14cf23b0f`, ap-southeast-1a). Evidence: `evidence/failure-tests/ft3-20261120-205401-*`, `ft3-nacl-fault.png`, `ft3-terminal.png`, `ft3-dashboard.png`.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Failed probes during the 5-minute fault | 20–50 % (partial) | **16 of 57 (28 %).** All of them in the **first 120 s** (t+0 to t+112 s, every request timed out). Then **100 % success from t+120 s, while the deny-all ACL was still in place.** | — | — |
| User-visible outage (`downtime_s`) | — | **120 s** | ≤ 3600 s | ✅ |
| Recovery after the ACL was restored | < 30 s | **immediate**: 0 failed probes in the 2-minute recovery window | ≤ 3600 s | ✅ |
| Data lost (answers) | 0 (client retry) | **0**: autosave keeps answers locally and retries every 30 s, and 120 s is 4 retries | ≤ 300 s | ✅ |

**Finding (different from the prediction):**
- The impact was **total for 2 minutes, then healed itself**, instead of a constant partial error rate.
- At low traffic, the few warm API Lambda environments happened to sit in the broken AZ-a subnet, so every request hit them and timed out.
- After about 2 minutes, Lambda replaced those failing environments, and new ones were placed in the healthy AZ-b subnet. From then on everything worked, even though AZ-a was still cut off.
- **The design therefore survived the loss of an AZ's network with a 120 s outage, without any manual action.**

**Likely fix (to cut the 120 s further):**
1. Lower the API Lambda **timeout** (15 s → 6 s) and keep the DB `connectionTimeout` at 5 s, so broken environments fail and get replaced faster.
2. If an AZ stays unhealthy, evacuate it: set `lambda_subnet_indexes = [1]` and apply (about 2–4 minutes). This removes the broken subnet from every VPC Lambda.
2. Keep the client-side retry.
3. Alarm on the API 5xx rate. It already exists and triggers within 1–2 minutes.

Cost: $0. Network ACLs are free.

---

## FT4: Submitted assignment file deleted

**Script:** `scripts/failure-tests/ft4-s3-delete-recover.sh`

**What happens:**
1. The script uploads a 2 MB test file and deletes it.
2. It recovers the file by removing the delete marker.
3. It compares SHA-256 checksums of the original and the recovered file.

**Expected impact:** None for students. Versioning keeps the data, and the "deleted" object comes back in seconds.

**Measured on 2026-11-20 at 14:05 UTC.** Evidence: `evidence/failure-tests/ft4-20261120-200534-*`, `ft4-s3-versions.png` (delete marker over the 2.0 MB version), `ft4-terminal.png`.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Recovery time (remove the delete marker + download and verify) | < 10 s | **73 s** (mostly AWS CLI start-up time on Windows; the S3 action itself is instant) | ≤ 3600 s | ✅ |
| Checksum identical (RPO) | yes, so 0 s lost | **IDENTICAL**: SHA-256 `0b9a707f…5412b` before and after, so **0 bytes lost** | ≤ 300 s | ✅ |

**Finding and fix:**
- Non-current versions expire after **30 days** (`storage.tf`). A deletion noticed later than that cannot be undone.
- For records that must be kept for 5 years, raise the noncurrent-version expiration to 90 days.
- For legal holds, add **S3 Object Lock (governance mode)** on `assignments/`.
- Restrict `s3:DeleteObject` to an admin role.

---

## FT5: Marking worker outage while submissions arrive

**Script:** `scripts/failure-tests/ft5-marking-worker-outage.sh`

**What happens:**
1. The script sets the marking Lambda's reserved concurrency to 0.
2. It queues 50 messages.
3. It waits 3 minutes, then restores the worker.
4. It measures how long the backlog takes to drain and checks the DLQ.

**Expected impact:**
- Students can still submit, because the API only enqueues the work. Marking and emails are delayed.
- Messages stay in SQS, which retains them for 4 days.
- While the worker is throttled, SQS keeps redelivering. With `maxReceiveCount = 5`, **some messages can reach the DLQ**. That triggers the DLQ alarm, and the script redrives them.

**Measured on 2026-11-20:** worker stopped 14:40:01, 50 messages queued by 14:42:18, worker restored 14:45:40 UTC. Evidence: `evidence/failure-tests/ft5-20261120-203950-*` (the queue depth every 15 s), `ft5-*.png`.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Worker outage | 3 min | **5 min 39 s** (14:40:01 → 14:45:40) | — | — |
| Queue depth during the outage | rises to 50 | **50**, held steady: nothing was processed and nothing was dropped | — | — |
| Messages lost | 0 | **0** | ≤ 300 s of work | ✅ |
| Backlog drain after restore | < 60 s | **96 s** (50 → 28 → 16 → 6 → 0) | ≤ 3600 s | ✅ |
| Messages that reached the DLQ | 0–50 | **0**: the DLQ depth stayed 0, so no redrive was needed | 0 after redrive | ✅ |

**Result:**
- **Pass.** SQS kept every message while the worker was down. When the worker came back, the backlog cleared in 96 s with no help.
- Throttling the consumer did **not** push messages into the DLQ in a 5-minute outage. Longer outages could, after 5 receives.
- With an end-to-end RTO of about 7 minutes and RPO 0, a marking outage only delays results; it does not lose submissions.

**Likely fix:**
- Never stop a queue consumer with reserved concurrency 0. Disable the **event source mapping** instead, so messages are not received at all.
- Raise `maxReceiveCount` to 10.
- Keep the DLQ alarm and run `start-message-move-task` (in the script) after a fix.

---

## FT6: Region loss (tabletop exercise, not executed)

**Expected impact:** The whole platform is down. Multi-AZ does not help.

| Option | RPO | RTO | Extra cost |
|---|---|---|---|
| Accept the risk (current design) | up to 24 h (last backup is in the same Region) | days | $0 |
| `ENABLE_DR_BACKUP_COPY=true`: daily backups copied to Mumbai, plus a Terraform redeploy with `region=ap-south-1` | ≤ 24 h | ≈ 2–4 h | ≈ $3–5 / month (snapshot storage + transfer) |
| Warm standby (Aurora Global Database / cross-Region read replica) | < 1 min | < 1 h | + $150–300 / month |

**Decision: accept the risk, and switch on the DR backup copy before exam months.** A Region-wide outage of AWS Singapore is rare. A warm standby would double the database bill and push the exam-month cost towards the budget limit. The RTO target of 1 h is **not** met for Region loss. The feasibility verdict in `docs/cost-report.md` states this.
