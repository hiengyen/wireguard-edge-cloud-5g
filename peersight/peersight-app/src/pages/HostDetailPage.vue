<template>
  <div>
    <!-- Back + Header -->
    <div class="page-header">
      <div style="display:flex;align-items:center;gap:var(--space-md)">
        <router-link to="/hosts" class="btn btn-secondary" style="padding:6px 10px">
          <span class="material-symbols-outlined" style="font-size:18px">arrow_back</span>
        </router-link>
        <div>
          <h1 class="page-title">{{ host?.name || 'Loading...' }}</h1>
          <code v-if="host" class="host-id">{{ host.id }}</code>
        </div>
      </div>
      <div style="display:flex;gap:var(--space-sm);align-items:center">
        <span v-if="host" class="badge" :class="isOnline(host) ? 'online' : 'offline'">
          <span class="badge-dot"></span>
          {{ isOnline(host) ? 'Online' : 'Offline' }}
        </span>
        <button class="btn btn-secondary" @click="refreshAll">
          <span class="material-symbols-outlined">refresh</span> Refresh
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
          <div class="stat-label">Interfaces</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon yellow"><span class="material-symbols-outlined">hub</span></div>
        <div>
          <div class="stat-value">{{ endpoints.length }}</div>
          <div class="stat-label">Peer Connections</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon red"><span class="material-symbols-outlined">schedule</span></div>
        <div>
          <div class="stat-value">{{ formatTime(host.last_ping) }}</div>
          <div class="stat-label">Last Ping</div>
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
        <h3>No Interfaces</h3>
        <p>No WireGuard interfaces reported by the agent yet.</p>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Address</th>
            <th>Listen Port</th>
            <th>MTU</th>
            <th>DNS</th>
            <th>Status</th>
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
        <h3>No Endpoints</h3>
        <p>No peer connections discovered yet.</p>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Peer IP</th>
            <th>Port</th>
            <th>Allowed IPs</th>
            <th>Keepalive</th>
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
          <h2 class="card-title">Push a Change</h2>
        </div>
        <form @submit.prevent="submitChange" style="display:flex;gap:var(--space-sm);flex-wrap:wrap;align-items:flex-end">
          <div class="form-group" style="margin-bottom:0;flex:0 0 180px">
            <label class="form-label">Type</label>
            <select v-model="newChange.type" class="form-input">
              <option value="add_peer">Add Peer</option>
              <option value="remove_peer">Remove Peer</option>
              <option value="update_interface">Update Interface</option>
            </select>
          </div>
          <div class="form-group" style="margin-bottom:0;flex:1;min-width:250px">
            <label class="form-label">Payload (JSON)</label>
            <input v-model="newChange.payload" class="form-input" placeholder='{"interface":"wg0","public_key":"...","allowed_ips":"10.0.0.2/32"}' />
          </div>
          <button type="submit" class="btn btn-primary" :disabled="changeSending">
            <span class="material-symbols-outlined" style="font-size:16px">send</span>
            Push
          </button>
        </form>
        <div v-if="changeError" style="color:var(--color-danger);font-size:var(--font-size-xs);margin-top:var(--space-sm)">{{ changeError }}</div>
      </div>

      <!-- Changes History -->
      <div class="card">
        <div v-if="changes.length === 0" class="empty-state">
          <span class="material-symbols-outlined">history</span>
          <h3>No Changes</h3>
          <p>No desired changes have been created for this host.</p>
        </div>
        <table v-else class="data-table">
          <thead>
            <tr>
              <th>Type</th>
              <th>State</th>
              <th>Message</th>
              <th>Created</th>
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
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/plugins/axios.js'

const route = useRoute()
const hostId = route.params.id

const host = ref(null)
const interfaces = ref([])
const endpoints = ref([])
const changes = ref([])
const activeTab = ref('interfaces')

const newChange = ref({ type: 'add_peer', payload: '' })
const changeSending = ref(false)
const changeError = ref('')

const tabs = computed(() => [
  { id: 'interfaces', label: 'Interfaces', icon: 'lan', count: interfaces.value.length },
  { id: 'endpoints', label: 'Endpoints', icon: 'hub', count: endpoints.value.length },
  { id: 'changes', label: 'Changes', icon: 'history', count: changes.value.filter(c => c.state === 'pending').length }
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
</style>
