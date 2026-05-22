<template>
  <div>
    <!-- Page header -->
    <div class="page-header">
      <h1 class="page-title">{{ t('hosts.title') }}</h1>
      <div style="display:flex;gap:10px">
        <button class="btn btn-primary" @click="openCreate" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">add</span>
          {{ t('hosts.registerNew') }}
        </button>
        <button class="btn btn-secondary" @click="hostStore.fetchHosts()" style="display:flex;align-items:center;gap:6px">
          <span class="material-symbols-outlined" style="font-size:18px">refresh</span>
          {{ t('common.refresh') }}
        </button>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="hostStore.loading && hostStore.hosts.length === 0" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <!-- Empty state -->
    <div v-else-if="hostStore.hosts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">dns</span>
      <h3>{{ t('settings.auditEmpty') }}</h3>
      <p>{{ t('settings.auditEmptyDesc') }}</p>
    </div>

    <!-- Host table -->
    <div v-else class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>{{ t('hosts.hostName') }}</th>
            <th>{{ t('hosts.hostId') }}</th>
            <th>Agent</th>
            <th>{{ t('hosts.lastSeen') }}</th>
            <th>{{ t('common.status') }}</th>
            <th style="text-align:right">{{ t('users.actions') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="host in hostStore.hosts" :key="host.id">
            <!-- Name cell — inline edit mode -->
            <td style="font-weight:600">
              <div v-if="editingId === host.id" style="display:flex;align-items:center;gap:6px" @click.stop>
                <input
                  v-model="editName"
                  class="inline-input"
                  @keyup.enter="submitEdit(host.id)"
                  @keyup.escape="cancelEdit"
                  ref="editInput"
                />
                <button class="icon-btn green" @click.stop="submitEdit(host.id)" title="Save">
                  <span class="material-symbols-outlined">check</span>
                </button>
                <button class="icon-btn muted" @click.stop="cancelEdit" title="Cancel">
                  <span class="material-symbols-outlined">close</span>
                </button>
              </div>
              <div v-else style="display:flex;align-items:center;gap:8px;cursor:pointer"
                   @click="$router.push(`/hosts/${host.id}`)">
                <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-accent)">computer</span>
                {{ host.name }}
              </div>
            </td>

            <td @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
              <code class="mono-id">{{ shortId(host.id) }}</code>
            </td>
            <td @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
              <code style="font-size:var(--font-size-xs);color:var(--color-text-muted)">{{ host.agent_ver || host.agent_version || '—' }}</code>
            </td>
            <td @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer;color:var(--color-text-secondary);font-size:var(--font-size-xs)">
              {{ formatTime(host.last_ping) }}
            </td>
            <td @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
              <span class="badge" :class="isOnline(host) ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ isOnline(host) ? t('common.online') : t('common.offline') }}
              </span>
            </td>

            <!-- Actions -->
            <td style="text-align:right">
              <div style="display:flex;justify-content:flex-end;gap:4px" @click.stop>
                <button class="icon-btn" @click.stop="startEdit(host)" :title="t('hosts.rename')">
                  <span class="material-symbols-outlined">edit</span>
                </button>
                <button class="icon-btn" @click.stop="openTokenModal(host)" :title="t('settings.generateToken')">
                  <span class="material-symbols-outlined">key</span>
                </button>
                <button class="icon-btn red" @click.stop="confirmDelete(host)" :title="t('common.delete')">
                  <span class="material-symbols-outlined">delete</span>
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- ═══════════════════════════════════════════
         MODAL: Register / Token flow
    ════════════════════════════════════════════ -->
    <div v-if="showModal" class="modal-overlay" @click.self="closeModal">
      <div class="modal-card">
        <div class="modal-header">
          <h3>
            <span class="material-symbols-outlined" style="font-size:19px;vertical-align:middle;margin-right:6px">
              {{ modalStep === 'form' ? 'dns' : modalStep === 'created' ? 'check_circle' : 'key' }}
            </span>
            {{ modalStep === 'form' ? t('hosts.registerNew')
              : modalStep === 'created' ? 'Host Created'
              : 'Agent Token' }}
          </h3>
          <button class="modal-close" @click="closeModal">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <!-- Step 1: form -->
        <div v-if="modalStep === 'form'" class="modal-body">
          <p class="hint">Enter a name for this WireGuard host. A unique Host ID will be generated.</p>
          <div class="form-group">
            <label for="host-name">{{ t('hosts.hostName') }}</label>
            <input id="host-name" type="text" v-model="newHostName" class="form-control"
                   placeholder="e.g. cloud-gateway" @keyup.enter="handleCreate" autofocus />
          </div>
          <div class="modal-footer">
            <button class="btn btn-secondary" @click="closeModal">{{ t('common.cancel') }}</button>
            <button class="btn btn-primary" :disabled="!newHostName.trim() || hostStore.loading" @click="handleCreate">
              <span v-if="hostStore.loading" class="spinner-sm"></span>
              <span v-else>{{ t('common.save') }}</span>
            </button>
          </div>
        </div>

        <!-- Step 2: host created -->
        <div v-if="modalStep === 'created'" class="modal-body">
          <div class="success-banner">
            <span class="material-symbols-outlined">check_circle</span>
            Host <strong>{{ activeHost?.name }}</strong> registered!
          </div>
          <div class="info-row">
            <span class="info-label">Host ID</span>
            <div class="copy-row">
              <code>{{ activeHost?.id }}</code>
              <button class="copy-btn" @click="copy(activeHost?.id, 'hostId')">
                <span class="material-symbols-outlined">{{ copied.hostId ? 'check' : 'content_copy' }}</span>
              </button>
            </div>
          </div>
          <p class="hint">Generate an Agent Token to authenticate the <code>peersight-agent</code> daemon.</p>
          <div class="modal-footer">
            <button class="btn btn-secondary" @click="closeModal">Skip</button>
            <button class="btn btn-primary" :disabled="tokenLoading" @click="handleGenerateToken">
              <span v-if="tokenLoading" class="spinner-sm"></span>
              <span v-else style="display:flex;align-items:center;gap:5px">
                <span class="material-symbols-outlined" style="font-size:16px">key</span>
                {{ t('settings.generateToken') }}
              </span>
            </button>
          </div>
        </div>

        <!-- Step 3: show token + install cmd -->
        <div v-if="modalStep === 'token'" class="modal-body">
          <div class="success-banner" style="color:#a3e635;border-color:rgba(163,230,53,.3);background:rgba(163,230,53,.07)">
            <span class="material-symbols-outlined">key</span>
            Token valid for <strong>10 years</strong>
          </div>

          <div class="info-row">
            <span class="info-label">Host ID</span>
            <div class="copy-row">
              <code class="truncate">{{ activeHost?.id }}</code>
              <button class="copy-btn" @click="copy(activeHost?.id, 'hostId')">
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
              {{ t('hosts.installCommand') }}
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
            {{ t('settings.tokenWarning') }}
          </div>

          <div class="modal-footer">
            <button class="btn btn-primary" @click="closeModal">Done</button>
          </div>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════
         MODAL: Delete confirmation
    ════════════════════════════════════════════ -->
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
            {{ t('hosts.deleteConfirm').replace('{name}', deleteTarget?.name) }}<br/>
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
import { ref, computed, nextTick, onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { shortId, isOnline, formatTime } from '@/utils/format.js'
import { useI18n } from '@/utils/i18n.js'

const hostStore = useHostStore()
const { t } = useI18n()
onMounted(() => hostStore.fetchHosts())

// ── Inline Edit ─────────────────────────────────
const editingId = ref(null)
const editName  = ref('')
const editInput = ref(null)

function startEdit(host) {
  editingId.value = host.id
  editName.value  = host.name
  nextTick(() => editInput.value?.focus())
}
function cancelEdit() {
  editingId.value = null
  editName.value  = ''
}
async function submitEdit(id) {
  const name = editName.value.trim()
  if (!name) return cancelEdit()
  await hostStore.updateHost(id, name)
  cancelEdit()
}

// ── Delete ──────────────────────────────────────
const showDeleteConfirm = ref(false)
const deleteTarget      = ref(null)
const deleteLoading     = ref(false)

function confirmDelete(host) {
  deleteTarget.value = host
  showDeleteConfirm.value = true
}
async function executeDelete() {
  if (!deleteTarget.value) return
  deleteLoading.value = true
  try {
    await hostStore.deleteHost(deleteTarget.value.id)
    showDeleteConfirm.value = false
    deleteTarget.value = null
  } finally {
    deleteLoading.value = false
  }
}

// ── Register / Token Modal ───────────────────────
const showModal   = ref(false)
const modalStep   = ref('form')     // 'form' | 'created' | 'token'
const newHostName = ref('')
const activeHost  = ref(null)
const agentToken  = ref('')
const tokenLoading = ref(false)
const copied = ref({ hostId: false, token: false, cmd: false })

const installCmd = computed(() => {
  if (!activeHost.value || !agentToken.value) return ''
  const hostName = window.location.hostname
  const apiHost = hostName === 'localhost' || hostName === '127.0.0.1' ? '127.0.0.1' : hostName
  return `cd ~/wireguard-edge-cloud-5g && sudo -E PEERSIGHT_API_URL="http://${apiHost}:4000" \\
     PEERSIGHT_HOST_ID="${activeHost.value.id}" \\
     PEERSIGHT_TOKEN="${agentToken.value}" \\
     bash peersight/install-agent.sh`
})

function openCreate() {
  newHostName.value = ''
  activeHost.value = null
  agentToken.value = ''
  modalStep.value = 'form'
  showModal.value = true
}

async function openTokenModal(host) {
  activeHost.value = host
  agentToken.value = ''
  modalStep.value = 'created'
  showModal.value = true
}

function closeModal() { showModal.value = false }

async function handleCreate() {
  if (!newHostName.value.trim()) return
  const host = await hostStore.createHost(newHostName.value.trim())
  if (host) { activeHost.value = host; modalStep.value = 'created' }
}

async function handleGenerateToken() {
  tokenLoading.value = true
  try {
    const token = await hostStore.generateAgentToken()
    if (token) { agentToken.value = token; modalStep.value = 'token' }
  } finally { tokenLoading.value = false }
}

function copy(value, key) {
  if (!value) return
  navigator.clipboard.writeText(value)
  copied.value[key] = true
  setTimeout(() => { copied.value[key] = false }, 2000)
}
</script>

<style scoped>
/* Table */
.mono-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}

/* Inline edit input */
.inline-input {
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-accent, #5865f2);
  border-radius: var(--radius-sm, 4px);
  color: var(--color-text);
  padding: 4px 8px;
  font-size: var(--font-size-sm);
  width: 160px;
  outline: none;
  box-shadow: 0 0 0 2px rgba(88,101,242,.2);
}

/* Action icon buttons */
.icon-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--color-text-muted);
  padding: 5px;
  border-radius: 6px;
  display: inline-flex;
  align-items: center;
  transition: background .15s, color .15s;
}
.icon-btn .material-symbols-outlined { font-size: 17px; }
.icon-btn:hover { background: rgba(255,255,255,.06); color: var(--color-text); }
.icon-btn.red:hover { background: rgba(248,113,113,.12); color: #f87171; }
.icon-btn.green:hover { background: rgba(74,222,128,.12); color: #4ade80; }
.icon-btn.muted:hover { background: rgba(255,255,255,.06); color: var(--color-text-muted); }

/* Danger button */
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

/* Modal */
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

/* Form */
.hint { font-size: var(--font-size-sm, 13px); color: var(--color-text-secondary); margin: 0; line-height: 1.5; }
.form-group label { display: block; font-size: var(--font-size-sm); font-weight: 600; margin-bottom: 6px; }
.form-control {
  width: 100%; padding: 10px 14px;
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md, 8px);
  color: var(--color-text); font-size: var(--font-size-sm);
  transition: border-color .2s, box-shadow .2s; box-sizing: border-box;
}
.form-control:focus { outline: none; border-color: var(--color-accent); box-shadow: 0 0 0 2px rgba(88,101,242,.25); }

/* Success banner */
.success-banner {
  display: flex; align-items: center; gap: 10px;
  background: rgba(34,197,94,.08); border: 1px solid rgba(34,197,94,.3);
  border-radius: var(--radius-md, 8px); padding: 12px 14px;
  font-size: var(--font-size-sm); color: #4ade80;
}
.success-banner .material-symbols-outlined { font-size: 20px; }

/* Info row */
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

/* Copy button */
.copy-btn {
  background: transparent; border: none; cursor: pointer;
  color: var(--color-text-muted); display: flex; align-items: center;
  padding: 2px; border-radius: 4px; flex-shrink: 0; transition: color .15s;
}
.copy-btn:hover { color: var(--color-accent); }
.copy-btn .material-symbols-outlined { font-size: 16px; }

/* Install command */
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

/* Warning */
.warning-note {
  display: flex; align-items: center; gap: 8px; font-size: 12px; color: #fbbf24;
  background: rgba(251,191,36,.07); border: 1px solid rgba(251,191,36,.25);
  border-radius: var(--radius-md, 8px); padding: 10px 14px;
}
.warning-note .material-symbols-outlined { font-size: 18px; }

/* Spinner */
.spinner-sm {
  display: inline-block; width: 14px; height: 14px;
  border: 2px solid rgba(255,255,255,.2); border-top-color: #fff;
  border-radius: 50%; animation: spin .6s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
