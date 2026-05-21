<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Peers</h1>
      <button class="btn btn-secondary" @click="peerStore.fetchPeers()">
        <span class="material-symbols-outlined">refresh</span>
        Refresh
      </button>
    </div>

    <div v-if="peerStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="peerStore.peers.length === 0" class="empty-state">
      <span class="material-symbols-outlined">hub</span>
      <h3>No Peers Found</h3>
      <p>Peers are discovered automatically when an agent reports its WireGuard state.</p>
    </div>

    <div v-else class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Public Key</th>
            <th>Created</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="peer in peerStore.peers" :key="peer.id">
            <td style="font-weight:600">
              <div style="display:flex;align-items:center;gap:8px">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-success)">key</span>
                {{ peer.name }}
              </div>
            </td>
            <td>
              <code class="pubkey">{{ truncateKey(peer.public_key) }}</code>
              <button class="copy-btn" @click="copyKey(peer.public_key)" title="Copy full key">
                <span class="material-symbols-outlined" style="font-size:14px">content_copy</span>
              </button>
            </td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
              {{ formatDate(peer.created_at) }}
            </td>
            <td>
              <button class="btn btn-danger" style="font-size:var(--font-size-xs);padding:4px 10px" @click="confirmDelete(peer)">
                <span class="material-symbols-outlined" style="font-size:14px">delete</span>
                Remove
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Delete Confirmation Modal -->
    <div v-if="peerToDelete" class="modal-overlay" @click.self="peerToDelete = null">
      <div class="modal-content">
        <h3 style="margin-bottom:var(--space-md)">Remove Peer?</h3>
        <p style="color:var(--color-text-secondary);margin-bottom:var(--space-lg)">
          Are you sure you want to remove <strong>{{ peerToDelete.name }}</strong>?
          This will not remove the peer from the WireGuard interface.
        </p>
        <div style="display:flex;gap:var(--space-sm);justify-content:flex-end">
          <button class="btn btn-secondary" @click="peerToDelete = null">Cancel</button>
          <button class="btn btn-danger" @click="deletePeer">Remove</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { usePeerStore } from '@/stores/data.js'

const peerStore = usePeerStore()
const peerToDelete = ref(null)

onMounted(() => peerStore.fetchPeers())

function truncateKey(key) {
  if (!key) return '—'
  return key.substring(0, 12) + '…' + key.substring(key.length - 6)
}

function copyKey(key) {
  navigator.clipboard.writeText(key)
}

function formatDate(ts) {
  return ts ? new Date(ts).toLocaleDateString() : '—'
}

function confirmDelete(peer) {
  peerToDelete.value = peer
}

async function deletePeer() {
  if (peerToDelete.value) {
    await peerStore.deletePeer(peerToDelete.value.id)
    peerToDelete.value = null
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
</style>
