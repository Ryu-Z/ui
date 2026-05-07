async (page) => {
const baseUrl = '__BASE_URL__';
const assert = (condition, message) => {
  if (!condition) {
    throw new Error(message);
  }
};
const jsonHeaders = { 'content-type': 'application/json' };
const requests = {
  status: [],
  commands: [],
  replay: [],
};

function parseUrl(rawUrl) {
  const queryIndex = rawUrl.indexOf('?');
  const pathStart = rawUrl.indexOf('/v3/');
  const pathname = rawUrl.slice(pathStart, queryIndex === -1 ? rawUrl.length : queryIndex);
  const query = queryIndex === -1 ? '' : rawUrl.slice(queryIndex + 1);
  const values = {};

  for (const pair of query.split('&')) {
    if (!pair) {
      continue;
    }

    const [key, value = ''] = pair.split('=');

    values[decodeURIComponent(key)] = decodeURIComponent(value.replace(/\+/g, ' '));
  }

  return {
    pathname,
    searchParams: {
      get(key) {
        return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : null;
      },
      has(key) {
        return Object.prototype.hasOwnProperty.call(values, key);
      },
    },
  };
}

async function fulfillJson(route, body, status = 200) {
  await route.fulfill({
    status,
    headers: jsonHeaders,
    body: JSON.stringify(body),
  });
}

async function setupHtmlErrorRoutes() {
  const html404 = '<!DOCTYPE HTML><html><body><h1>Error response</h1><p>File not found.</p></body></html>';

  await page.route('**/v3/terminal-audit/status', async (route) => {
    await route.fulfill({
      status: 404,
      contentType: 'text/html',
      body: html404,
    });
  });

  await page.route('**/v3/terminal-audit/commands**', async (route) => {
    await route.fulfill({
      status: 404,
      contentType: 'text/html',
      body: html404,
    });
  });
}

async function waitUntil(predicate, message) {
  for (let i = 0; i < 50; i += 1) {
    if (predicate()) {
      return;
    }

    await page.waitForTimeout(100);
  }

  throw new Error(message);
}

await page.route('**/v3/terminal-audit/status', async (route) => {
  requests.status.push(parseUrl(route.request().url()));
  await fulfillJson(route, {
    enabled: true,
    commandStorageType: 's3',
    replayStorageType: 's3',
  });
});
await page.route('**/v3/terminal-audit/commands**', async (route) => {
  const url = parseUrl(route.request().url());
  const searchedSession = url.searchParams.get('sessionId');

  requests.commands.push(url);

  if (searchedSession) {
    await fulfillJson(route, {
      count: 1,
      data: [{
        timestamp: 1778112000,
        user: url.searchParams.get('user'),
        asset: url.searchParams.get('asset'),
        account: url.searchParams.get('account'),
        session: searchedSession,
        input: url.searchParams.get('input'),
        riskLevel: 2,
      }],
    });
    return;
  }

  await fulfillJson(route, {
    count: 2,
    data: [{
      timestamp: 1778112000,
      user: 'alice',
      asset: 'prod-node-1',
      account: 'root',
      session: 'sess-a',
      input: 'kubectl get pods -A',
      riskLevel: 1,
    }],
  });
});
await page.route('**/v3/terminal-audit/replays/**/url**', async (route) => {
  const url = parseUrl(route.request().url());

  requests.replay.push(url);
  await fulfillJson(route, {
    url: 'https://replay.example/session-one.cast.gz?signature=test',
    key: 'terminal-audit/2026-05-07/session-one.cast.gz',
  });
});

await page.goto(baseUrl);
await page.waitForSelector('text=Command Records (2)');
await waitUntil(() => requests.status.length >= 1, 'status endpoint should be requested on load');
await waitUntil(() => requests.commands.length >= 1, 'commands endpoint should be requested on load');

assert(await page.locator('text=Enabled').count() > 0, 'status label should render');
assert(await page.locator('text=s3').count() >= 2, 'status storage values should render');
assert(await page.locator('text=kubectl get pods -A').count() === 1, 'initial command data should render');
assert(requests.commands[0].pathname === '/v3/terminal-audit/commands', 'initial commands endpoint path should match');
assert(requests.commands[0].searchParams.get('limit') === '100', 'initial commands query should include limit');

await page.locator('input[placeholder="Session"]').first().fill('sess/one');
await page.locator('input[placeholder="User"]').fill('alice@example.com');
await page.locator('input[placeholder="Asset"]').fill('prod-node-1');
await page.locator('input[placeholder="Account"]').fill('root');
await page.locator('input[placeholder="Command"]').fill('kubectl get pods');
await page.click('button:has-text("Search")');
await page.waitForSelector('text=Command Records (1)');
await waitUntil(() => requests.commands.length >= 2, 'commands endpoint should be requested on search');
assert(requests.commands[1].searchParams.get('sessionId') === 'sess/one', 'search request should include sessionId');
assert(requests.commands[1].searchParams.get('user') === 'alice@example.com', 'search request should include user');
assert(requests.commands[1].searchParams.get('input') === 'kubectl get pods', 'search request should include command input');

await page.click('button:has-text("Clear")');
await page.waitForSelector('text=Command Records (2)');
await waitUntil(() => requests.commands.length >= 3, 'commands endpoint should be requested after clearing filters');
assert(!requests.commands[2].searchParams.has('sessionId'), 'clear request should drop sessionId');
assert(requests.commands[2].searchParams.get('limit') === '100', 'clear request should keep default limit');

await page.locator('input[placeholder="YYYY-MM-DD"]').fill('2026-05-07');
await page.locator('input[placeholder="Session"]').nth(1).fill('sess/replay');
await page.locator('input[placeholder="session.cast.gz"]').fill('session one.cast.gz');
await page.locator('section:has(h3:has-text("Replay")) button.bg-primary').click();
await page.waitForSelector('text=terminal-audit/2026-05-07/session-one.cast.gz');
await waitUntil(() => requests.replay.length >= 1, 'replay endpoint should be requested');
assert(
  requests.replay[0].pathname === '/v3/terminal-audit/replays/sess%2Freplay/session%20one.cast.gz/url',
  'replay endpoint should URL-encode session and filename path segments'
);
assert(requests.replay[0].searchParams.get('date') === '2026-05-07', 'replay endpoint should include date query');

await page.unroute('**/v3/terminal-audit/status');
await page.unroute('**/v3/terminal-audit/commands**');
await page.unroute('**/v3/terminal-audit/replays/**/url**');
await setupHtmlErrorRoutes();
await page.goto(`${baseUrl}?html-error`);
await page.waitForSelector('.banner.bg-error');

const banner = await page.locator('.banner.bg-error').innerText();

assert(banner.includes('Request failed with status 404'), 'html error should become a concise HTTP error');
assert(!banner.includes('<!DOCTYPE'), 'html error should not leak raw response body');

console.log('terminal audit playwright-cli browser tests passed');
}
