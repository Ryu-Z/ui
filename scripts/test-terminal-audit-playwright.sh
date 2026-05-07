#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "npx is required for playwright-cli" >&2
  exit 1
fi

run_pwcli() {
  local script="${CODEX_HOME:-$HOME/.codex}/skills/playwright/scripts/playwright_cli.sh"

  if [ -x "${script}" ]; then
    "${script}" "$@"
  else
    npx --yes --package @playwright/cli playwright-cli "$@"
  fi
}

server_pid=""
base_url="${BASE_URL:-}"

cleanup() {
  run_pwcli --session ta close >/dev/null 2>&1 || true
  if [ -n "${server_pid}" ]; then
    kill "${server_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ -z "${base_url}" ]; then
  yarn build >/tmp/rancher-ui-terminal-audit-test-build.log
  port="${PORT:-4173}"

  while lsof -ti "tcp:${port}" >/dev/null 2>&1; do
    port=$((port + 1))
  done

  python3 -m http.server "${port}" --bind 127.0.0.1 --directory dist >/tmp/rancher-ui-terminal-audit-test-server.log 2>&1 &
  server_pid="$!"
  base_url="http://127.0.0.1:${port}/"

  for _ in $(seq 1 50); do
    if curl -fsI "${base_url}" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
fi

code="$(
  BASE_URL="${base_url}" node - <<'NODE'
import { readFileSync } from 'node:fs';

const code = readFileSync('tests/playwright/terminal-audit-cli.js', 'utf8')
  .replace('__BASE_URL__', process.env.BASE_URL);

process.stdout.write(code);
NODE
)"

run_pwcli --session ta open about:blank
output="$(run_pwcli --session ta run-code "${code}" 2>&1)"
echo "${output}"

if echo "${output}" | grep -q '### Error'; then
  exit 1
fi
