import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

function databaseMock() {
  const rows = [];
  return {
    rows,
    prepare(sql) {
      assert.match(sql, /INSERT INTO diagnostic_reports/);
      return {
        bind(...values) {
          return { async run() { rows.push(values); } };
        },
      };
    },
  };
}

const envWith = (db = databaseMock()) => ({
  RELAY_BEARER_TOKEN: 'relay-test-token-012345678901234567890123456789',
  DIAGNOSTICS_DB: db,
});

const validPayload = {
  schemaVersion: 2,
  repository: 'owner/project',
  labels: ['bug'],
  report: {
    type: 'bugReport',
    severity: 'medium',
    category: 'bug',
    component: 'user_report',
    appVersion: '1.0.0',
    message: 'token=supersecret123 user@example.test https://private.example/path',
    stackTrace: '',
    reproductionSteps: 'Repeat the action',
    occurrences: 1,
    fingerprint: 'local-only-fingerprint',
    uploadApproved: true,
    deviceId: 'must-not-be-saved',
  },
};

test('health endpoint is public and does not require a relay token', async () => {
  const response = await worker.fetch(new Request('https://relay.test/diagnostics'), envWith());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, 'ok');
});

test('rejects missing bearer credential and malformed reports', async () => {
  const unauthorized = await worker.fetch(new Request('https://relay.test/diagnostics', { method: 'POST', body: '{}' }), envWith());
  assert.equal(unauthorized.status, 401);

  const invalid = await worker.fetch(new Request('https://relay.test/diagnostics', {
    method: 'POST',
    headers: { authorization: `Bearer ${envWith().RELAY_BEARER_TOKEN}` },
    body: JSON.stringify({ schemaVersion: 99 }),
  }), envWith());
  assert.equal(invalid.status, 400);
});

test('persists only allowlisted sanitized report fields', async () => {
  const db = databaseMock();
  const env = envWith(db);
  const response = await worker.fetch(new Request('https://relay.test/diagnostics', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RELAY_BEARER_TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify(validPayload),
  }), env);
  assert.equal(response.status, 202);
  assert.equal(db.rows.length, 1);
  const report = JSON.parse(db.rows[0][3]);
  assert.equal(report.message.includes('supersecret123'), false);
  assert.equal(report.message.includes('user@example.test'), false);
  assert.equal(report.message.includes('private.example'), false);
  assert.equal('fingerprint' in report, false);
  assert.equal('uploadApproved' in report, false);
  assert.equal('deviceId' in report, false);
});

test('rejects payloads over the 64 KiB bound', async () => {
  const env = envWith();
  const response = await worker.fetch(new Request('https://relay.test/diagnostics', {
    method: 'POST',
    headers: { authorization: `Bearer ${env.RELAY_BEARER_TOKEN}` },
    body: 'x'.repeat(65 * 1024),
  }), env);
  assert.equal(response.status, 413);
});
