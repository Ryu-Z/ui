<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { loadCommands, loadReplayUrl, loadStatus } from './api/terminalAudit';

const navItems = ['Global', 'Clusters', 'Apps', 'Security', 'Tools'];
const status = reactive({
  enabled: false,
  commandStorageType: '-',
  replayStorageType: '-',
});
const filters = reactive({
  sessionId: '',
  user: '',
  asset: '',
  account: '',
  input: '',
  limit: 100,
});
const replay = reactive({
  date: '',
  sessionId: '',
  filename: '',
  url: '',
  key: '',
});
const commands = ref([]);
const commandCount = ref(0);
const loadingCommands = ref(false);
const loadingStatus = ref(false);
const loadingReplay = ref(false);
const errorMessage = ref('');
const copied = ref(false);
const mobileNavOpen = ref(false);

const commandRows = computed(() => commands.value.map((row) => {
  const timestamp = row.timestamp;
  const timestampDisplay = timestamp ? new Date(timestamp * 1000).toLocaleString() : '-';

  return {
    user: row.user || '-',
    asset: row.asset || '-',
    account: row.account || '-',
    session: row.session || '-',
    input: row.input || '-',
    riskLevel: row.riskLevel ?? 0,
    timestampDisplay,
  };
}));

async function refreshStatus() {
  loadingStatus.value = true;

  try {
    const body = await loadStatus();

    status.enabled = Boolean(body.enabled);
    status.commandStorageType = body.commandStorageType || '-';
    status.replayStorageType = body.replayStorageType || '-';
  } catch (err) {
    errorMessage.value = `Failed to load terminal status: ${err.message}`;
  } finally {
    loadingStatus.value = false;
  }
}

async function searchCommands() {
  loadingCommands.value = true;
  errorMessage.value = '';

  try {
    const body = await loadCommands(filters);

    commands.value = body.data || [];
    commandCount.value = body.count || 0;
  } catch (err) {
    errorMessage.value = `Failed to load command records: ${err.message}`;
  } finally {
    loadingCommands.value = false;
  }
}

async function refreshAll() {
  await Promise.all([refreshStatus(), searchCommands()]);
}

function clearCommandFilters() {
  filters.sessionId = '';
  filters.user = '';
  filters.asset = '';
  filters.account = '';
  filters.input = '';
  filters.limit = 100;
  searchCommands();
}

async function openReplay() {
  if (!replay.sessionId || !replay.filename) {
    errorMessage.value = 'Session and file name are required.';
    return;
  }

  loadingReplay.value = true;
  replay.url = '';
  replay.key = '';
  errorMessage.value = '';

  try {
    const body = await loadReplayUrl({
      sessionId: replay.sessionId,
      filename: replay.filename,
      date: replay.date,
    });

    replay.url = body.url || '';
    replay.key = body.key || '';
  } catch (err) {
    errorMessage.value = `Failed to load replay URL: ${err.message}`;
  } finally {
    loadingReplay.value = false;
  }
}

async function copyReplayUrl() {
  if (!replay.url || !navigator.clipboard) {
    return;
  }

  await navigator.clipboard.writeText(replay.url);
  copied.value = true;
  window.setTimeout(() => {
    copied.value = false;
  }, 1600);
}

onMounted(refreshAll);
</script>

