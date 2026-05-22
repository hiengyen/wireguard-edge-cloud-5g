<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Hosts</h1>
      <div style="display:flex;gap:12px;align-items:center">
        <button class="btn btn-primary" @click="openModal" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">add</span>
          Register Host
        </button>
        <button class="btn btn-secondary" @click="hostStore.fetchHosts()" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">refresh</span>
          Refresh
        </button>
      </div>
    </div>

    <!-- Host table -->
    <div v-if="hostStore.loading && hostStore.hosts.length === 0" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="hostStore.hosts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">dns</span>
      <h3>No Hosts Registered</h3>
      <p>Click <strong>Register Host</strong> above to add a WireGuard host to PeerSight.</p>
    </div>

    <div v-else class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>ID</th>
            <th>Agent</th>
            <th>Last Ping</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="host in hostStore.hosts" :key="host.id"
              @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
            <td style="font-weight:600">
              <div style="display:flex;align-items:center;gap:8px">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-accent)">computer</span>
                {{ host.name }}
              </div>
            </td>
            <td><code class="mono-id">{{ shortId(host.id) }}</code></td>
            <td><code style="font-size:var(--font-size-xs);color:var(--color-text-muted)">{{ host.agent_version || '—' }}</code></td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">{{ formatTime(host.last_ping) }}</td>
            <td>
              <span class="badge" :class="isOnline(host) ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ isOnline(host) ? 'Online' : 'Offline' }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- ── Modal ── -->
    <div v-if="showModal" class="modal-overlay" @click.self="closeModal">
      <div class="modal-card">

        <!-- Header -->
        <div class="modal-header">
          <h3>
            <span class="material-symbols-outlined" style="font-size:20px;vertical-align:middle;margin-right:6px">dns</span>
            {{ step === 'form' ? 'Register New Host' : step === 'token' ? 'Setup Agent' : 'Host Created' }}
          </h3>
          <button class="modal-close" @click="closeModal">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <!-- Step 1: Form -->
        <div v-if="step === 'form'" class="modal-body">
          <p class="hint">Enter a name for this WireGuard host. A unique Host ID will be generated.</p>
          <div class="form-group">
            <label for="host-name">Host Name</label>
            <input
              id="host-name"
              type="text"
              v-model="newHostName"
              placeholder="e.g. cloud-gateway  or  edge-orangepi-01"
              class="form-control"
              @keyup.enter="handleCreate"
              autofocus
            />
          </div>
          <div class="modal-footer">
            <button class="btn btn-secondary" @click="closeModal">Cancel</button>
            <button class="btn btn-primary" :disabled="!newHostName.trim() || hostStore.loading" @click="handleCreate">
              <span v-if="hostStore.loading" class="spinner-sm"></span>
              <span v-else>Create Host</span>
            </button>
          </div>
        </div>

        <!-- Step 2: Host created — show ID, then prompt token -->
        <div v-if="step === 'created'" class="modal-body">
          <div class="success-banner">
            <span class="material-symbols-outlined">check_circle</span>
            <span>Host <strong>{{ createdHost.name }}</strong> registered successfully!</span>
          </div>

          <div class="info-row">
            <span class="info-label">Host ID</span>
            <div class="copy-row">
              <code>{{ createdHost.id }}</code>
              <button class="copy-btn" @click="copy(createdHost.id, 'hostId')" :title="copied.hostId ? 'Copied!' : 'Copy'">
                <span class="material-symbols-outlined">{{ copied.hostId ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <p class="hint" style="margin-top:var(--space-lg)">
            Next: generate a long-lived <strong>Agent Token</strong> to authenticate the
            <code>peersight-agent</code> daemon on this host.
          </p>

          <div class="modal-footer">
            <button class="btn btn-secondary" @click="closeModal">Skip for now</button>
            <button class="btn btn-primary" :disabled="tokenLoading" @click="handleGenerateToken">
              <span v-if="tokenLoading" class="spinner-sm"></span>
              <span v-else style="display:flex;align-items:center;gap:6px">
                <span class="material-symbols-outlined" style="font-size:16px">key</span>
                Generate Agent Token
              </span>
            </button>
          </div>
        </div>

        <!-- Step 3: Show token + install command -->
        <div v-if="step === 'token'" class="modal-body">
          <div class="success-banner">
            <span class="material-symbols-outlined">key</span>
            <span>Agent token generated — valid for <strong>10 years</strong></span>
          </div>

          <div class="info-row">
            <span class="info-label">Host ID</span>
            <div class="copy-row">
              <code class="truncate">{{ createdHost.id }}</code>
              <button class="copy-btn" @click="copy(createdHost.id, 'hostId')" :title="copied.hostId ? 'Copied!' : 'Copy'">
                <span class="material-symbols-outlined">{{ copied.hostId ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="info-row">
            <span class="info-label">Agent Token</span>
            <div class="copy-row">
              <code class="truncate">{{ agentToken }}</code>
              <button class="copy-btn" @click="copy(agentToken, 'token')" :title="copied.token ? 'Copied!' : 'Copy'">
                <span class="material-symbols-outlined">{{ copied.token ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="cmd-block-wrap">
            <div class="cmd-label">
              <span class="material-symbols-outlined" style="font-size:14px">terminal</span>
              Run on the host to install peersight-agent
            </div>
            <div class="cmd-block">
              <pre>{{ installCmd }}</pre>
              <button class="copy-btn cmd-copy" @click="copy(installCmd, 'cmd')" :title="copied.cmd ? 'Copied!' : 'Copy'">
                <span class="material-symbols-outlined">{{ copied.cmd ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="warning-note">
            <span class="material-symbols-outlined">warning</span>
            Save this token now — it will not be shown again.
          </div>

          <div class="modal-footer">
            <button class="btn btn-primary" @click="closeModal">Done</button>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { shortId, isOnline, formatTime } from '@/utils/format.js'

const hostStore = useHostStore()
onMounted(() => hostStore.fetchHosts())

// Modal state
const showModal   = ref(false)
const step        = ref('form')     // 'form' | 'created' | 'token'
const newHostName = ref('')
const createdHost = ref(null)
const agentToken  = ref('')
const tokenLoading = ref(false)
const copied = ref({ hostId: false, token: false, cmd: false })

const installCmd = computed(() => {
  if (!createdHost.value || !agentToken.value) return ''
  return `sudo PEERSIGHT_API_URL="http://127.0.0.1:4000" \\
     PEERSIGHT_HOST_ID="${createdHost.value.id}" \\
     PEERSIGHT_TOKEN="${agentToken.value}" \\
     ~/wireguard-edge-cloud-5g/peersight/install-agent.sh`
})

function openModal() {
  step.value = 'form'
  newHostName.value = ''
  createdHost.value = null
  agentToken.value = ''
  showModal.value = true
}

function closeModal() {
  showModal.value = false
}

async function handleCreate() {
  if (!newHostName.value.trim()) return
  const host = await hostStore.createHost(newHostName.value.trim())
  if (host) {
    createdHost.value = host
    step.value = 'created'
  }
}

async function handleGenerateToken() {
  tokenLoading.value = true
  try {
    const token = await hostStore.generateAgentToken()
    if (token) {
      agentToken.value = token
      step.value = 'token'
    }
  } finally {
    tokenLoading.value = false
  }
}

function copy(value, key) {
  if (!value) return
  navigator.clipboard.writeText(value)
  copied.value[key] = true
  setTimeout(() => { copied.value[key] = false }, 2000)
}
</script>

<style scoped>
/* ── Table ── */
.mono-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}

/* ── Modal overlay ── */
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,.72);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-card {
  background: var(--color-bg-card, #1e1e24);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-lg, 14px);
  width: 100%;
  max-width: 540px;
  padding: var(--space-xl, 24px);
  box-shadow: 0 12px 48px rgba(0,0,0,.6);
  animation: pop .22s cubic-bezier(.16,1,.3,1);
}

@keyframes pop {
  from { transform: scale(.96) translateY(8px); opacity: 0; }
  to   { transform: scale(1)   translateY(0);   opacity: 1; }
}

/* ── Modal header ── */
.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-bottom: var(--space-md, 14px);
  border-bottom: 1px solid var(--color-border, #2d2d34);
  margin-bottom: var(--space-lg, 18px);
}
.modal-header h3 { margin: 0; font-size: 17px; }

.modal-close {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 4px;
  border-radius: 50%;
  display: flex;
  transition: background .15s, color .15s;
}
.modal-close:hover { background: rgba(255,255,255,.06); color: var(--color-text); }

/* ── Modal body ── */
.modal-body { display: flex; flex-direction: column; gap: var(--space-md, 14px); }

.hint {
  font-size: var(--font-size-sm, 13px);
  color: var(--color-text-secondary);
  margin: 0;
  line-height: 1.5;
}

/* ── Form ── */
.form-group label {
  display: block;
  font-size: var(--font-size-sm);
  font-weight: 600;
  margin-bottom: 6px;
}
.form-control {
  width: 100%;
  padding: 10px 14px;
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px);
  color: var(--color-text);
  font-size: var(--font-size-sm);
  transition: border-color .2s, box-shadow .2s;
  box-sizing: border-box;
}
.form-control:focus {
  outline: none;
  border-color: var(--color-accent, #5865f2);
  box-shadow: 0 0 0 2px rgba(88,101,242,.25);
}

/* ── Success banner ── */
.success-banner {
  display: flex;
  align-items: center;
  gap: 10px;
  background: rgba(34,197,94,.08);
  border: 1px solid rgba(34,197,94,.3);
  border-radius: var(--radius-md, 8px);
  padding: 12px 14px;
  font-size: var(--font-size-sm);
  color: #4ade80;
}
.success-banner .material-symbols-outlined { font-size: 20px; }

/* ── Info rows ── */
.info-row { display: flex; flex-direction: column; gap: 5px; }
.info-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--color-text-muted);
}

/* ── Copy row ── */
.copy-row {
  display: flex;
  align-items: center;
  gap: 8px;
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px);
  padding: 8px 12px;
}
.copy-row code {
  flex: 1;
  font-family: monospace;
  font-size: 12px;
  color: var(--color-accent, #5865f2);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.copy-row .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

/* ── Copy button ── */
.copy-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--color-text-muted);
  display: flex;
  align-items: center;
  padding: 2px;
  border-radius: 4px;
  flex-shrink: 0;
  transition: color .15s;
}
.copy-btn:hover { color: var(--color-accent); }
.copy-btn .material-symbols-outlined { font-size: 16px; }

/* ── Install command block ── */
.cmd-block-wrap { display: flex; flex-direction: column; gap: 6px; }
.cmd-label {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--color-text-muted);
}
.cmd-block {
  position: relative;
  background: #0a0a0f;
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px);
  padding: 12px 40px 12px 14px;
}
.cmd-block pre {
  margin: 0;
  font-family: monospace;
  font-size: 11px;
  color: #a3e635;
  white-space: pre-wrap;
  word-break: break-all;
  line-height: 1.6;
}
.cmd-copy {
  position: absolute;
  top: 8px;
  right: 8px;
}

/* ── Warning ── */
.warning-note {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: #fbbf24;
  background: rgba(251,191,36,.07);
  border: 1px solid rgba(251,191,36,.25);
  border-radius: var(--radius-md, 8px);
  padding: 10px 14px;
}
.warning-note .material-symbols-outlined { font-size: 18px; }

/* ── Footer ── */
.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  padding-top: var(--space-md, 14px);
  border-top: 1px solid var(--color-border, #2d2d34);
  margin-top: var(--space-sm, 8px);
}

/* ── Spinner ── */
.spinner-sm {
  display: inline-block;
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255,255,255,.2);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin .6s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
