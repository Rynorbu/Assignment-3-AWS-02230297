#!/usr/bin/env node
// Assignment 3 – exam-peak load test (no dependencies, Node 20+).
//
// Reproduces the brief: N students START one exam within RAMP seconds, then every student
// AUTOSAVES every AUTOSAVE seconds until the test ends. 3,000 students / 300 s / 30 s gives
// ~10 starts/s during the ramp and ~100 autosaves/s at steady state.
//
// Virtual students are spread over the accounts made by scripts/seed-load-users.sh
// (loadtest001@domain ...). Every account resumes the same attempt, which is what the API does
// after a reconnect, so the database work per request is realistic.
//
// Usage (repo root):
//   node scripts/peak-load-test.mjs --label before --exam-id 3 --domain example.com --accounts 200 \
//        --password 'LoadTest#2026pass' [--students 3000] [--ramp 300] [--hold 300] [--autosave 30]
// app_url, user_pool_client_id and region are read from `terraform output` unless given with
// --url / --client-id / --region. Results go to evidence/load-test/<label>-*.{json,csv}.
import { execSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';

const args = Object.fromEntries(process.argv.slice(2).reduce((acc, a, i, all) => {
  if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : 'true']);
  return acc;
}, []));
const tf = (name) => execSync(`terraform -chdir=infra output -raw ${name}`, { encoding: 'utf8' }).trim();
const cfg = {
  label: args.label || 'run',
  url: args.url || tf('app_url'),
  clientId: args['client-id'] || tf('user_pool_client_id'),
  region: args.region || tf('region'),
  examId: args['exam-id'],
  domain: args.domain,
  accounts: Number(args.accounts || 50),
  password: args.password,
  students: Number(args.students || 3000),
  ramp: Number(args.ramp || 300),
  hold: Number(args.hold || 300),
  autosave: Number(args.autosave || 30),
};
if (!cfg.examId || !cfg.domain || !cfg.password) {
  console.error('Required: --exam-id <id> --domain <email domain> --password <load-test password>  (see header)');
  process.exit(1);
}

