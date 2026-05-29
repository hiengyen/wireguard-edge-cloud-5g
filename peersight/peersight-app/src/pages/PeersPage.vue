<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">{{ t('peers.title') }}</h1>
      <div class="peer-toolbar">
        <select v-model="statusFilter" class="form-input compact-input">
          <option value="all">{{ t('peers.allStatuses') }}</option>
          <option value="active">{{ t('peers.active') }}</option>
          <option value="inactive">{{ t('peers.inactive') }}</option>
        </select>
        <input
          v-model.trim="searchQuery"
          class="form-input search-input"
          placeholder="Search peer, host, IP..."
        />
        <button class="btn btn-secondary" @click="fetchPeers">
          <span class="material-symbols-outlined">refresh</span>
          {{ t('common.refresh') }}
        </button>
      </div>
    </div>

    <div v-if="peerStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="peerStore.peers.length === 0" class="empty-state">
      <span class="material-symbols-outlined">hub</span>
      <h3>{{ t('peers.noEndpoints') }}</h3>
      <p>Peers are discovered automatically when an agent reports its WireGuard state.</p>
    </div>

    <div v-else class="card animate-fade" style="padding: 0; overflow: hidden;">
      <div class="table-responsive">
        <table class="data-table resizable-table">
          <thead>
            <tr>
              <th :style="{ width: colWidths.name + 'px' }">
                {{ t('hosts.hostName') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'name' }" @mousedown.stop.prevent="startResize($event, 'name')"></div>
              </th>
              <th :style="{ width: colWidths.public_key + 'px' }">
                Public Key
                <div class="resize-handle" :class="{ active: activeResizeCol === 'public_key' }" @mousedown.stop.prevent="startResize($event, 'public_key')"></div>
              </th>
              <th :style="{ width: colWidths.status + 'px' }">
                {{ t('common.status') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'status' }" @mousedown.stop.prevent="startResize($event, 'status')"></div>
              </th>
              <th :style="{ width: colWidths.related_host + 'px' }">
                {{ t('peers.relatedHost') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'related_host' }" @mousedown.stop.prevent="startResize($event, 'related_host')"></div>
              </th>
              <th :style="{ width: colWidths.allowed_ips + 'px' }">
                {{ t('peers.allowedIps') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'allowed_ips' }" @mousedown.stop.prevent="startResize($event, 'allowed_ips')"></div>
              </th>
              <th :style="{ width: colWidths.last_handshake + 'px' }">
                {{ t('peers.lastHandshake') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'last_handshake' }" @mousedown.stop.prevent="startResize($event, 'last_handshake')"></div>
              </th>
              <th :style="{ width: colWidths.traffic + 'px' }">
                {{ t('peers.traffic') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'traffic' }" @mousedown.stop.prevent="startResize($event, 'traffic')"></div>
              </th>
              <th :style="{ width: colWidths.actions + 'px' }">
                {{ t('users.actions') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'actions' }" @mousedown.stop.prevent="startResize($event, 'actions')"></div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="peer in peerStore.peers" :key="peer.id">
              <td style="font-weight:600">
                <router-link :to="`/peers/${peer.id}`" class="peer-link">
                  <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-success)">key</span>
                  {{ peer.name }}
                </router-link>
              </td>
              <td>
                <code class="pubkey">{{ truncateKey(peer.public_key) }}</code>
                <button class="copy-btn" @click="copyKey(peer.public_key)" title="Copy full key">
                  <span class="material-symbols-outlined" style="font-size:14px">content_copy</span>
                </button>
              </td>
              <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
                <span class="badge" :class="peer.active ? 'online' : 'offline'">
                  <span class="badge-dot"></span>
                  {{ peer.active ? t('peers.active') : t('peers.inactive') }}
                </span>
              </td>
              <td>
                <template v-if="primaryHost(peer)">
                  <router-link :to="`/hosts/${primaryHost(peer).id}`" class="host-chip">
                    <span class="material-symbols-outlined" style="font-size:15px;color:var(--color-accent)">dns</span>
                    {{ primaryHost(peer).name }}
                    <code>{{ primaryHost(peer).interface_name }}</code>
                  </router-link>
                  <span v-if="extraHostCount(peer) > 0" class="more-chip">+{{ extraHostCount(peer) }}</span>
                </template>
                <span v-else class="muted">—</span>
              </td>
              <td>
                <div v-if="peer.allowed_ips?.length" class="ip-list">
                  <code v-for="ip in peer.allowed_ips.slice(0, 2)" :key="ip" class="ip-chip">{{ ip }}</code>
                  <span v-if="peer.allowed_ips.length > 2" class="more-chip">+{{ peer.allowed_ips.length - 2 }}</span>
                </div>
                <span v-else class="muted">—</span>
              </td>
              <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs);white-space:nowrap">
                {{ formatTime(peer.last_handshake) }}
              </td>
              <td style="font-size:var(--font-size-xs);white-space:nowrap">
                <span style="color:var(--color-success)">↓{{ formatBytes(peer.rx_bytes) }}</span>
                <span style="color:var(--color-text-muted);margin:0 4px">/</span>
                <span style="color:var(--color-info)">↑{{ formatBytes(peer.tx_bytes) }}</span>
              </td>
              <td>
                <button class="btn btn-danger" style="font-size:var(--font-size-xs);padding:4px 10px" @click="confirmDelete(peer)">
                  <span class="material-symbols-outlined" style="font-size:14px">delete</span>
                  {{ t('common.delete') }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Delete Confirmation Modal -->
    <div v-if="peerToDelete" class="modal-overlay" @click.self="peerToDelete = null">
      <div class="modal-content">
        <h3 style="margin-bottom:var(--space-md)">{{ t('common.delete') }}</h3>
        <p style="color:var(--color-text-secondary);margin-bottom:var(--space-lg)">
          Are you sure you want to remove <strong>{{ peerToDelete.name }}</strong>?
          This will not remove the peer from the WireGuard interface.
        </p>
        <div style="display:flex;gap:var(--space-sm);justify-content:flex-end">
          <button class="btn btn-secondary" @click="peerToDelete = null">{{ t('common.cancel') }}</button>
          <button class="btn btn-danger" @click="deletePeer">{{ t('common.delete') }}</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { usePeerStore } from '@/stores/data.js'
import { useI18n } from '@/utils/i18n.js'
import { formatBytes, formatTime, truncateKey } from '@/utils/format.js'

const peerStore = usePeerStore()
const { t } = useI18n()
const peerToDelete = ref(null)
const statusFilter = ref('all')
const searchQuery = ref('')

// Resizable column widths (like Excel)
const colWidths = ref({
  name: 180,
  public_key: 140,
  status: 120,
  related_host: 160,
  allowed_ips: 160,
  last_handshake: 140,
  traffic: 160,
  actions: 120
})

const activeResizeCol = ref(null)
let startX = 0
let startWidth = 0

function startResize(event, colName) {
  activeResizeCol.value = colName
  startX = event.clientX
  startWidth = colWidths.value[colName]
  
  document.addEventListener('mousemove', handleResize)
  document.addEventListener('mouseup', stopResize)
  
  document.body.style.cursor = 'col-resize'
  document.body.style.userSelect = 'none'
}

function handleResize(event) {
  if (!activeResizeCol.value) return
  const diff = event.clientX - startX
  const newWidth = Math.max(startWidth + diff, 60)
  colWidths.value[activeResizeCol.value] = newWidth
}

function stopResize() {
  activeResizeCol.value = null
  document.removeEventListener('mousemove', handleResize)
  document.removeEventListener('mouseup', stopResize)
  
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
}

onMounted(() => {
  fetchPeers()
})

watch([statusFilter, searchQuery], () => fetchPeers())

function fetchPeers() {
  const params = { status: statusFilter.value, limit: 200 }
  if (searchQuery.value) params.q = searchQuery.value
  return peerStore.fetchPeers(params)
}

function copyKey(key) {
  navigator.clipboard.writeText(key)
}

function primaryHost(peer) {
  return peer.related_hosts?.[0] || null
}

function extraHostCount(peer) {
  return Math.max((peer.related_hosts?.length || 0) - 1, 0)
}

function confirmDelete(peer) {
  peerToDelete.value = peer
}

async function deletePeer() {
  if (peerToDelete.value) {
    await peerStore.deletePeer(peerToDelete.value.id)
    peerToDelete.value = null
    await fetchPeers()
  }
}
</script>

<style scoped>
.pubkey {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  font-family: monospace;
}

.copy-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 2px;
  margin-left: 4px;
  vertical-align: middle;
  transition: color var(--transition-fast);
}

.copy-btn:hover {
  color: var(--color-accent);
}

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 200;
  backdrop-filter: blur(4px);
}

.modal-content {
  background: var(--color-bg-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-xl);
  max-width: 420px;
  width: 90%;
  box-shadow: var(--shadow-lg);
}

.peer-link {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--color-text);
  text-decoration: none;
  transition: color var(--transition-fast);
}

.peer-link:hover {
  color: var(--color-accent);
}

.peer-toolbar {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  flex-wrap: wrap;
}

.compact-input {
  width: auto;
  min-width: 140px;
  margin: 0;
}

.search-input {
  width: 220px;
  margin: 0;
}

.host-chip,
.ip-list {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.host-chip {
  color: var(--color-text);
  text-decoration: none;
}

.host-chip:hover {
  color: var(--color-accent);
}

.host-chip code,
.ip-chip {
  font-size: 11px;
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  font-family: monospace;
}

.more-chip {
  display: inline-flex;
  align-items: center;
  color: var(--color-text-muted);
  background: rgba(148, 163, 184, 0.12);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
  font-size: 11px;
  font-weight: 600;
}

.muted {
  color: var(--color-text-muted);
}

/* Resizable columns & responsive styles */
.table-responsive {
  width: 100%;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

.resizable-table {
  table-layout: fixed;
  width: 100%;
  border-collapse: collapse;
}

.resizable-table th {
  position: relative;
  user-select: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.resizable-table td {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.resize-handle {
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 6px;
  cursor: col-resize;
  z-index: 100;
  border-right: 1px solid var(--color-border, #2a2e42);
  transition: border-right-color var(--transition-fast), background-color var(--transition-fast);
}

.resize-handle:hover,
.resize-handle.active {
  border-right: 2px solid var(--color-accent, #4f6ef7);
  background-color: rgba(79, 110, 247, 0.15);
}

.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
