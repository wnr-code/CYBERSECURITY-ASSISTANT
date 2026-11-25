const MAX_BODY_BYTES = 64 * 1024;
const TYPES = new Set([
  'bugReport', 'crashReport', 'runtimeError', 'assessmentError',
  'terminalError', 'aiProviderError', 'marketError', 'networkCloudError',
]);
const SEVERITIES = new Set(['info', 'low', 'medium', 'high', 'critical']);
const FIELDS = [
  'type', 'severity', 'category', 'component', 'moduleVersion', 'appVersion',
  'buildNumber', 'runtimeVersion', 'occurredAt', 'assessmentId', 'executionId',
  'runtimeStatus', 'errorType', 'message', 'stackTrace', 'reproductionSteps',
  'occurrences',
];
const MAX_LENGTHS = {
  category: 40, component: 80, moduleVersion: 80, appVersion: 80, buildNumber: 80,
  runtimeVersion: 120, assessmentId: 128, executionId: 128, runtimeStatus: 120,
  errorType: 100, message: 900, stackTrace: 2400, reproductionSteps: 1200,
};


function sanitizeText(value) {
  return value
    .replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----/gi, '[private-key-redacted]')
    .replace(/\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+\/-]+=*/gi, '[authorization-redacted]')
    .replace(/\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|AKIA[0-9A-Z]{16})\b/g, '[credential-redacted]')
    .replace(/\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g, '[jwt-redacted]')
    .replace(/(authorization|cookie|set-cookie|credential|token|api[_-]?key|password|secret)\s*[:=]\s*[^\s,;]+/gi, '$1=[redacted]')
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, '[email]')
    .replace(/https?:\/\/\S+/gi, '[url]')
    .replace(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g, '[ip]')
    .replace(/(?:\/data\/\S+|\/storage\/emulated\/\S+|\/sdcard\/\S+|\/Users\/\S+|\/home\/\S+|\/private\/var\/\S+|[A-Z]:\\\S+)/gi, '[path]');
}

function constantTimeEqual(actual, expected) {
  const left = new TextEncoder().encode(actual);
  const right = new TextEncoder().encode(expected);
  let mismatch = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let i = 0; i < length; i++) mismatch |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return mismatch === 0;
}

async function readBodyLimited(request) {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

function allowedReport(report) {
  if (!report || typeof report !== 'object' || Array.isArray(report)) return false;
  if (!TYPES.has(report.type) || !SEVERITIES.has(report.severity)) return false;
  for (const [key, max] of Object.entries(MAX_LENGTHS)) {
    if (report[key] != null && (typeof report[key] !== 'string' || report[key].length > max)) return false;
  }
  if (report.occurredAt != null && (typeof report.occurredAt !== 'string' || !Number.isFinite(Date.parse(report.occurredAt)))) return false;
  if (report.occurrences != null && (!Number.isInteger(report.occurrences) || report.occurrences < 1 || report.occurrences > 100000)) return false;
  return true;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== '/diagnostics') return json({ error: 'not_found' }, 404);
    if (request.method === 'GET') return json({ status: 'ok', service: 'diagnostics-relay' });
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

    const expected = env.RELAY_BEARER_TOKEN;
    const authorization = request.headers.get('authorization') ?? '';
    if (!expected || !constantTimeEqual(authorization, `Bearer ${expected}`)) return json({ error: 'unauthorized' }, 401);

    const contentLength = Number(request.headers.get('content-length') ?? '0');
    if (contentLength > MAX_BODY_BYTES) return json({ error: 'payload_too_large' }, 413);
    const bytes = await readBodyLimited(request);
    if (bytes === null) return json({ error: 'payload_too_large' }, 413);

    let body;
    try {
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) {
      return json({ error: 'invalid_json' }, 400);
    }
    if (body?.schemaVersion !== 2 || !allowedReport(body.report)) return json({ error: 'invalid_report' }, 400);

    // Allowlist again at the relay boundary. Never persist client-local queue,
    // approval, fingerprint, device identity, token, or arbitrary extra fields.
    const report = Object.fromEntries(FIELDS.filter((key) => body.report[key] !== undefined).map((key) => {
      const value = body.report[key];
      return [key, typeof value === 'string' ? sanitizeText(value) : value];
    }));
    const repository = typeof body.repository === 'string' && /^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/.test(body.repository)
      ? body.repository
      : null;
    try {
      await env.DIAGNOSTICS_DB.prepare(
        'INSERT INTO diagnostic_reports (id, received_at, repository, report_json) VALUES (?, ?, ?, ?)',
      ).bind(crypto.randomUUID(), new Date().toISOString(), repository, JSON.stringify(report)).run();
    } catch (_) {
      return json({ error: 'temporarily_unavailable' }, 503);
    }
    return json({ accepted: true }, 202);
  },
};