<template>
  <div id="application-shell">
    <header class="page-header">
      <nav class="clearfix responsive-nav" role="navigation">
        <a class="nav-logo logo-oss" href="/" aria-label="Rancher"></a>
        <button
          class="nav-toggle btn bg-transparent"
          type="button"
          aria-controls="primary-nav"
          aria-label="Toggle navigation"
          :aria-expanded="mobileNavOpen.toString()"
          @click="mobileNavOpen = !mobileNavOpen"
        >
          <i class="icon" :class="mobileNavOpen ? 'icon-close' : 'icon-hamburger-nav'"></i>
        </button>
        <ul id="primary-nav" class="nav-main nav-list no-inline-space" :class="{ 'is-open': mobileNavOpen }">
          <li v-for="item in navItems" :key="item" class="nav-item">
            <a class="nav-link" href="#" @click="mobileNavOpen = false">{{ item }}</a>
          </li>
          <li class="nav-item active">
            <a class="nav-link" href="#" @click="mobileNavOpen = false">Terminal</a>
          </li>
        </ul>
        <ul class="nav-user list-unstyled">
          <li class="nav-item">
            <a role="button" aria-haspopup="true" class="nav-link">
              <div class="gh-avatar">
                <div class="gh-placeholder">
                  <i class="icon icon-user"></i>
                </div>
              </div>
              <i class="icon icon-chevron-down text-muted"></i>
            </a>
          </li>
        </ul>
      </nav>
    </header>

    <main class="clearfix">
      <section class="header clearfix">
        <div class="right-buttons">
          <button class="btn btn-sm bg-default" type="button" :disabled="loadingStatus || loadingCommands" @click="refreshAll">
            <i class="icon icon-refresh icon-fw"></i>
            Refresh
          </button>
        </div>

        <h1>Terminal</h1>
      </section>

      <section v-if="errorMessage" class="banner bg-error mb-10">
        {{ errorMessage }}
      </section>

      <section class="row">
        <div class="col span-4">
          <label>Enabled</label>
          <div class="text-bold">{{ status.enabled ? 'Enabled' : 'Disabled' }}</div>
        </div>
        <div class="col span-4">
          <label>Command Storage</label>
          <div class="text-bold">{{ status.commandStorageType }}</div>
        </div>
        <div class="col span-4">
          <label>Replay Storage</label>
          <div class="text-bold">{{ status.replayStorageType }}</div>
        </div>
      </section>

      <section>
        <div class="row">
          <div class="col span-3">
            <label>Session</label>
            <input v-model="filters.sessionId" class="form-control" placeholder="Session">
          </div>
          <div class="col span-2">
            <label>User</label>
            <input v-model="filters.user" class="form-control" placeholder="User">
          </div>
          <div class="col span-2">
            <label>Asset</label>
            <input v-model="filters.asset" class="form-control" placeholder="Asset">
          </div>
          <div class="col span-2">
            <label>Account</label>
            <input v-model="filters.account" class="form-control" placeholder="Account">
          </div>
          <div class="col span-2">
            <label>Command</label>
            <input v-model="filters.input" class="form-control" placeholder="Command">
          </div>
          <div class="col span-1">
            <label>Limit</label>
            <input v-model.number="filters.limit" class="form-control" type="number" min="1" max="1000">
          </div>
        </div>

        <div class="mt-10">
          <button class="btn btn-sm bg-primary" type="button" :disabled="loadingCommands" @click="searchCommands">
            <i class="icon icon-search icon-fw"></i>
            Search
          </button>
          <button class="btn btn-sm bg-default ml-10" type="button" :disabled="loadingCommands" @click="clearCommandFilters">
            Clear
          </button>
        </div>
      </section>

      <section>
        <div class="clearfix mb-10">
          <h3 class="pull-left">Command Records ({{ commandCount }})</h3>
        </div>

        <div class="table-scroll">
          <table class="grid fixed bordered">
            <thead>
              <tr>
                <th>Time</th>
                <th>User</th>
                <th>Asset</th>
                <th>Account</th>
                <th>Session</th>
                <th>Command</th>
                <th>Risk</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in commandRows" :key="`${row.timestampDisplay}-${row.session}-${row.input}`">
                <td>{{ row.timestampDisplay }}</td>
                <td>{{ row.user }}</td>
                <td>{{ row.asset }}</td>
                <td>{{ row.account }}</td>
                <td><code>{{ row.session }}</code></td>
                <td><code>{{ row.input }}</code></td>
                <td>{{ row.riskLevel }}</td>
              </tr>
              <tr v-if="commandRows.length === 0">
                <td colspan="7" class="text-center text-muted pt-20 pb-20">No command records found.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h3>Replay</h3>
        <div class="row">
          <div class="col span-3">
            <label>Date</label>
            <input v-model="replay.date" class="form-control" placeholder="YYYY-MM-DD">
          </div>
          <div class="col span-4">
            <label>Session</label>
            <input v-model="replay.sessionId" class="form-control" placeholder="Session">
          </div>
          <div class="col span-4">
            <label>File Name</label>
            <input v-model="replay.filename" class="form-control" placeholder="session.cast.gz">
          </div>
          <div class="col span-1">
            <label>&nbsp;</label>
            <button class="btn btn-sm bg-primary" type="button" :disabled="loadingReplay" @click="openReplay">
              <i class="icon icon-external-link icon-fw"></i>
            </button>
          </div>
        </div>

        <div v-if="replay.url" class="mt-10">
          <label>Object Key</label>
          <code class="p-10 mb-10 block">{{ replay.key }}</code>
          <a class="btn btn-sm bg-default" :href="replay.url" target="_blank" rel="nofollow noreferrer">
            <i class="icon icon-download icon-fw"></i>
            Open Replay
          </a>
          <button class="btn btn-sm bg-default ml-10" type="button" @click="copyReplayUrl">
            <i class="icon icon-copy icon-fw"></i>
            {{ copied ? 'Copied' : 'Copy' }}
          </button>
        </div>
      </section>
    </main>

    <footer>
      <a href="#" class="btn btn-sm bg-transparent">v2.5-dev</a>
      <a role="button" class="btn btn-sm bg-transparent" href="https://rancher.com/docs/" target="_blank" rel="noreferrer noopener">Help</a>
      <a role="button" class="btn btn-sm bg-transparent" href="https://github.com/rancher/rancher/issues" target="_blank" rel="noreferrer noopener">Issues</a>
      <div class="pull-right">
        <a class="btn btn-sm bg-transparent" href="#">
          <i class="icon icon-download"></i>
          Download
          <i class="icon icon-chevron-down"></i>
        </a>
      </div>
    </footer>
  </div>
</template>
