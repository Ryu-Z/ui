import assert from 'node:assert/strict';
import test from 'node:test';
import { loadCommands, loadReplayUrl, loadStatus } from '../../src/api/terminalAudit.js';

function jsonResponse(body, init = {}) {
  return new Response(JSON.stringify(body), {
    status: init.status || 200,
    statusText: init.statusText || 'OK',
    headers: {
      'content-type': 'application/json',
      ...(init.headers || {}),
    },
  });
}

function textResponse(body, init = {}) {
  return new Response(body, {
    status: init.status || 200,
    statusText: init.statusText || 'OK',
    headers: {
      'content-type': init.contentType || 'text/plain',
    },
  });
}

function mockFetch(handler) {
  const calls = [];

  globalThis.fetch = async (path, init) => {
    calls.push({ path, init });

    return handler(path, init);
  };

  return calls;
}

test('loadStatus fetches the terminal audit status endpoint', async () => {
  const expected = {
    enabled: true,
    commandStorageType: 's3',
    replayStorageType: 's3',
  };
  const calls = mockFetch((path) => {
    assert.equal(path, '/v3/terminal-audit/status');

    return jsonResponse(expected);
  });

  assert.deepEqual(await loadStatus(), expected);
  assert.equal(calls[0].init.credentials, 'same-origin');
  assert.equal(calls[0].init.headers.accept, 'application/json');
});

test('loadCommands filters empty params and URL-encodes query values', async () => {
  const expected = {
    count: 1,
    data: [{ session: 'sess/one', input: 'kubectl get pods' }],
  };
  const calls = mockFetch(() => jsonResponse(expected));

  assert.deepEqual(await loadCommands({
    sessionId: 'sess/one',
    user: 'alice@example.com',
    asset: '',
    account: null,
    input: 'kubectl get pods',
    limit: 100,
  }), expected);

  assert.equal(
    calls[0].path,
    '/v3/terminal-audit/commands?sessionId=sess%2Fone&user=alice%40example.com&input=kubectl%20get%20pods&limit=100'
  );
});

test('loadReplayUrl encodes path segments and optional date query', async () => {
  const expected = {
    url: 'https://replay.example/session.cast.gz',
    key: 'terminal-audit/2026-05-07/session.cast.gz',
  };
  const calls = mockFetch(() => jsonResponse(expected));

  assert.deepEqual(await loadReplayUrl({
    sessionId: 'sess/one',
    filename: 'session one.cast.gz',
    date: '2026-05-07',
  }), expected);

  assert.equal(
    calls[0].path,
    '/v3/terminal-audit/replays/sess%2Fone/session%20one.cast.gz/url?date=2026-05-07'
  );
});

test('non-json error responses do not leak raw HTML into UI messages', async () => {
  mockFetch(() => textResponse(
    '<!DOCTYPE HTML><html><body><h1>Error response</h1></body></html>',
    { status: 404, statusText: 'File not found', contentType: 'text/html' }
  ));

  await assert.rejects(
    () => loadStatus(),
    (err) => {
      assert.equal(err.message, 'Request failed with status 404 File not found');
      assert.equal(err.message.includes('<!DOCTYPE'), false);

      return true;
    }
  );
});
