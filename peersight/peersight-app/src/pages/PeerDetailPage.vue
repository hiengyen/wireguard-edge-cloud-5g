<template>
  <div>
    <!-- Back + Header -->
    <div class="page-header">
      <div style="display:flex;align-items:center;gap:var(--space-md)">
        <router-link to="/peers" class="btn btn-secondary" style="padding:6px 10px">
          <span class="material-symbols-outlined" style="font-size:18px">arrow_back</span>
        </router-link>
        <div>
          <h1 class="page-title">{{ peer?.name || 'Loading Peer...' }}</h1>
          <div v-if="peer" class="pubkey-wrap">
            <code class="pubkey">{{ peer.public_key }}</code>
            <button class="copy-btn" @click="copyKey" title="Copy full key">
              <span class="material-symbols-outlined" style="font-size:16px">{{ copied ? 'check' : 'content_copy' }}</span>
            </button>
          </div>
        </div>
      </div>
      <button class="btn btn-secondary" @click="refreshAll" style="display:flex;align-items:center;gap:6px">
        <span class="material-symbols-outlined">refresh</span> Refresh
      </button>
    </div>

    <!-- Peer Info Cards -->
    <div v-if="peer" class="stat-grid animate-fade" style="margin-bottom:var(--space-xl)">
      <div class="stat-card">
        <div class="stat-icon green"><span class="material-symbols-outlined">schedule</span></div>
        <div>
          <div class="stat-value">{{ formatDate(peer.created_at) }}</div>
          <div class="stat-label">Discovered On</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon blue"><span class="material-symbols-outlined">hub</span></div>
        <div>
          <div class="stat-value">{{ endpoints.length }}</div>
          <div class="stat-label">Active Host Associations</div>
        </div>
      </div>
      <div class="stat-card">
        <div class="stat-icon yellow"><span class="material-symbols-outlined">swap_calls</span></div>
        <div>
          <div class="stat-value">{{ totalTransfer }}</div>
          <div class="stat-label">Cumulative Data Flow</div>
        </div>
      </div>
    </div>

    <!-- Interfaces and Associated Hosts -->
    <div class="card animate-fade">
      <div class="card-header border-b">
        <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
          <span class="material-symbols-outlined" style="color:var(--color-accent)">dns</span>
          Host Endpoint Associations
        </h2>
      </div>

      <div v-if="loading" style="text-align:center;padding:var(--space-xl)">
        <div class="spinner" style="margin:0 auto"></div>
      </div>

      <div v-else-if="endpoints.length === 0" class="empty-state">
        <span class="material-symbols-outlined">swap_horiz</span>
        <h3>No Host Associations</h3>
        <p>This peer is not active on any managed WireGuard interface.</p>
      </div>

      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Host Node</th>
            <th>WG Interface</th>
            <th>Tunnel IP</th>
            <th>Allowed IPs</th>
            <th>Last Handshake</th>
            <th>RX / TX Data</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="ep in endpoints" :key="ep.id">
            <!-- Link back to Host -->
            <td style="font-weight:600">
              <router-link :to="`/hosts/${ep.host_id}`" class="host-link">
                <span class="material-symbols-outlined" style="font-size:16px;color:var(--color-accent)">dns</span>
                {{ ep.host_name || 'Unknown Host' }}
              </router-link>
            </td>
            <td>
              <code class="mono-val">{{ ep.interface_name || 'wg0' }}</code>
            </td>
            <td>
              <code class="mono-val" v-if="ep.ip">{{ ep.ip }}:{{ ep.port }}</code>
              <span v-else class="text-muted">—</span>
            </td>
            <td>
              <code class="mono-val" style="font-size:11px">{{ ep.allowed_ips || '—' }}</code>
            </td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
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
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/plugins/axios.js'
import { formatTime, formatBytes, formatDate } from '@/utils/format.js'

const route = useRoute()
const peerId = route.params.id

const peer = ref(null)
const endpoints = ref([])
const loading = ref(false)
const copied = ref(false)

const totalTransfer = computed(() => {
  if (endpoints.value.length === 0) return '0 B'
  const sum = endpoints.value.reduce((acc, ep) => acc + (ep.rx_bytes || 0) + (ep.tx_bytes || 0), 0)
  return formatBytes(sum)
})

onMounted(() => {
  refreshAll()
})

async function refreshAll() {
  loading.value = true
  try {
    const [peerRes, epRes] = await Promise.allSettled([
      api.get(`/peers/${peerId}`),
      api.get(`/peers/${peerId}/endpoints`)
    ])
    if (peerRes.status === 'fulfilled') peer.value = peerRes.value.data.data
    if (epRes.status === 'fulfilled') endpoints.value = epRes.value.data.data || []
  } catch (err) {
    console.error('Failed to refresh peer detail:', err)
  } finally {
    loading.value = false
  }
}

function copyKey() {
  if (!peer.value) return
  navigator.clipboard.writeText(peer.value.public_key)
  copied.value = true
  setTimeout(() => {
    copied.value = false
  }, 2000)
}
</script>

<style scoped>
.pubkey-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
}

.pubkey {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 4px 8px;
  border-radius: var(--radius-sm);
  font-family: monospace;
}

.copy-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 4px;
  display: flex;
  border-radius: 4px;
  transition: color 0.15s, background-color 0.15s;
}

.copy-btn:hover {
  color: var(--color-accent);
  background: rgba(255, 255, 255, 0.05);
}

.border-b {
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-md);
  margin-bottom: var(--space-md);
}

.mono-val {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  font-family: monospace;
}

.host-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--color-text);
  text-decoration: none;
  transition: color 0.15s;
}

.host-link:hover {
  color: var(--color-accent);
}

.text-muted {
  color: var(--color-text-muted);
}

.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
