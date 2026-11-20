#!/usr/bin/env node
// Cost model for the exam platform in ap-southeast-1 (Singapore).
// Every unit price comes from the AWS Price List API (publication dates 2026-10-19 .. 2026-11-18,
// checked 2026-11-19) unless marked [calc] (copied from the AWS Pricing Calculator / pricing page).
// The usage numbers are the ASSUMPTIONS listed in docs/cost-report.md section 1.
// Run:  node scripts/cost-model.mjs            -> prints markdown tables
//       node scripts/cost-model.mjs --json     -> prints the raw numbers
const H = 730; // hours per month used by the AWS Pricing Calculator

// ---------------- unit prices (USD) ----------------
const P = {
  sgp: {
    rds: { 't4g.micro': 0.051, 't4g.small': 0.102, 't4g.medium': 0.203, 't4g.large': 0.406, 'm6g.large': 0.441, 'm7g.large': 0.468 }, // Multi-AZ PostgreSQL / hour
    rdsRiMonthly: { 't4g.medium': 111.29, 't4g.large': 222.50 }, // 1-yr Partial Upfront, Multi-AZ, effective / month
    gp3MultiAz: 0.276, // GB-month
    proxyVcpu: 0.018, // per vCPU-hour (min 2 vCPU billed)
    snapshot: 0.095, // GB-month backup storage beyond free allocation
    cpuCredit: 0.075, // per vCPU-hour of T4g surplus credits
    natHour: 0.059, natGb: 0.059, // [calc] NAT gateway
    vpceHour: 0.013, vpceGb: 0.01, // interface endpoint, per AZ
    lambdaReq: 0.20 / 1e6, lambdaGbSArm: 0.0000133334,
    apiHttp: 1.25 / 1e6,
    cfGb: 0.120, cfReq: 0.012 / 1e4, // [calc] CloudFront Asia/India blend (India 0.109, SG 0.140), HTTPS requests
    wafAcl: 5, wafRule: 1, wafReq: 0.60 / 1e6, // [calc] WAF (global, CloudFront scope)
    s3Std: 0.025, s3Ia: 0.0138, s3Gir: 0.005, s3Gda: 0.002, s3Int: 0.025, // GB-month (Deep Archive SG 0.002 [calc])
    s3Put: 0.005 / 1000, s3Get: 0.0004 / 1000, s3LifecycleGda: 0.06 / 1000, s3LifecycleIa: 0.01 / 1000,
    dtoInternet: 0.12, // [calc] S3 -> internet, first 10 TB
    interAz: 0.02, // 0.01 out + 0.01 in per GB
    cwLogsIngest: 0.70, cwLogsStore: 0.03, cwAlarm: 0.10, cwDashboard: 3,
    kmsKey: 1, kmsReq: 0.03 / 1e4,
    secret: 0.40, secretReq: 0.05 / 1e4,
    sqsReq: 0.40 / 1e6,
    ses: 0.10 / 1000, // [calc]
    cognitoMau: 0.0055, cognitoFreeMau: 10000,
    route53Zone: 0.50,
  },
};
// Mumbai (ap-south-1) prices that differ, for the Region comparison
P.bom = {
  ...P.sgp,
  rds: { 't4g.medium': 0.167, 't4g.large': 0.334, 'm7g.large': 0.479 },
  rdsRiMonthly: { 't4g.medium': 0.167 * H * 0.75, 't4g.large': 0.334 * H * 0.75 }, // ~25 % RI discount assumed [calc]
  gp3MultiAz: 0.262, proxyVcpu: 0.017, apiHttp: 1.05 / 1e6, cwLogsIngest: 0.67,
  cfGb: 0.109, // users in Bhutan/India served from India edges
  dtoInternet: 0.1093, // [calc]
  natHour: 0.056, natGb: 0.056, // [calc]
};

