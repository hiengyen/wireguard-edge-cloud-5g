<template>
  <div>
    <!-- Back + Header -->
    <div class="page-header">
      <div style="display:flex;align-items:center;gap:var(--space-md)">
        <router-link to="/hosts" class="btn btn-secondary" style="padding:6px 10px">
          <span class="material-symbols-outlined" style="font-size:18px">arrow_back</span>
        </router-link>
        <div>
          <!-- Inline Name Editing -->
          <div v-if="editingName" style="display:flex;align-items:center;gap:8px">
            <input
              v-model="editNameVal"
              class="inline-input-lg"
              @keyup.enter="saveName"
              @keyup.escape="cancelRename"
              ref="nameInput"
            />
            <button class="icon-btn green-btn" @click="saveName" title="Save">
              <span class="material-symbols-outlined">check</span>
            </button>
            <button class="icon-btn" @click="cancelRename" title="Cancel">
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>
          <div v-else style="display:flex;align-items:center;gap:8px">
            <h1 class="page-title">{{ host?.name || t('common.loading') }}</h1>
            <button v-if="host" class="icon-btn-edit" @click="startRename" :title="t('hosts.rename')">
              <span class="material-symbols-outlined" style="font-size:18px">edit</span>
            </button>
          </div>
          <code v-if="host" class="host-id">{{ host.id }}</code>
        </div>
      </div>
      <div style="display:flex;gap:var(--space-sm);align-items:center">
        <span v-if="host" class="badge" :class="isOnline(host) ? 'online' : 'offline'">
          <span class="badge-dot"></span>
          {{ isOnline(host) ? t('common.online') : t('common.offline') }}
        </span>
        <button class="btn btn-secondary" @click="refreshAll">
          <span class="material-symbols-outlined">refresh</span> {{ t('common.refresh') }}
        </button>
        <button v-if="host" class="btn btn-secondary" @click="openTokenModal" :title="t('settings.generateToken')" style="display:flex;align-items:center;gap:4px">
          <span class="material-symbols-outlined" style="font-size:18px">key</span> Token
        </button>
        <button v-if="host" class="btn btn-secondary" @click="confirmDelete" :title="t('common.delete')" style="display:flex;align-items:center;gap:4px;color:var(--color-danger);border-color:rgba(239,68,68,0.2)">
          <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-danger)">delete</span> {{ t('common.delete') }}
        </button>
      </div>
    </div>

    <!-- Host Info Cards -->
    <div v-if="host" class="stat-grid" style="margin-bottom:var(--space-xl)">
      <div class="stat-card">
        <div class="stat-icon blue"><span class="material-symbols-outlined">memory</span></div>
        <div>
          <div class="stat-value">{{ host.agent_version || '—' }}</div>
          <div class="stat-label">Agent Version</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon green"><span class="material-symbols-outlined">lan</span></div>
        <div>
          <div class="stat-value">{{ interfaces.length }}</div>
          <div class="stat-label">{{ t('hosts.interfaces') }}</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon yellow"><span class="material-symbols-outlined">hub</span></div>
        <div>
          <div class="stat-value">{{ endpoints.length }}</div>
          <div class="stat-label">{{ t('peers.endpointsList') }}</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon red"><span class="material-symbols-outlined">schedule</span></div>
        <div>
          <div class="stat-value">{{ formatTime(host.last_ping) }}</div>
          <div class="stat-label">{{ t('hosts.lastSeen') }}</div>
        </div>
      </div>
    </div>

    <!-- Tabs -->
    <div class="tabs">
      <button v-for="t in tabs" :key="t.id" class="tab" :class="{ active: activeTab === t.id }" @click="activeTab = t.id">
        <span class="material-symbols-outlined" style="font-size:18px">{{ t.icon }}</span>
        {{ t.label }}
        <span v-if="t.count > 0" class="tab-count">{{ t.count }}</span>
      </button>
    </div>

    <!-- Interfaces Tab -->
    <div v-if="activeTab === 'interfaces'" class="card">
      <div v-if="interfaces.length === 0" class="empty-state">
        <span class="material-symbols-outlined">lan</span>
        <h3>{{ t('hosts.noInterfaces') }}</h3>
        <p>No WireGuard interfaces reported by the agent yet.</p>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>{{ t('hosts.hostName') }}</th>
            <th>Address</th>
            <th>Listen Port</th>
            <th>MTU</th>
            <th>DNS</th>
            <th>{{ t('common.status') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="iface in interfaces" :key="iface.id">
            <td style="font-weight:600">
              <div style="display:flex;align-items:center;gap:8px">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-accent)">settings_ethernet</span>
                {{ iface.name }}
              </div>
            </td>
            <td><code class="mono-val">{{ iface.address || '—' }}</code></td>
            <td>{{ iface.listen_port || '—' }}</td>
            <td>{{ iface.mtu || 'auto' }}</td>
            <td><code class="mono-val">{{ iface.dns || '—' }}</code></td>
            <td>
              <span class="badge" :class="iface.up ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ iface.up ? 'Up' : 'Down' }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Endpoints Tab -->
    <div v-if="activeTab === 'endpoints'" class="card">
      <div v-if="endpoints.length === 0" class="empty-state">
        <span class="material-symbols-outlined">hub</span>
        <h3>{{ t('peers.noEndpoints') }}</h3>
        <p>No peer connections discovered yet.</p>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Peer IP</th>
            <th>Port</th>
            <th>Allowed IPs</th>
            <th>Keepalive</th>
            <th>Last Handshake</th>
            <th>RX / TX</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="ep in endpoints" :key="ep.id">
            <td style="font-weight:500">
              <div style="display:flex;align-items:center;gap:8px">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-success)">swap_horiz</span>
                <code class="mono-val">{{ ep.ip || '—' }}</code>
              </div>
            </td>
            <td>{{ ep.port || '—' }}</td>
            <td><code class="mono-val" style="font-size:11px">{{ ep.allowed_ips || '—' }}</code></td>
            <td>{{ ep.keepalive > 0 ? ep.keepalive + 's' : '—' }}</td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs);white-space:nowrap">
              {{ formatTime(ep.last_handshake) }}
            </td>
            <td style="font-size:var(--font-size-xs)">
              <span style="color:var(--color-success)">↓{{ formatBytes(ep.rx_bytes) }}</span>
              <span style="color:var(--color-text-muted);margin:0 4px">/</span>
              <span style="color:var(--color-info)">↑{{ formatBytes(ep.tx_bytes) }}</span>
            </td>
            <td>
              <span class="badge" :class="ep.available ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ ep.available ? 'Active' : 'Inactive' }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Changes Tab -->
    <div v-if="activeTab === 'changes'">
      <!-- Add Change Form -->
      <div class="card" style="margin-bottom:var(--space-md)">
        <div class="card-header">
          <h2 class="card-title">{{ t('hosts.pushChange') }}</h2>
        </div>
        <form @submit.prevent="submitChange" style="display:flex;gap:var(--space-sm);flex-wrap:wrap;align-items:flex-end">
          <div class="form-group" style="margin-bottom:0;flex:0 0 180px">
            <label class="form-label">{{ t('settings.auditType') }}</label>
            <select v-model="newChange.type" class="form-input">
              <option value="add_peer">{{ t('hosts.addPeer') }}</option>
              <option value="remove_peer">{{ t('hosts.removePeer') }}</option>
              <option value="update_interface">{{ t('hosts.updateInterface') }}</option>
            </select>
          </div>
          <div class="form-group" style="margin-bottom:0;flex:1;min-width:250px">
            <label class="form-label">Payload (JSON)</label>
            <input v-model="newChange.payload" class="form-input" placeholder='{"interface":"wg0","public_key":"...","allowed_ips":"10.0.0.2/32"}' />
          </div>
          <button type="submit" class="btn btn-primary" :disabled="changeSending">
            <span class="material-symbols-outlined" style="font-size:16px">send</span>
            {{ t('hosts.pushChange') }}
          </button>
        </form>
        <div v-if="changeError" style="color:var(--color-danger);font-size:var(--font-size-xs);margin-top:var(--space-sm)">{{ changeError }}</div>
      </div>

      <!-- Changes History -->
      <div class="card">
        <div v-if="changes.length === 0" class="empty-state">
          <span class="material-symbols-outlined">history</span>
          <h3>{{ t('hosts.noChanges') }}</h3>
          <p>No desired changes have been created for this host.</p>
        </div>
        <table v-else class="data-table">
          <thead>
            <tr>
              <th>{{ t('settings.auditType') }}</th>
              <th>{{ t('common.status') }}</th>
              <th>{{ t('common.message') }}</th>
              <th>{{ t('common.time') }}</th>
              <th>Executed</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="ch in changes" :key="ch.id">
              <td style="font-weight:500">
                <span class="badge" :class="changeTypeClass(ch.type)">{{ ch.type }}</span>
              </td>
              <td>
                <span class="badge" :class="changeStateClass(ch.state)">
                  <span class="material-symbols-outlined" style="font-size:12px">{{ changeStateIcon(ch.state) }}</span>
                  {{ ch.state }}
                </span>
              </td>
              <td style="max-width:250px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:var(--font-size-xs)">
                {{ ch.message || '—' }}
              </td>
              <td style="font-size:var(--font-size-xs);color:var(--color-text-secondary)">{{ formatTime(ch.created_at) }}</td>
              <td style="font-size:var(--font-size-xs);color:var(--color-text-secondary)">{{ ch.executed_at ? formatTime(ch.executed_at) : '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Agent Token Modal -->
    <div v-if="showTokenModal" class="modal-overlay" @click.self="showTokenModal = false">
      <div class="modal-card">
        <div class="modal-header">
          <h3>
            <span class="material-symbols-outlined" style="font-size:19px;vertical-align:middle;margin-right:6px">key</span>
            Agent Token
          </h3>
          <button class="modal-close" @click="showTokenModal = false">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <div v-if="!agentToken" class="modal-body">
          <p class="hint">Generate a host-scoped Agent Token (10 years) to authenticate the <code>peersight-agent</code> daemon for <strong>{{ host?.name }}</strong>.</p>
          <div class="modal-footer">
            <button class="btn btn-secondary" @click="showTokenModal = false">Cancel</button>
            <button class="btn btn-primary" :disabled="tokenLoading" @click="handleGenerateToken">
              <span v-if="tokenLoading" class="spinner-sm"></span>
              <span v-else style="display:flex;align-items:center;gap:5px">
                <span class="material-symbols-outlined" style="font-size:16px">key</span>
                Generate Agent Token
              </span>
            </button>
          </div>
        </div>

        <div v-else class="modal-body animate-fade">
          <div class="success-banner">
            <span class="material-symbols-outlined">key</span>
            Host-scoped token valid for <strong>10 years</strong>
          </div>

          <div class="info-row">
            <span class="info-label">Host ID</span>
            <div class="copy-row">
              <code class="truncate">{{ host?.id }}</code>
              <button class="copy-btn" @click="copy(host?.id, 'hostId')">
                <span class="material-symbols-outlined">{{ copied.hostId ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="info-row">
            <span class="info-label">Agent Token</span>
            <div class="copy-row">
              <code class="truncate">{{ agentToken }}</code>
              <button class="copy-btn" @click="copy(agentToken, 'token')">
                <span class="material-symbols-outlined">{{ copied.token ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="cmd-block-wrap">
            <div class="cmd-label">
              <span class="material-symbols-outlined" style="font-size:13px">terminal</span>
              Install command
            </div>
            <div class="cmd-block">
              <pre>{{ installCmd }}</pre>
              <button class="copy-btn cmd-copy" @click="copy(installCmd, 'cmd')">
                <span class="material-symbols-outlined">{{ copied.cmd ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>

          <div class="warning-note">
            <span class="material-symbols-outlined">warning</span>
            Save this token — it will not be shown again.
          </div>

          <div class="modal-footer">
            <button class="btn btn-primary" @click="showTokenModal = false">Done</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Delete Confirmation Modal -->
    <div v-if="showDeleteConfirm" class="modal-overlay" @click.self="showDeleteConfirm = false">
      <div class="modal-card" style="max-width:420px">
        <div class="modal-header">
          <h3 style="color:#f87171">
            <span class="material-symbols-outlined" style="font-size:19px;vertical-align:middle;margin-right:6px">warning</span>
            {{ t('common.delete') }}
          </h3>
          <button class="modal-close" @click="showDeleteConfirm = false">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
        <div class="modal-body">
          <p style="color:var(--color-text-secondary);line-height:1.6;margin:0">
            {{ t('hosts.deleteConfirm').replace('{name}', host?.name) }}<br/>
            {{ t('hosts.deleteWarning') }}
          </p>
          <div class="modal-footer">
            <button class="btn btn-secondary" @click="showDeleteConfirm = false">{{ t('common.cancel') }}</button>
            <button class="btn btn-danger" :disabled="deleteLoading" @click="executeDelete">
              <span v-if="deleteLoading" class="spinner-sm"></span>
              <span v-else>{{ t('common.delete') }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/plugins/axios.js'
import { useHostStore } from '@/stores/data.js'
import { useI18n } from '@/utils/i18n.js'

const route = useRoute()
const router = useRouter()
const hostId = route.params.id

const hostStore = useHostStore()
const { t } = useI18n()

const host = ref(null)
const interfaces = ref([])
const endpoints = ref([])
const changes = ref([])
const activeTab = ref('interfaces')

const newChange = ref({ type: 'add_peer', payload: '' })
const changeSending = ref(false)
const changeError = ref('')

// Rename states
const editingName = ref(false)
const editNameVal = ref('')
const nameInput = ref(null)

// Delete states
const showDeleteConfirm = ref(false)
const deleteLoading = ref(false)

// Token states
const showTokenModal = ref(false)
const tokenLoading = ref(false)
const agentToken = ref('')
const copied = ref({ hostId: false, token: false, cmd: false })

const installCmd = computed(() => {
  if (!host.value || !agentToken.value) return ''
  return `cd ~/wireguard-edge-cloud-5g && sudo -E PEERSIGHT_API_URL="http://10.8.0.1:4000" \\
     PEERSIGHT_HOST_ID="${host.value.id}" \\
     PEERSIGHT_TOKEN="${agentToken.value}" \\
     bash peersight/install-agent.sh`
})

const tabs = computed(() => [
  { id: 'interfaces', label: t('hosts.interfaces'), icon: 'lan', count: interfaces.value.length },
  { id: 'endpoints', label: t('hosts.endpoints'), icon: 'hub', count: endpoints.value.length },
  { id: 'changes', label: t('hosts.changes'), icon: 'history', count: changes.value.filter(c => c.state === 'pending').length }
])

onMounted(() => refreshAll())

async function refreshAll() {
  const [hostRes, ifaceRes, epRes, chRes] = await Promise.allSettled([
    api.get(`/hosts/${hostId}`),
    api.get(`/hosts/${hostId}/interfaces`),
    api.get(`/hosts/${hostId}/endpoints`),
    api.get(`/hosts/${hostId}/changes`)
  ])
  if (hostRes.status === 'fulfilled') host.value = hostRes.value.data.data
  if (ifaceRes.status === 'fulfilled') interfaces.value = ifaceRes.value.data.data || []
  if (epRes.status === 'fulfilled') endpoints.value = epRes.value.data.data || []
  if (chRes.status === 'fulfilled') changes.value = chRes.value.data.data || []
}

function startRename() {
  if (!host.value) return
  editNameVal.value = host.value.name
  editingName.value = true
  nextTick(() => {
    nameInput.value?.focus()
  })
}

function cancelRename() {
  editingName.value = false
}

async function saveName() {
  const val = editNameVal.value.trim()
  if (!val || val === host.value.name) {
    editingName.value = false
    return
  }
  try {
    const updated = await hostStore.updateHost(hostId, val)
    if (updated) {
      host.value.name = updated.name
    }
  } catch (err) {
    console.error('Failed to rename host:', err)
  } finally {
    editingName.value = false
  }
}

function confirmDelete() {
  showDeleteConfirm.value = true
}

async function executeDelete() {
  deleteLoading.value = true
  try {
    await hostStore.deleteHost(hostId)
    router.push('/hosts')
  } catch (err) {
    console.error('Failed to delete host:', err)
  } finally {
    deleteLoading.value = false
    showDeleteConfirm.value = false
  }
}

function openTokenModal() {
  agentToken.value = ''
  showTokenModal.value = true
}

async function handleGenerateToken() {
  tokenLoading.value = true
  try {
    const token = await hostStore.generateAgentToken(hostId)
    if (token) {
      agentToken.value = token
    }
  } catch (err) {
    console.error('Failed to generate token:', err)
  } finally {
    tokenLoading.value = false
  }
}

function copy(value, key) {
  if (!value) return
  navigator.clipboard.writeText(value)
  copied.value[key] = true
  setTimeout(() => {
    copied.value[key] = false
  }, 2000)
}

async function submitChange() {
  changeError.value = ''
  try {
    JSON.parse(newChange.value.payload)
  } catch {
    changeError.value = 'Payload must be valid JSON'
    return
  }
  changeSending.value = true
  try {
    await api.post(`/hosts/${hostId}/changes`, {
      type: newChange.value.type,
      payload: newChange.value.payload
    })
    newChange.value.payload = ''
    const res = await api.get(`/hosts/${hostId}/changes`)
    changes.value = res.data.data || []
  } catch (e) {
    changeError.value = e.response?.data?.error || 'Failed to create change'
  } finally {
    changeSending.value = false
  }
}

function isOnline(h) {
  if (!h?.last_ping) return false
  return Date.now() - new Date(h.last_ping).getTime() < 120000
}

function formatTime(ts) {
  if (!ts) return '—'
  const d = new Date(ts)
  const diff = Math.floor((Date.now() - d.getTime()) / 1000)
  if (diff < 60) return `${diff}s ago`
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  return d.toLocaleString()
}

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i]
}

function changeTypeClass(type) {
  const map = { add_peer: 'online', remove_peer: 'offline', update_interface: 'warning' }
  return map[type] || 'warning'
}

function changeStateClass(state) {
  const map = { pending: 'warning', executed: 'online', failed: 'offline' }
  return map[state] || 'warning'
}

function changeStateIcon(state) {
  const map = { pending: 'schedule', executed: 'check_circle', failed: 'error' }
  return map[state] || 'schedule'
}
</script>

<style scoped>
.host-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 8px;
  border-radius: var(--radius-sm);
}

.tabs {
  display: flex;
  gap: var(--space-xs);
  margin-bottom: var(--space-md);
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-xs);
}

.tab {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: var(--space-sm) var(--space-md);
  background: none;
  border: none;
  color: var(--color-text-secondary);
  font-family: var(--font-family);
  font-size: var(--font-size-sm);
  font-weight: 500;
  cursor: pointer;
  border-radius: var(--radius-sm) var(--radius-sm) 0 0;
  transition: all var(--transition-fast);
}

.tab:hover {
  color: var(--color-text-primary);
  background: var(--color-bg-hover);
}

.tab.active {
  color: var(--color-accent);
  border-bottom: 2px solid var(--color-accent);
}

.tab-count {
  background: rgba(79, 110, 247, 0.15);
  color: var(--color-accent);
  font-size: 11px;
  font-weight: 700;
  min-width: 20px;
  height: 20px;
  border-radius: var(--radius-full);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 6px;
}

.mono-val {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  font-family: monospace;
}

/* Inline edit input */
.inline-input-lg {
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-accent, #5865f2);
  border-radius: var(--radius-md, 8px);
  color: var(--color-text);
  padding: 6px 12px;
  font-size: var(--font-size-lg);
  font-weight: 700;
  outline: none;
  box-shadow: 0 0 0 2px rgba(88,101,242,.2);
}

/* Icon Buttons */
.icon-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--color-text-muted);
  padding: 6px;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  transition: background .15s, color .15s;
}
.icon-btn:hover { background: rgba(255,255,255,.06); color: var(--color-text); }
.icon-btn.green-btn:hover { background: rgba(74,222,128,.12); color: #4ade80; }

.icon-btn-edit {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--color-text-muted);
  padding: 4px;
  border-radius: 50%;
  display: inline-flex;
  align-items: center;
  transition: background 0.15s, color 0.15s;
}
.icon-btn-edit:hover {
  background: rgba(255, 255, 255, 0.05);
  color: var(--color-accent);
}

/* Modal and utility classes */
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
  width: 90%;
  max-width: 540px;
  padding: var(--space-xl, 24px);
  box-shadow: 0 12px 48px rgba(0,0,0,.6);
  animation: pop .22s cubic-bezier(.16,1,.3,1);
}
@keyframes pop {
  from { transform: scale(.96) translateY(8px); opacity: 0; }
  to   { transform: scale(1)   translateY(0);   opacity: 1; }
}
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
  background: transparent; border: none;
  color: var(--color-text-muted); cursor: pointer;
  padding: 4px; border-radius: 50%; display: flex;
  transition: background .15s, color .15s;
}
.modal-close:hover { background: rgba(255,255,255,.06); color: var(--color-text); }
.modal-body { display: flex; flex-direction: column; gap: var(--space-md, 14px); }
.modal-footer {
  display: flex; justify-content: flex-end; gap: 10px;
  padding-top: var(--space-md, 14px);
  border-top: 1px solid var(--color-border, #2d2d34);
  margin-top: var(--space-sm, 8px);
}

.hint { font-size: var(--font-size-sm, 13px); color: var(--color-text-secondary); margin: 0; line-height: 1.5; }
.success-banner {
  display: flex; align-items: center; gap: 10px;
  background: rgba(34,197,94,.08); border: 1px solid rgba(34,197,94,.3);
  border-radius: var(--radius-md, 8px); padding: 12px 14px;
  font-size: var(--font-size-sm); color: #4ade80;
}
.success-banner .material-symbols-outlined { font-size: 20px; }

.info-row { display: flex; flex-direction: column; gap: 5px; }
.info-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--color-text-muted); }
.copy-row {
  display: flex; align-items: center; gap: 8px;
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px); padding: 8px 12px;
}
.copy-row code { flex: 1; font-family: monospace; font-size: 12px; color: var(--color-accent); }
.copy-row .truncate { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.copy-btn {
  background: transparent; border: none; cursor: pointer;
  color: var(--color-text-muted); display: flex; align-items: center;
  padding: 2px; border-radius: 4px; flex-shrink: 0; transition: color .15s;
}
.copy-btn:hover { color: var(--color-accent); }
.copy-btn .material-symbols-outlined { font-size: 16px; }

.cmd-block-wrap { display: flex; flex-direction: column; gap: 6px; }
.cmd-label {
  display: flex; align-items: center; gap: 5px;
  font-size: 11px; font-weight: 700; text-transform: uppercase;
  letter-spacing: .05em; color: var(--color-text-muted);
}
.cmd-block {
  position: relative; background: #0a0a0f;
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px); padding: 12px 40px 12px 14px;
}
.cmd-block pre {
  margin: 0; font-family: monospace; font-size: 11px;
  color: #a3e635; white-space: pre-wrap; word-break: break-all; line-height: 1.6;
}
.cmd-copy { position: absolute; top: 8px; right: 8px; }

.warning-note {
  display: flex; align-items: center; gap: 8px; font-size: 12px; color: #fbbf24;
  background: rgba(251,191,36,.07); border: 1px solid rgba(251,191,36,.25);
  border-radius: var(--radius-md, 8px); padding: 10px 14px;
}
.warning-note .material-symbols-outlined { font-size: 18px; }

.spinner-sm {
  display: inline-block; width: 14px; height: 14px;
  border: 2px solid rgba(255,255,255,.2); border-top-color: #fff;
  border-radius: 50%; animation: spin .6s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}

.btn-danger {
  background: #dc2626;
  color: #fff;
  border: none;
  border-radius: var(--radius-md, 8px);
  padding: 8px 18px;
  font-size: var(--font-size-sm);
  font-weight: 600;
  cursor: pointer;
  transition: background .15s;
  display: flex;
  align-items: center;
  gap: 6px;
}
.btn-danger:hover:not(:disabled) { background: #b91c1c; }
.btn-danger:disabled { opacity: .5; cursor: default; }
</style>
