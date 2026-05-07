#!/usr/bin/env bash
set -euo pipefail

session="${PLAYWRIGHT_CLI_SESSION:-ta-cli}"
base_url="${BASE_URL:-http://127.0.0.1:8000/}"
base_url_was_default="false"
if [ -z "${BASE_URL:-}" ]; then
  base_url_was_default="true"
fi
mock_file="${MOCK_FILE:-tests/playwright/terminal-audit-mocks.json}"
report_dir="${REPORT_DIR:-output/playwright/terminal-audit-cli}"
images_dir="${report_dir}/images"
steps_file="${report_dir}/steps.jsonl"
summary_file="${report_dir}/summary.json"
report_file="${report_dir}/report.html"
server_pid=""
current_log_file=""

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

cleanup() {
  run_pwcli --session "${session}" close >/dev/null 2>&1 || true
  if [ -n "${server_pid}" ]; then
    kill "${server_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

prepare_report_dir() {
  rm -rf "${report_dir}"
  mkdir -p "${images_dir}"
  : >"${steps_file}"
}

json_response() {
  node - "${mock_file}" "$1" <<'NODE'
import { readFileSync } from 'node:fs';

const [, , file, key] = process.argv;
const mocks = JSON.parse(readFileSync(file, 'utf8'));

process.stdout.write(JSON.stringify(mocks.responses[key]));
NODE
}

text_response() {
  node - "${mock_file}" "$1" <<'NODE'
import { readFileSync } from 'node:fs';

const [, , file, key] = process.argv;
const mocks = JSON.parse(readFileSync(file, 'utf8'));

process.stdout.write(String(mocks.responses[key]));
NODE
}

js_string() {
  node - "$1" <<'NODE'
process.stdout.write(JSON.stringify(process.argv[2]));
NODE
}

append_log() {
  if [ -n "${current_log_file}" ]; then
    printf '%s\n' "$1" >>"${current_log_file}"
  fi
}

start_step_log() {
  local id="$1"

  current_log_file="${report_dir}/${id}.log"
  : >"${current_log_file}"
}

run_logged() {
  local label="$1"
  shift
  local output

  append_log "### ${label}"
  append_log "\$ playwright-cli --session ${session} $*"

  if ! output="$(run_pwcli --session "${session}" "$@" 2>&1)"; then
    append_log "${output}"
    echo "${output}" >&2
    exit 1
  fi

  append_log "${output}"
  append_log ""

  if grep -q '^### Error' <<<"${output}"; then
    echo "${output}" >&2
    exit 1
  fi
}

eval_raw() {
  local output

  if ! output="$(run_pwcli --session "${session}" eval "$1" 2>&1 | tr -d '\r')"; then
    echo "${output}" >&2
    exit 1
  fi

  if grep -q '^### Error' <<<"${output}"; then
    echo "${output}" >&2
    exit 1
  fi

  printf '%s\n' "${output}" | awk '
    /^### Result/ {
      getline
      print
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  '
}

assert_eval() {
  local expression="$1"
  local message="$2"
  local result

  result="$(eval_raw "${expression}")"
  if [ "${result}" != "true" ]; then
    append_log "ASSERT failed: ${message}"
    append_log "Expression: ${expression}"
    append_log "Actual: ${result}"
    echo "Assertion failed: ${message}" >&2
    exit 1
  fi

  append_log "ASSERT ok: ${message}"
}

wait_for_text() {
  local text="$1"
  local message="${2:-Timed out waiting for text: ${text}}"
  local quoted

  quoted="$(js_string "${text}")"
  for _ in $(seq 1 60); do
    if [ "$(eval_raw "document.body.innerText.includes(${quoted})")" = "true" ]; then
      append_log "WAIT ok: ${text}"
      return
    fi
    sleep 0.2
  done

  append_log "WAIT failed: ${text}"
  echo "${message}" >&2
  exit 1
}

add_step() {
  node - "${steps_file}" "$1" "$2" "$3" "$4" "$5" "$6" <<'NODE'
import { appendFileSync } from 'node:fs';

const [, , file, id, title, status, screenshot, log, detail] = process.argv;

appendFileSync(file, `${JSON.stringify({
  id,
  title,
  status,
  screenshot,
  log,
  detail,
})}\n`);
NODE
}

capture_step() {
  local id="$1"
  local title="$2"
  local detail="$3"
  local image_file="images/${id}.png"
  local log_file="${id}.log"

  run_logged "页面快照" snapshot
  run_logged "截图" screenshot --filename "${report_dir}/${image_file}" --full-page
  add_step "${id}" "${title}" "ok" "${image_file}" "${log_file}" "${detail}"
}

route_json() {
  local pattern="$1"
  local response_key="$2"
  local body

  body="$(json_response "${response_key}")"
  run_logged "Mock ${pattern}" route "${pattern}" --content-type "application/json" --body "${body}"
}

route_html_error() {
  local pattern="$1"
  local body

  body="$(text_response html404)"
  run_logged "Mock ${pattern} as HTML 404" route "${pattern}" --status 404 --content-type "text/html" --body "${body}"
}

ensure_base_url() {
  if curl -fsI "${base_url}" >/dev/null 2>&1; then
    return
  fi

  if [ "${base_url_was_default}" != "true" ]; then
    echo "BASE_URL is not reachable: ${base_url}" >&2
    exit 1
  fi

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
      return
    fi
    sleep 0.2
  done

  echo "Local static server did not become ready: ${base_url}" >&2
  exit 1
}

install_mock_routes() {
  route_json "**/v3/terminal-audit/status" status
  route_json "**/v3/terminal-audit/commands**" commandsDefault
  route_json "**/v3/terminal-audit/commands?sessionId=**" commandsFiltered
  route_json "**/v3/terminal-audit/replays/**/url**" replayUrl
}

write_summary() {
  node - "${mock_file}" "${summary_file}" "${base_url}" "${session}" "${server_pid}" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';

const [, , mockFile, summaryFile, baseUrl, session, serverPid] = process.argv;
const mocks = JSON.parse(readFileSync(mockFile, 'utf8'));

writeFileSync(summaryFile, JSON.stringify({
  generatedAt: new Date().toISOString(),
  baseUrl,
  session,
  mode: 'playwright-cli headless + native route mocks',
  server: serverPid ? `started local static server pid ${serverPid}` : 'reused existing server',
  routes: mocks.routes,
}, null, 2));
NODE
}

generate_report() {
  node - "${steps_file}" "${summary_file}" "${report_file}" <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const [, , stepsFile, summaryFile, reportFile] = process.argv;
const reportDir = dirname(reportFile);
const steps = readFileSync(stepsFile, 'utf8')
  .trim()
  .split('\n')
  .filter(Boolean)
  .map((line) => JSON.parse(line));
const summary = JSON.parse(readFileSync(summaryFile, 'utf8'));
const escapeHtml = (value) => String(value)
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;');

function imageDataUri(relativePath) {
  const absolutePath = join(reportDir, relativePath);
  const data = readFileSync(absolutePath).toString('base64');

  return `data:image/png;base64,${data}`;
}

function logText(relativePath) {
  return readFileSync(join(reportDir, relativePath), 'utf8').trimEnd();
}

const routeLines = summary.routes
  .map((route) => `${route.method} ${route.pattern} -> ${route.response}`)
  .join('\n');
const stepCards = steps.map((step, index) => `
      <section class="step-card">
        <h3>${index + 1}. ${escapeHtml(step.title)}</h3>
        <p><strong>状态：</strong><span class="ok">${escapeHtml(step.status)}</span></p>
        <p><strong>截图：</strong><a href="${escapeHtml(step.screenshot)}">${escapeHtml(step.screenshot)}</a></p>
        <img src="${imageDataUri(step.screenshot)}" alt="${escapeHtml(step.title)}">
        <pre><code>${escapeHtml(logText(step.log))}</code></pre>
      </section>`).join('');

const html = `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <title>Playwright CLI 前端自动化报告</title>
    <style>
      :root {
        color: #111827;
        background: #f5f7fb;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      body {
        margin: 0;
      }
      main {
        padding: 22px;
      }
      h1 {
        font-size: 22px;
        margin: 0 0 18px;
      }
      h2 {
        font-size: 18px;
        margin: 22px 0 12px;
      }
      h3 {
        font-size: 15px;
        margin: 0 0 14px;
      }
      p {
        font-size: 13px;
        margin: 8px 0;
      }
      a {
        color: #1d4ed8;
      }
      .summary,
      .step-card {
        background: #fff;
        border: 1px solid #e5e7eb;
        border-radius: 8px;
        box-shadow: 0 8px 24px rgba(15, 23, 42, 0.06);
        margin-bottom: 18px;
        padding: 18px;
      }
      .summary dl {
        display: grid;
        grid-template-columns: max-content 1fr;
        gap: 7px 12px;
        margin: 0;
      }
      .summary dt,
      .summary dd {
        font-size: 13px;
        margin: 0;
      }
      .summary dt {
        font-weight: 700;
      }
      .routes {
        white-space: pre-wrap;
      }
      .ok {
        color: #047857;
        font-weight: 700;
      }
      img {
        border: 1px solid #d1d5db;
        border-radius: 4px;
        display: block;
        margin-top: 12px;
        max-width: 700px;
        width: 52vw;
      }
      pre {
        background: #08111f;
        border-radius: 7px;
        color: #dbeafe;
        font-size: 11px;
        line-height: 1.45;
        margin: 14px 0 0;
        max-height: 360px;
        overflow: auto;
        padding: 14px;
        white-space: pre-wrap;
      }
      code {
        font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>Playwright CLI 前端自动化报告</h1>
      <section class="summary">
        <dl>
          <dt>时间：</dt><dd>${escapeHtml(summary.generatedAt)}</dd>
          <dt>前端地址：</dt><dd>${escapeHtml(summary.baseUrl)}</dd>
          <dt>Session：</dt><dd>${escapeHtml(summary.session)}</dd>
          <dt>模式：</dt><dd>${escapeHtml(summary.mode)}</dd>
          <dt>后端 Mock：</dt><dd class="routes">${escapeHtml(routeLines)}</dd>
        </dl>
      </section>
      <h2>步骤记录</h2>
      ${stepCards}
    </main>
  </body>
</html>`;

writeFileSync(reportFile, html);
NODE
}

main() {
  prepare_report_dir
  ensure_base_url
  write_summary

  start_step_log "01-initial-load"
  run_logged "启动无头浏览器" open about:blank
  install_mock_routes
  run_logged "打开终端审计页面" goto "${base_url}"
  wait_for_text "Command Records (2)" "Initial command list did not render"
  assert_eval "document.body.innerText.includes('Enabled') && document.body.innerText.includes('s3') && document.body.innerText.includes('kubectl get pods -A')" "初始状态和命令列表渲染成功"
  assert_eval "Math.abs(document.querySelector('.page-header nav').getBoundingClientRect().left - document.querySelector('main').getBoundingClientRect().left) < 1" "主内容与导航栏左侧对齐"
  run_logged "打开 Tools 导航菜单" click 'button.nav-menu-button:has-text("Tools")'
  assert_eval "document.querySelector('.nav-dropdown')?.innerText.includes('Catalogs') && document.querySelector('.nav-dropdown')?.innerText.includes('Terminal')" "Tools 二级菜单可点击展开"
  run_logged "打开用户菜单" click '.nav-user .nav-link'
  assert_eval "document.querySelector('.user-menu')?.innerText.includes('API & Keys') && document.querySelector('.user-menu')?.innerText.includes('Preferences')" "用户菜单可点击展开"
  run_logged "关闭用户菜单" click '.nav-user .nav-link'
  capture_step "01-initial-load" "初始加载" "验证 status 与 commands 默认列表 mock。"

  start_step_log "02-mobile-nav"
  run_logged "切换到窄屏视口" resize 534 993
  assert_eval "document.documentElement.scrollWidth <= window.innerWidth + 1" "窄屏页面没有横向溢出"
  assert_eval "getComputedStyle(document.querySelector('.nav-toggle')).display !== 'none' && getComputedStyle(document.querySelector('.nav-main')).display === 'none' && document.querySelector('.page-header nav').getBoundingClientRect().height <= 60" "窄屏导航默认折叠为紧凑顶栏"
  run_logged "展开窄屏导航" click '.nav-toggle'
  assert_eval "getComputedStyle(document.querySelector('.nav-main')).display !== 'none' && document.querySelector('.nav-overview')?.innerText.includes('Global DNS Entries') && document.querySelector('.page-header nav').getBoundingClientRect().height < 760" "窄屏导航点击后展开全量菜单且高度受控"
  capture_step "02-mobile-nav" "窄屏导航" "验证 534px 视口下导航默认折叠，展开后菜单高度受控且页面没有横向溢出。"
  run_logged "收起窄屏导航" click '.nav-toggle'
  run_logged "恢复桌面视口" resize 1440 1100

  start_step_log "03-filtered-search"
  run_logged "输入 Session 筛选" fill 'section:has(button:has-text("Search")) input[placeholder="Session"]' "sess/one"
  run_logged "输入 User 筛选" fill 'section:has(button:has-text("Search")) input[placeholder="User"]' "alice@example.com"
  run_logged "输入 Asset 筛选" fill 'section:has(button:has-text("Search")) input[placeholder="Asset"]' "prod-eks-node-a"
  run_logged "输入 Account 筛选" fill 'section:has(button:has-text("Search")) input[placeholder="Account"]' "root"
  run_logged "输入 Command 筛选" fill 'section:has(button:has-text("Search")) input[placeholder="Command"]' "kubectl get pods"
  run_logged "触发查询" eval "(() => { Array.from(document.querySelectorAll('button')).find((button) => button.innerText.includes('Search')).click(); return true; })()"
  wait_for_text "Command Records (1)" "Filtered command list did not render"
  assert_eval "document.body.innerText.includes('alice@example.com') && document.body.innerText.includes('sess/one') && document.body.innerText.includes('kubectl get pods')" "筛选结果渲染成功"
  run_logged "检查网络请求" requests
  assert_eval "performance.getEntriesByType('resource').some((entry) => entry.name.includes('sessionId=sess%2Fone') && entry.name.includes('user=alice%40example.com') && entry.name.includes('input=kubectl%20get%20pods'))" "commands 请求包含 URL 编码后的查询参数"
  capture_step "03-filtered-search" "筛选查询" "验证 commands 查询参数触发 filtered mock。"

  start_step_log "04-clear-filters"
  run_logged "清空筛选" eval "(() => { Array.from(document.querySelectorAll('button')).find((button) => button.innerText.includes('Clear')).click(); return true; })()"
  wait_for_text "Command Records (2)" "Command list did not reset after clearing filters"
  assert_eval "!document.body.innerText.includes('alice@example.com') && document.body.innerText.includes('prod-docker-host-b')" "清空后恢复默认命令列表"
  capture_step "04-clear-filters" "清空筛选" "验证 Clear 会移除筛选条件并重新加载默认 commands mock。"

  start_step_log "05-replay-url"
  run_logged "输入回放日期" fill 'section:has(h3:has-text("Replay")) input[placeholder="YYYY-MM-DD"]' "2026-05-07"
  run_logged "输入回放 Session" fill 'section:has(h3:has-text("Replay")) input[placeholder="Session"]' "sess/replay"
  run_logged "输入回放文件名" fill 'section:has(h3:has-text("Replay")) input[placeholder="session.cast.gz"]' "session one.cast.gz"
  run_logged "请求回放地址" eval "(() => { Array.from(document.querySelectorAll('section')).find((section) => section.querySelector('h3')?.innerText.includes('Replay')).querySelector('button.bg-primary').click(); return true; })()"
  wait_for_text "terminal-audit/2026-05-07/session-one.cast.gz" "Replay object key did not render"
  assert_eval "document.body.innerText.includes('Open Replay') && document.body.innerText.includes('Copy')" "回放地址操作按钮渲染成功"
  run_logged "检查网络请求" requests
  assert_eval "performance.getEntriesByType('resource').some((entry) => entry.name.includes('/v3/terminal-audit/replays/sess%2Freplay/session%20one.cast.gz/url?date=2026-05-07'))" "replay 请求包含编码后的 path 与 date 查询参数"
  capture_step "05-replay-url" "回放地址" "验证 replay signed URL mock。"

  start_step_log "06-html-error"
  run_logged "清理已有 Mock" unroute
  route_html_error "**/v3/terminal-audit/status"
  route_html_error "**/v3/terminal-audit/commands**"
  run_logged "打开 HTML 错误场景" goto "${base_url}?html-error"
  wait_for_text "Request failed with status 404" "HTML error banner did not render"
  assert_eval "document.querySelector('.banner.bg-error').innerText.includes('Request failed with status 404') && !document.querySelector('.banner.bg-error').innerText.includes('<!DOCTYPE')" "HTML 后端错误被压缩成简洁 HTTP 错误"
  capture_step "06-html-error" "非 JSON 错误" "验证后端返回 HTML 404 时不泄露响应体。"

  generate_report
  echo "playwright-cli browser mock verification passed"
  echo "Report: ${report_file}"
}

main "$@"