// ---------------- usage assumptions ----------------
const U = {
  normal: {
    apiRequests: 14.4e6, // 400 avg active users x 2 req/min x 10 h x 30 days
    staticGb: 50, apiGbOut: 72, // CloudFront bytes: SPA assets + API responses (5 KB avg)
    lambdaMs: 80, lambdaMb: 512,
    logsGb: 11, // API access logs + Lambda + RDS logs
    uploads: 12000, uploadGb: 120, tutorDownloadGb: 120,
    emails: 36000,
    sqsRequests: 2.0e6, // includes Lambda long-polling of 3 queues
    kmsRequests: 100000,
    interAzGb: 86,
    dbClass: 't4g.medium', cpuCreditVcpuH: 0,
  },
  exam: {
    apiRequests: 22.4e6, // normal 14.4 M + 40,000 attempts x 200 requests
    staticGb: 75, apiGbOut: 112,
    lambdaMs: 80, lambdaMb: 512,
    logsGb: 17,
    uploads: 4000, uploadGb: 40, tutorDownloadGb: 60,
    emails: 50000,
    sqsRequests: 2.4e6,
    kmsRequests: 150000,
    interAzGb: 134,
    dbClass: 't4g.large', cpuCreditVcpuH: 130, // surplus credits during exam sittings
  },
};
// S3 storage at STEADY STATE (year 5): 1.44 TB of new files per year
const S3_STEADY = { std: 120, ia: 600, gir: 740, gda: 5760 }; // GB in each class
const S3_TOTAL_GB = Object.values(S3_STEADY).reduce((a, b) => a + b, 0);

function month(profile, region = 'sgp', opts = {}) {
  const p = P[region], u = U[profile];
  const o = { nat: 0, ri: false, lifecycle: true, logRetentionMonths: 1, dbAllYear: null, ...opts };
  const dbClass = o.dbAllYear || u.dbClass;
  let rds;
  if (o.ri && region === 'sgp') {
    // RI on t4g.medium (size-flexible): covers the whole medium, and half of a large
    rds = dbClass === 't4g.medium' ? p.rdsRiMonthly['t4g.medium'] : p.rdsRiMonthly['t4g.medium'] + p.rds['t4g.medium'] * H;
  } else rds = p.rds[dbClass] * H;
  const lines = {
    'RDS PostgreSQL Multi-AZ (instance)': rds,
    'RDS storage gp3 Multi-AZ (20 GB)': 20 * p.gp3MultiAz,
    'RDS Proxy (2 vCPU)': 2 * p.proxyVcpu * H,
    'RDS CPU credits (T4g unlimited)': u.cpuCreditVcpuH * p.cpuCredit,
    'Backups (AWS Backup snapshots, 40 GB)': 40 * p.snapshot,
    'NAT gateway hours + processing': o.nat * p.natHour * H + (o.nat ? 5 * p.natGb : 0),
    // SQS endpoint always; Secrets Manager endpoint only when there is no NAT (RDS Proxy needs it)
    'VPC interface endpoints (SQS + Secrets Manager, 2 AZ each)': (o.nat ? 1 : 2) * (2 * p.vpceHour * H) + 2 * p.vpceGb,
    'Lambda (arm64) requests + compute': u.apiRequests * 1.05 * p.lambdaReq + u.apiRequests * (u.lambdaMs / 1000) * (u.lambdaMb / 1024) * p.lambdaGbSArm + 43200 * 0.2 * 0.5 * p.lambdaGbSArm,
    'API Gateway HTTP API': u.apiRequests * p.apiHttp,
    'CloudFront data out + requests': (u.staticGb + u.apiGbOut) * p.cfGb + (u.apiRequests * 1.07) * p.cfReq,
    'WAF (web ACL + 4 rules + requests)': p.wafAcl + 4 * p.wafRule + u.apiRequests * 1.07 * p.wafReq,
    'S3 storage (uploads, 5-yr steady state)': o.lifecycle
      ? S3_STEADY.std * p.s3Std + S3_STEADY.ia * p.s3Ia + S3_STEADY.gir * p.s3Gir + S3_STEADY.gda * p.s3Gda
      : S3_TOTAL_GB * p.s3Std,
    'S3 requests + lifecycle transitions': u.uploads * p.s3Put + u.uploads * 3 * p.s3Get + (o.lifecycle ? u.uploads * (2 * p.s3LifecycleIa + p.s3LifecycleGda) : 0),
    'Data transfer out (S3 downloads to tutors)': u.tutorDownloadGb * p.dtoInternet,
    'Inter-AZ data transfer (Lambda <-> RDS)': u.interAzGb * p.interAz,
    'CloudWatch Logs ingest + storage': u.logsGb * p.cwLogsIngest + u.logsGb * o.logRetentionMonths * p.cwLogsStore,
    'CloudWatch alarms (14) + dashboard': 4 * p.cwAlarm + p.cwDashboard, // first 10 alarms and 3 dashboards are free
    'KMS key + requests': p.kmsKey + Math.max(0, u.kmsRequests - 20000) * p.kmsReq,
    'Secrets Manager (1 secret)': p.secret + 50000 * p.secretReq,
    'SQS requests': Math.max(0, u.sqsRequests - 1e6) * p.sqsReq,
    'SES email': u.emails * p.ses,
    'Cognito (8,400 MAU, 10k free)': Math.max(0, 8400 - p.cognitoFreeMau) * p.cognitoMau,
    'Route 53 hosted zone': p.route53Zone,
    'EventBridge schedule + CloudTrail (free tier)': 0,
  };
  const total = Object.values(lines).reduce((a, b) => a + b, 0);
  return { lines, total };
}

