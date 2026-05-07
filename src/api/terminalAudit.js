async function readJson(response) {
  const text = await response.text();

  if (!text) {
    return {};
  }

  try {
    return JSON.parse(text);
  } catch {
    return { message: text };
  }
}

async function request(path) {
  const response = await fetch(path, {
    credentials: 'same-origin',
    headers: {
      accept: 'application/json',
    },
  });
  const body = await readJson(response);

  if (!response.ok) {
    throw new Error(body.message || body.error || response.statusText);
  }

  return body;
}

export function loadStatus() {
  return request('/v3/terminal-audit/status');
}

export function loadCommands(params = {}) {
  const query = Object.entries(params)
    .filter(([, value]) => value !== '' && value !== undefined && value !== null)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');

  return request(`/v3/terminal-audit/commands${query ? `?${query}` : ''}`);
}

export function loadReplayUrl({ sessionId, filename, date }) {
  const query = date ? `?date=${encodeURIComponent(date)}` : '';
  const encodedSession = encodeURIComponent(sessionId);
  const encodedFile = encodeURIComponent(filename);

  return request(`/v3/terminal-audit/replays/${encodedSession}/${encodedFile}/url${query}`);
}