// ---------- sign in the load-test accounts ----------
async function signIn(email) {
  const res = await fetch(`https://cognito-idp.${cfg.region}.amazonaws.com/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-amz-json-1.1', 'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth' },
    body: JSON.stringify({ AuthFlow: 'USER_PASSWORD_AUTH', ClientId: cfg.clientId, AuthParameters: { USERNAME: email, PASSWORD: cfg.password } }),
  }).then((r) => r.json());
  const token = res.AuthenticationResult?.IdToken;
  if (!token) throw new Error(`sign-in failed for ${email}: ${JSON.stringify(res)}`);
  return token;
}
const tokens = [];
for (let i = 1; i <= cfg.accounts; i += 5) {
  const batch = [];
  for (let j = i; j < i + 5 && j <= cfg.accounts; j++) batch.push(signIn(`loadtest${String(j).padStart(String(cfg.accounts).length, '0')}@${cfg.domain}`));
  tokens.push(...(await Promise.all(batch)));
}
console.log(`Signed in ${tokens.length} accounts. Target: ${cfg.students} students start within ${cfg.ramp}s, autosave every ${cfg.autosave}s, hold ${cfg.hold}s.`);

// ---------- metrics ----------
const T0 = Date.now();
const buckets = new Map(); // 10-second buckets
const all = { latencies: [], statuses: {}, byType: { start: 0, autosave: 0 } };
let active = 0;
function record(type, status, ms) {
  const b = Math.floor((Date.now() - T0) / 10000);
  if (!buckets.has(b)) buckets.set(b, { n: 0, ok: 0, lat: [], statuses: {}, active: 0 });
  const k = buckets.get(b);
  k.n++; if (status === 200) k.ok++; k.lat.push(ms); k.statuses[status] = (k.statuses[status] || 0) + 1; k.active = active;
  all.latencies.push(ms); all.statuses[status] = (all.statuses[status] || 0) + 1; all.byType[type]++;
}
async function call(type, method, path, token, body) {
  const t = performance.now();
  let status;
  try {
    const r = await fetch(`${cfg.url}${path}`, {
      method, body: body && JSON.stringify(body), signal: AbortSignal.timeout(15000),
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    });
    status = r.status;
    const json = await r.json().catch(() => ({}));
    record(type, status, performance.now() - t);
    return { status, json };
  } catch (e) {
    status = e.name === 'TimeoutError' ? 'timeout' : 'network-error';
    record(type, status, performance.now() - t);
    return { status };
  }
}
const pct = (arr, q) => { if (!arr.length) return 0; const s = [...arr].sort((a, b) => a - b); return Math.round(s[Math.min(s.length - 1, Math.floor(q * s.length))]); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- virtual students ----------
const END = T0 + (cfg.ramp + cfg.hold) * 1000;
async function student(i) {
  await sleep((i / cfg.students) * cfg.ramp * 1000 + Math.random() * 500);
  const token = tokens[i % tokens.length];
  active++;
  let attemptId;
  for (let tries = 0; tries < 3 && !attemptId; tries++) { // the real UI retries a failed start
    const r = await call('start', 'POST', `/api/exams/${cfg.examId}/start`, token);
    attemptId = r.json?.attemptId;
    if (!attemptId) await sleep(2000);
  }
  if (!attemptId) { active--; return; }
  await sleep(Math.random() * cfg.autosave * 1000); // students did not all open the exam on the same second
  let n = 0;
  while (Date.now() < END) {
    await call('autosave', 'PUT', `/api/attempts/${attemptId}/answers`, token, { answers: { q1: 'Amazon S3', q3: `vu ${i} save ${++n}` } });
    await sleep(cfg.autosave * 1000);
  }
  active--;
}

const ticker = setInterval(() => {
  const b = buckets.get(Math.floor((Date.now() - T0) / 10000) - 1);
  if (!b) return;
  const errs = Object.entries(b.statuses).filter(([s]) => s !== '200').map(([s, c]) => `${s}:${c}`).join(' ') || '-';
  console.log(`t+${String(Math.round((Date.now() - T0) / 1000)).padStart(4)}s active=${String(b.active).padStart(4)} rps=${(b.n / 10).toFixed(1).padStart(6)} ok=${((100 * b.ok) / b.n).toFixed(1).padStart(5)}% p50=${pct(b.lat, 0.5)}ms p95=${pct(b.lat, 0.95)}ms errors=${errs}`);
}, 10000);

await Promise.all(Array.from({ length: cfg.students }, (_, i) => student(i)));
clearInterval(ticker);

// ---------- results ----------
const total = all.latencies.length;
const ok = all.statuses[200] || 0;
const summary = {
  label: cfg.label, startedAt: new Date(T0).toISOString(), finishedAt: new Date().toISOString(),
  config: { ...cfg, password: undefined, clientId: undefined },
  requests: total, byType: all.byType, statuses: all.statuses,
  successRatePct: +((100 * ok) / total).toFixed(2),
  latencyMs: { p50: pct(all.latencies, 0.5), p95: pct(all.latencies, 0.95), p99: pct(all.latencies, 0.99), max: pct(all.latencies, 1) },
  peakRps: Math.max(...[...buckets.values()].map((b) => b.n / 10)),
};
mkdirSync('evidence/load-test', { recursive: true });
const stamp = new Date(T0).toISOString().replace(/[:.]/g, '-');
writeFileSync(`evidence/load-test/${cfg.label}-${stamp}.json`, JSON.stringify(summary, null, 2));
const csv = ['second,active_students,requests,ok,rps,p50_ms,p95_ms,non_200'];
for (const [b, k] of [...buckets.entries()].sort((a, c) => a[0] - c[0])) {
  csv.push([b * 10, k.active, k.n, k.ok, (k.n / 10).toFixed(1), pct(k.lat, 0.5), pct(k.lat, 0.95), k.n - k.ok].join(','));
}
writeFileSync(`evidence/load-test/${cfg.label}-${stamp}.csv`, csv.join('\n'));
console.log(JSON.stringify(summary, null, 2));
console.log(`Saved evidence/load-test/${cfg.label}-${stamp}.json and .csv`);
