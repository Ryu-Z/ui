function responseErrorMessage(response, body) {
  if (body && !body.nonJson && typeof body === 'object') {
    if (body.message) {
      return body.message;
    }

    if (body.error) {
      return body.error;
    }
  }

  return `Request failed with status ${response.status}${response.statusText ? ` ${response.statusText}` : ''}`;
}

async function readJson(response) {
  const text = await response.text();

  if (!text) {
    return {};
  }

  const contentType = response.headers.get('content-type') || '';

  if (!contentType.includes('json')) {
    return { nonJson: true };
  }

  try {
    return JSON.parse(text);
  } catch {
    return { nonJson: true };
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
    throw new Error(responseErrorMessage(response, body));
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
