<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { loadCommands, loadReplayUrl, loadStatus } from './api/terminalAudit';

const navItems = [
  {
    id: 'global',
    label: 'Global',
    href: '/g',
    columns: [
      {
        title: 'Scope',
        links: [
          { label: 'Global', href: '/g' },
          { label: 'Clusters', href: '/g/clusters' },
          { label: 'Apps', href: '/g/apps' },
        ],
      },
      {
        title: 'Clusters',
        links: [
          { label: 'All Clusters', href: '/g/clusters' },
          { label: 'Add Cluster', href: '/g/clusters/add' },
        ],
        emptyText: "You don't have any clusters",
      },
      {
        title: 'Projects',
        links: [
          { label: 'Projects/Namespaces', href: '/c/local/projects-namespaces' },
        ],
        emptyText: 'Select a cluster',
      },
    ],
  },
  {
    id: 'clusters',
    label: 'Clusters',
    href: '/g/clusters',
    menu: [
      { label: 'Clusters', href: '/g/clusters' },
      { label: 'Add Cluster', href: '/g/clusters/add' },
      { label: 'Cluster Templates', href: '/g/rke-templates' },
      { label: 'Node Drivers', href: '/n/drivers/node' },
      { label: 'Cluster Drivers', href: '/n/drivers/cluster' },
    ],
  },
  {
    id: 'apps',
    label: 'Apps',
    href: '/g/apps',
    menu: [
      { label: 'Apps', href: '/g/apps' },
      { label: 'Launch', href: '/g/apps/catalog' },
      { label: 'Manage Catalogs', href: '/g/catalog' },
    ],
  },
  {
    id: 'security',
    label: 'Security',
    href: '/g/security',
    menu: [
      { label: 'Users', href: '/g/security/accounts/users' },
      { label: 'Groups', href: '/g/security/accounts/groups' },
      { label: 'Roles', href: '/g/security/roles' },
      { label: 'Pod Security Policies', href: '/g/security/policies' },
      { label: 'Authentication', href: '/g/security/authentication' },
    ],
  },
  {
    id: 'tools',
    label: 'Tools',
    href: '/g/catalog',
    menu: [
      { label: 'Catalogs', href: '/g/catalog' },
      { label: 'Drivers', href: '/n/drivers' },
      { label: 'Global DNS Entries', href: '/g/dns/entries' },
      { label: 'Global DNS Providers', href: '/g/dns/providers' },
      { label: 'RKE Templates', href: '/g/rke-templates' },
      { label: 'Terminal', href: '/terminal-audit' },
      { divider: true },
      { label: 'Continuous Delivery', href: '/dashboard/c/local/fleet' },
    ],
  },
  {
    id: 'terminal',
    label: 'Terminal',
    href: '/terminal-audit',
    active: true,
  },
];
const userMenuItems = [
  { label: 'API & Keys', href: '/apikeys' },
  { label: 'Cloud Credentials', href: '/g/security/cloud-credentials' },
  { label: 'Node Templates', href: '/n/node-templates' },
  { label: 'Preferences', href: '/prefs' },
  { divider: true },
  { label: 'Log Out', href: '/logout' },
];
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
const navOverviewOpen = ref(false);
const openNavMenu = ref('');
const userMenuOpen = ref(false);

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
const overviewSections = computed(() => navItems.map((item) => ({
  ...item,
  links: (item.menu || item.columns?.flatMap((column) => column.links) || [{ label: item.label, href: item.href }])
    .filter((link) => !link.divider),
})));

function hasNavMenu(item) {
  return Boolean(item.menu || item.columns);
}

function closeMenus() {
  openNavMenu.value = '';
  userMenuOpen.value = false;
}

function toggleNavigation() {
  mobileNavOpen.value = !mobileNavOpen.value;
  navOverviewOpen.value = mobileNavOpen.value;
  closeMenus();
}

function toggleNavMenu(item) {
  if (!hasNavMenu(item)) {
    closeMenus();
    navOverviewOpen.value = false;
    mobileNavOpen.value = false;
    return;
  }

  userMenuOpen.value = false;
  navOverviewOpen.value = false;
  openNavMenu.value = openNavMenu.value === item.id ? '' : item.id;
}