function annual(region = 'sgp', opts = {}) {
  const n = month('normal', region, opts).total, e = month('exam', region, opts).total;
  return { normal: n, exam: e, annual: 10 * n + 2 * e, avg: (10 * n + 2 * e) / 12 };
}

const scenarios = {
  // Assignment 2 production design moved to Singapore unchanged
  a2: annual('sgp', { nat: 2, ri: false, lifecycle: true, logRetentionMonths: 3, dbAllYear: 'm6g.large' }),
  // Final optimised design (this repo)
  final: annual('sgp', { nat: 0, ri: true, lifecycle: true, logRetentionMonths: 1 }),
  finalOnDemand: annual('sgp', { nat: 0, ri: false, lifecycle: true, logRetentionMonths: 1 }),
  mumbai: annual('bom', { nat: 0, ri: false, lifecycle: true, logRetentionMonths: 1 }),
};
const opt = {
  'O1 Remove 2 NAT gateways (VPC endpoints only)': annual('sgp', { nat: 2, ri: false, logRetentionMonths: 1, dbAllYear: null }).annual - scenarios.finalOnDemand.annual,
  'O2 Seasonal right-sizing (t4g.medium normal / t4g.large exam vs m6g.large all year)': annual('sgp', { nat: 0, logRetentionMonths: 1, dbAllYear: 'm6g.large' }).annual - scenarios.finalOnDemand.annual,
  'O3 1-yr RDS Reserved Instance (t4g.medium, partial upfront)': scenarios.finalOnDemand.annual - scenarios.final.annual,
  'O4 S3 lifecycle to IA/Glacier IR/Deep Archive vs S3 Standard (steady state)': annual('sgp', { nat: 0, ri: true, lifecycle: false }).annual - scenarios.final.annual,
  'O5 Log retention 90 -> 30 days': annual('sgp', { nat: 0, ri: true, logRetentionMonths: 3 }).annual - scenarios.final.annual,
};

const f = (x) => '$' + x.toFixed(2);
if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ normal: month('normal', 'sgp', { ri: true }), exam: month('exam', 'sgp', { ri: true }), scenarios, opt }, null, 2));
} else {
  const n = month('normal', 'sgp', { ri: true }), e = month('exam', 'sgp', { ri: true });
  console.log('| Service | Normal month | Exam month |\n|---|---:|---:|');
  for (const k of Object.keys(n.lines)) console.log(`| ${k} | ${f(n.lines[k])} | ${f(e.lines[k])} |`);
  console.log(`| **Total** | **${f(n.total)}** | **${f(e.total)}** |\n`);
  for (const [k, v] of Object.entries(scenarios)) console.log(`${k}: normal ${f(v.normal)}  exam ${f(v.exam)}  annual ${f(v.annual)}  avg/month ${f(v.avg)}  per student/yr ${f(v.annual / 8000)}`);
  console.log('\nOptimisations (annual saving):');
  for (const [k, v] of Object.entries(opt)) console.log(`${k}: ${f(v)} / year (${f(v / 12)} / month avg)`);
}
