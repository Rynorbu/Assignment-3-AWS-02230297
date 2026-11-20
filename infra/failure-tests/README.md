# Failure tests: scenarios, expected impact, measurements and fixes

Targets: **RPO ≤ 5 minutes**, **RTO ≤ 1 hour**, and the platform must **survive the loss of one AZ**.
Region: ap-southeast-1 (Singapore).

Every scenario has a script in [`scripts/failure-tests/`](../../scripts/failure-tests). Each script writes CSV and text evidence to `evidence/failure-tests/`.

- **Expected** is what the design predicts *before* the test.
- **Measured** is filled in from the script output after the run.
- Any measured value still showing `☐` has not been run yet.

| # | Scenario | Layer | How it is caused | RPO target | RTO target |
|---|---|---|---|---|---|
| FT1 | AZ hosting the primary DB is lost | Database | `reboot-db-instance --force-failover` | 5 min | 1 h |
| FT2 | Answers wiped by a bad change (logical corruption) | Database | Point-in-time restore | 5 min | 1 h |
| FT3 | Network of one AZ lost for the Lambda subnet | Compute / network | AWS FIS `aws:network:disrupt-connectivity` | 5 min | 1 h |
| FT4 | Submitted assignment file deleted | Storage | `aws s3 rm` on a versioned object | 5 min | 1 h |
| FT5 | Marking worker down during submissions | Async | Lambda reserved concurrency = 0 | 5 min | 1 h |
| FT6 | Whole Singapore Region unavailable (tabletop exercise, not executed) | Region | — | 5 min | 1 h |

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

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Health-check downtime (`downtime_s`) | 60–120 s (no proxy), < 30 s (proxy) | ☐ | ≤ 3600 s | ☐ |
| Failed probes | 15–60 | ☐ | — | — |
| Marker answer present after failover (RPO) | yes, so 0 s lost | ☐ | ≤ 300 s | ☐ |
| Primary AZ before → after | `ap-southeast-1a` → `1b` | ☐ | different AZ | ☐ |

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

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| RPO exposure (now − LatestRestorableTime) | 60–300 s | ☐ | ≤ 300 s | ☐ |
| Restore until `available` | 600–1500 s | ☐ | — | — |
| Total RTO (restore + switch) | 15–35 min | ☐ | ≤ 60 min | ☐ |

**Recovery runbook (the fix):**

```bash
aws rds modify-db-instance --db-instance-identifier exam-platform-prod-db --new-db-instance-identifier exam-platform-prod-db-broken --apply-immediately
aws rds modify-db-instance --db-instance-identifier exam-platform-prod-db-ft2-restore --new-db-instance-identifier exam-platform-prod-db --apply-immediately
aws rds modify-db-instance --db-instance-identifier exam-platform-prod-db --multi-az --apply-immediately   # online
```

- Because the endpoint name is unchanged, there is no redeploy, and Terraform state still matches.
- **Residual risk:** answers autosaved between the bad change and the restore point must be re-sent. Clients keep them locally until the exam is submitted.

---

## FT3: Network loss in one AZ for the Lambda subnet (AWS FIS)

**Script:** `scripts/failure-tests/ft3-az-network-loss.sh`. Deploy with `ENABLE_FIS=true` first.

**What happens:**
- The FIS template [`infra/fis.tf`](../fis.tf) puts a deny-all network ACL on the **app subnet in the first AZ** for 5 minutes.
- The script calls `/api/health` every 2 seconds for 7 minutes.

**Expected impact:**
- Lambda does **not** health-check its subnets. Execution environments in the broken subnet cannot reach RDS or the SQS endpoint, so their requests time out after 5 seconds (`connectionTimeout`).
- Expect a **partial failure**: roughly **20–50 % of API calls fail** for the 5 minutes. Environments in the healthy AZ keep working.
- Autosave retries every 30 seconds and keeps answers locally. The answers that actually reach the database are, in the worst case, 30–60 s behind the student's screen. Nothing is lost while the browser stays open.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Failed probes during the 5-minute fault | 20–50 % | ☐ | — | — |
| Time until 100 % success after the fault ends | < 30 s | ☐ | ≤ 3600 s | ☐ |
| Data lost (answers) | 0 (client retry) | ☐ | ≤ 300 s | ☐ |

**Likely fix:**
1. Evacuate the sick AZ. Set `lambda_subnet_indexes = [1]` and apply (about 2–4 minutes). This removes the broken subnet from every VPC Lambda.
2. Keep the client-side retry.
3. Alarm on the API 5xx rate. It already exists and triggers within 1–2 minutes.

FIS costs about $0.10 per action-minute, so one run costs about $0.50.

---

## FT4: Submitted assignment file deleted

**Script:** `scripts/failure-tests/ft4-s3-delete-recover.sh`

**What happens:**
1. The script uploads a 2 MB test file and deletes it.
2. It recovers the file by removing the delete marker.
3. It compares SHA-256 checksums of the original and the recovered file.

**Expected impact:** None for students. Versioning keeps the data, and the "deleted" object comes back in seconds.

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Recovery time | < 10 s | ☐ | ≤ 3600 s | ☐ |
| Checksum identical (RPO) | yes, so 0 s lost | ☐ | ≤ 300 s | ☐ |

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

| Measure | Expected | Measured | Target | Pass? |
|---|---|---|---|---|
| Messages lost | 0 | ☐ | ≤ 300 s of work | ☐ |
| Backlog drain after restore | < 60 s | ☐ | ≤ 3600 s | ☐ |
| Messages that reached the DLQ (then redriven) | 0–50 | ☐ | 0 after redrive | ☐ |

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