function toggleUserMenu() {
  userMenuOpen.value = !userMenuOpen.value;
  openNavMenu.value = '';
  navOverviewOpen.value = false;
}

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
          @click="toggleNavigation"
        >
          <i class="icon" :class="mobileNavOpen ? 'icon-close' : 'icon-hamburger-nav'"></i>
        </button>
        <ul id="primary-nav" class="nav-main nav-list no-inline-space" :class="{ 'is-open': mobileNavOpen }">
          <li
            v-for="item in navItems"
            :key="item.id"
            class="nav-item"
            :class="{ active: item.active, open: openNavMenu === item.id, 'has-menu': hasNavMenu(item) }"
          >
            <button
              v-if="hasNavMenu(item)"
              class="nav-link nav-menu-button"
              type="button"
              aria-haspopup="true"
              :aria-expanded="(openNavMenu === item.id).toString()"
              @click="toggleNavMenu(item)"
            >
              {{ item.label }}
              <i class="icon icon-chevron-down text-muted"></i>
            </button>
            <a
              v-else
              class="nav-link"
              :href="item.href"
              @click="closeMenus"
            >
              {{ item.label }}
            </a>

            <div v-if="item.columns && openNavMenu === item.id" class="nav-dropdown nav-project-menu" role="menu">
              <div v-for="column in item.columns" :key="column.title" class="nav-dropdown-column">
                <div class="nav-dropdown-title">{{ column.title }}</div>
                <a
                  v-for="link in column.links"
                  :key="link.href"
                  class="nav-dropdown-link"
                  :href="link.href"
                  role="menuitem"
                  @click="closeMenus"
                >
                  {{ link.label }}
                </a>
                <div v-if="column.emptyText" class="nav-dropdown-empty">{{ column.emptyText }}</div>
              </div>
            </div>

            <ul v-if="item.menu && openNavMenu === item.id" class="nav-dropdown nav-dropdown-list" role="menu">
              <li v-for="(link, index) in item.menu" :key="link.href || `divider-${index}`">
                <div v-if="link.divider" class="nav-divider"></div>
                <a
                  v-else
                  class="nav-dropdown-link"
                  :href="link.href"
                  role="menuitem"
                  @click="closeMenus"
                >
                  {{ link.label }}
                </a>
              </li>
            </ul>
          </li>
        </ul>
        <ul class="nav-user list-unstyled" :class="{ open: userMenuOpen }">
          <li class="nav-item">
            <a
              role="button"
              aria-haspopup="true"
              class="nav-link"
              href="#"
              :aria-expanded="userMenuOpen.toString()"
              @click.prevent="toggleUserMenu"
            >
              <div class="gh-avatar">
                <div class="gh-placeholder">
                  <i class="icon icon-user"></i>
                </div>
              </div>
              <i class="icon icon-chevron-down text-muted"></i>
            </a>
            <ul v-if="userMenuOpen" class="nav-dropdown nav-dropdown-list user-menu" role="menu">
              <li class="user-menu-header">
                <div class="gh-avatar">
                  <div class="gh-placeholder">
                    <i class="icon icon-user"></i>
                  </div>
                </div>
                <span>Local User</span>
              </li>
              <li v-for="(item, index) in userMenuItems" :key="item.href || `user-divider-${index}`">
                <div v-if="item.divider" class="nav-divider"></div>
                <a
                  v-else
                  class="nav-dropdown-link"
                  :href="item.href"
                  role="menuitem"
                  @click="closeMenus"
                >
                  {{ item.label }}
                </a>
              </li>
            </ul>
          </li>
        </ul>
        <div v-if="navOverviewOpen" class="nav-overview" role="menu">
          <section v-for="section in overviewSections" :key="section.id" class="nav-overview-section">
            <div class="nav-dropdown-title">{{ section.label }}</div>
            <a
              v-for="link in section.links"
              :key="`${section.id}-${link.href || link.label}`"
              class="nav-dropdown-link"
              :href="link.href"
              role="menuitem"
              @click="closeMenus"
            >
              {{ link.label }}
            </a>
          </section>
        </div>
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
