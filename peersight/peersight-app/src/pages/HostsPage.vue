<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Hosts</h1>
      <div style="display:flex;gap:12px;align-items:center">
        <button class="btn btn-primary" @click="showCreateModal = true" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">add</span>
          Register Host
        </button>
        <button class="btn btn-secondary" @click="hostStore.fetchHosts()" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">refresh</span>
          Refresh
        </button>
      </div>
    </div>

    <div v-if="hostStore.loading && hostStore.hosts.length === 0" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="hostStore.hosts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">dns</span>
      <h3>No Hosts Registered</h3>
      <p>Click "Register Host" above or install the peersight-agent on a WireGuard host to get started.</p>
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
          <tr v-for="host in hostStore.hosts" :key="host.id" @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
            <td style="font-weight:600">
              <div style="display:flex;align-items:center;gap:8px">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-accent)">computer</span>
                {{ host.name }}
              </div>
            </td>
            <td>
              <code class="mono-id">{{ shortId(host.id) }}</code>
            </td>
            <td>
              <code style="font-size:var(--font-size-xs);color:var(--color-text-muted)">
                {{ host.agent_version || '—' }}
              </code>
            </td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
              {{ formatTime(host.last_ping) }}
            </td>
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

    <!-- Register Host Modal -->
    <div v-if="showCreateModal" class="modal-overlay" @click.self="closeModal">
      <div class="modal-card">
        <div class="modal-header">
          <h3>Register New Host</h3>
          <button class="modal-close" @click="closeModal">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
        <div class="modal-body">
          <p style="color:var(--color-text-secondary);font-size:var(--font-size-sm);margin-bottom:var(--space-lg)">
            Create a host profile to generate a unique <strong>Host ID</strong>. You will need this ID to configure the local peersight-agent.
          </p>
          <div class="form-group" v-if="!createdHost">
            <label for="host-name" style="display:block;margin-bottom:6px;font-weight:600;font-size:var(--font-size-sm)">Host Name</label>
            <input 
              id="host-name"
              type="text" 
              v-model="newHostName" 
              placeholder="e.g. edge-orangepi-01" 
              class="form-control"
              @keyup.enter="handleCreateHost"
            />
          </div>
          
          <div v-if="createdHost" class="creation-success" style="margin-top:var(--space-lg)">
            <h4 style="color:var(--color-accent);margin-bottom:8px;display:flex;align-items:center;gap:6px">
              <span class="material-symbols-outlined">check_circle</span>
              Host Created Successfully!
            </h4>
            <div class="success-box">
              <div style="margin-bottom:8px">
                <span class="label">Host ID (UUID):</span>
                <div class="copy-box">
                  <code>{{ createdHost.id }}</code>
                  <button class="copy-action" @click="copyValue(createdHost.id)" title="Copy Host ID">
                    <span class="material-symbols-outlined">content_copy</span>
                  </button>
                </div>
              </div>
              <div style="margin-bottom:12px">
                <span class="label">Organization ID:</span>
                <div class="copy-box">
                  <code>{{ createdHost.org_id }}</code>
                  <button class="copy-action" @click="copyValue(createdHost.org_id)" title="Copy Organization ID">
                    <span class="material-symbols-outlined">content_copy</span>
                  </button>
                </div>
              </div>
              <p style="font-size:12px;color:var(--color-text-muted);margin:0">
                Use this <strong>Host ID</strong> to initialize the peersight-agent on your device.
              </p>
            </div>
          </div>
        </div>
        <div class="modal-footer" style="display:flex;justify-content:flex-end;gap:12px;margin-top:var(--space-xl)">
          <button class="btn btn-secondary" @click="closeModal">
            {{ createdHost ? 'Close' : 'Cancel' }}
          </button>
          <button v-if="!createdHost" class="btn btn-primary" :disabled="!newHostName.trim() || hostStore.loading" @click="handleCreateHost">
            Create Host
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { shortId, isOnline, formatTime } from '@/utils/format.js'

const hostStore = useHostStore()
onMounted(() => hostStore.fetchHosts())

const showCreateModal = ref(false)
const newHostName = ref('')
const createdHost = ref(null)

async function handleCreateHost() {
  if (!newHostName.value.trim()) return
  const host = await hostStore.createHost(newHostName.value.trim())
  if (host) {
    createdHost.value = host
  }
}

function closeModal() {
  showCreateModal.value = false
  newHostName.value = ''
  createdHost.value = null
}

function copyValue(value) {
  if (value) navigator.clipboard.writeText(value)
}
</script>

<style scoped>
.mono-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}

/* Modal Styling */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.75);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
  backdrop-filter: blur(4px);
}
.modal-card {
  background: var(--color-bg-card, #1e1e24);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 12px);
  width: 100%;
  max-width: 500px;
  padding: var(--space-xl, 24px);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
  animation: modal-fadeIn 0.25s cubic-bezier(0.16, 1, 0.3, 1);
}
@keyframes modal-fadeIn {
  from { transform: translateY(10px) scale(0.97); opacity: 0; }
  to { transform: translateY(0) scale(1); opacity: 1; }
}
.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-lg, 16px);
  border-bottom: 1px solid var(--color-border, #2d2d34);
  padding-bottom: var(--space-sm, 8px);
}
.modal-header h3 {
  margin: 0;
  font-size: var(--font-size-md, 18px);
  color: var(--color-text, #ffffff);
}
.modal-close {
  background: transparent;
  border: none;
  color: var(--color-text-muted, #7c7c8a);
  cursor: pointer;
  display: flex;
  align-items: center;
  padding: 4px;
  border-radius: 50%;
  transition: background 0.2s, color 0.2s;
}
.modal-close:hover {
  background: rgba(255, 255, 255, 0.05);
  color: var(--color-text, #ffffff);
}
.form-group {
  margin-bottom: var(--space-md, 16px);
}
.form-control {
  width: 100%;
  padding: 10px 14px;
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px);
  color: var(--color-text, #ffffff);
  font-size: var(--font-size-sm, 14px);
  transition: border-color 0.2s, box-shadow 0.2s;
}
.form-control:focus {
  outline: none;
  border-color: var(--color-accent, #5865f2);
  box-shadow: 0 0 0 2px rgba(88, 101, 242, 0.25);
}
.success-box {
  background: rgba(88, 101, 242, 0.08);
  border: 1px dashed var(--color-accent, #5865f2);
  border-radius: var(--radius-md, 8px);
  padding: var(--space-md, 16px);
}
.success-box .label {
  font-size: var(--font-size-xs, 12px);
  color: var(--color-text-muted, #7c7c8a);
  display: block;
  font-weight: 600;
}
.copy-box {
  background: var(--color-bg-input, #0f0f13);
  padding: 8px 12px;
  border-radius: var(--radius-sm, 4px);
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 4px;
  border: 1px solid var(--color-border, #2d2d34);
}

.copy-box code {
  min-width: 0;
  overflow-wrap: anywhere;
  color: var(--color-accent, #5865f2);
  font-family: monospace;
  font-size: var(--font-size-xs, 12px);
}

.copy-action {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  display: inline-flex;
  padding: 2px;
}

.copy-action:hover {
  color: var(--color-accent);
}

.copy-action .material-symbols-outlined {
  font-size: 16px;
}
</style>
