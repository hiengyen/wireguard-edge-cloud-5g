<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Settings</h1>
      <button class="btn btn-secondary" @click="fetchDiagnostics" style="display:flex;align-items:center;gap:6px">
        <span class="material-symbols-outlined" style="font-size:18px">sync</span>
        Refresh Diagnostics
      </button>
    </div>

    <div class="settings-grid">
      <!-- Agent Token Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-accent)">key</span>
            Agent Tokens
          </h2>
        </div>
        <div class="card-body">
          <p class="settings-desc">
            Generate long-lived tokens (valid for 10 years) to authenticate and initialize <code>peersight-agent</code> on your edge and gateway nodes.
          </p>

          <div v-if="generatedToken" class="token-result animate-fade">
            <div class="success-alert">
              <span class="material-symbols-outlined">check_circle</span>
              <span>Token generated successfully!</span>
            </div>
            
            <div class="token-box">
              <code class="token-text">{{ showToken ? generatedToken : maskToken(generatedToken) }}</code>
              <div class="token-actions">
                <button class="icon-btn" @click="showToken = !showToken" :title="showToken ? 'Hide token' : 'Show token'">
                  <span class="material-symbols-outlined">{{ showToken ? 'visibility_off' : 'visibility' }}</span>
                </button>
                <button class="icon-btn" @click="copyToken" :title="copied ? 'Copied!' : 'Copy to clipboard'">
                  <span class="material-symbols-outlined">{{ copied ? 'check' : 'content_copy' }}</span>
                </button>
              </div>
            </div>

            <div class="warning-alert">
              <span class="material-symbols-outlined">warning</span>
              <span>Make sure to copy this token now. For security, you will not be able to view it again after leaving this page.</span>
            </div>
          </div>

          <div class="btn-wrap">
            <button class="btn btn-primary" :disabled="loading" @click="generateToken" style="display:flex;align-items:center;gap:8px">
              <span v-if="loading" class="spinner-sm"></span>
              <span v-else class="material-symbols-outlined" style="font-size:18px">vpn_key</span>
              Generate New Agent Token
            </button>
          </div>
        </div>
      </div>

      <!-- Diagnostics Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-success)">analytics</span>
            System Diagnostics
          </h2>
        </div>
        <div class="card-body">
          <div v-if="diagnosticsLoading" class="diag-loading">
            <div class="spinner-sm"></div>
            <span>Fetching live API state...</span>
          </div>

          <div v-else-if="diagnosticsError" class="diag-error">
            <span class="material-symbols-outlined">error</span>
            <span>Failed to contact backend API. Host might be offline.</span>
          </div>

          <div v-else class="diagnostics-info animate-fade">
            <!-- Health Row -->
            <div class="diag-row">
              <span class="diag-label">API Service Status</span>
              <span class="badge" :class="diagnostics.status === 'healthy' ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ diagnostics.status || 'Offline' }}
              </span>
            </div>

            <!-- Version Row -->
            <div class="diag-row">
              <span class="diag-label">Software Version</span>
              <code>v{{ diagnostics.version || '0.1.0' }}</code>
            </div>

            <!-- Uptime Row -->
            <div class="diag-row">
              <span class="diag-label">API Service Uptime</span>
              <span style="font-weight:500;color:var(--color-text)">{{ diagnostics.uptime || '—' }}</span>
            </div>

            <!-- Database Stats Divider -->
            <div class="section-divider">PostgreSQL Connections</div>

            <div class="db-metrics-grid">
              <div class="metric-box">
                <span class="metric-val">{{ diagnostics.database?.total_conns ?? '—' }}</span>
                <span class="metric-lbl">Total Pool Size</span>
              </div>
              <div class="metric-box">
                <span class="metric-val" style="color:var(--color-accent)">{{ diagnostics.database?.acquired ?? '—' }}</span>
                <span class="metric-lbl">Active</span>
              </div>
              <div class="metric-box">
                <span class="metric-val" style="color:var(--color-text-muted)">{{ diagnostics.database?.idle_conns ?? '—' }}</span>
                <span class="metric-lbl">Idle</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { api } from '@/plugins/axios.js'

const hostStore = useHostStore()

const loading = ref(false)
const generatedToken = ref('')
const showToken = ref(false)
const copied = ref(false)

const diagnostics = ref({})
const diagnosticsLoading = ref(false)
const diagnosticsError = ref(false)

onMounted(() => {
  fetchDiagnostics()
})

async function generateToken() {
  loading.value = true
  showToken.value = false
  copied.value = false
  try {
    const token = await hostStore.generateAgentToken()
    if (token) {
      generatedToken.value = token
    }
  } catch (err) {
    console.error('Failed to generate agent token:', err)
  } finally {
    loading.value = false
  }
}

async function fetchDiagnostics() {
  diagnosticsLoading.value = true
  diagnosticsError.value = false
  try {
    const res = await api.get('/health')
    diagnostics.value = res.data
  } catch (err) {
    diagnosticsError.value = true
    console.error('Failed to fetch diagnostics:', err)
  } finally {
    diagnosticsLoading.value = false
  }
}

function maskToken(token) {
  if (!token) return ''
  return token.substring(0, 16) + '•'.repeat(48) + token.substring(token.length - 8)
}

function copyToken() {
  if (!generatedToken.value) return
  navigator.clipboard.writeText(generatedToken.value)
  copied.value = true
  setTimeout(() => {
    copied.value = false
  }, 2000)
}
</script>

<style scoped>
.settings-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-lg);
  align-items: start;
}

@media (max-width: 992px) {
  .settings-grid {
    grid-template-columns: 1fr;
  }
}

.settings-card {
  height: 100%;
}

.border-b {
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-md);
  margin-bottom: var(--space-md);
}

.settings-desc {
  font-size: var(--font-size-sm);
  color: var(--color-text-secondary);
  line-height: 1.6;
  margin-bottom: var(--space-lg);
}

.btn-wrap {
  margin-top: var(--space-lg);
  display: flex;
}

/* Token Result Area */
.token-result {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
  margin-bottom: var(--space-md);
}

.success-alert {
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgba(52, 211, 153, 0.08);
  border: 1px solid rgba(52, 211, 153, 0.3);
  color: #34d399;
  padding: 10px 14px;
  border-radius: var(--radius-md);
  font-size: var(--font-size-sm);
  font-weight: 500;
}

.success-alert .material-symbols-outlined {
  font-size: 20px;
}

.token-box {
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md);
  padding: var(--space-md);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-md);
}

.token-text {
  font-family: monospace;
  font-size: var(--font-size-sm);
  color: var(--color-accent);
  word-break: break-all;
  user-select: all;
  flex: 1;
}

.token-actions {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}

.icon-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 6px;
  border-radius: var(--radius-sm);
  display: flex;
  transition: background 0.15s, color 0.15s;
}

.icon-btn:hover {
  background: rgba(255, 255, 255, 0.05);
  color: var(--color-text);
}

.warning-alert {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  background: rgba(251, 191, 36, 0.08);
  border: 1px solid rgba(251, 191, 36, 0.3);
  color: #fbbf24;
  padding: 10px 14px;
  border-radius: var(--radius-md);
  font-size: var(--font-size-xs);
  line-height: 1.5;
}

.warning-alert .material-symbols-outlined {
  font-size: 18px;
  margin-top: 1px;
}

/* Diagnostics Info Area */
.diagnostics-info {
  display: flex;
  flex-direction: column;
  gap: var(--space-md);
}

.diag-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-sm) 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.02);
}

.diag-label {
  font-size: var(--font-size-sm);
  color: var(--color-text-secondary);
}

.diag-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-sm);
  color: var(--color-text-muted);
  font-size: var(--font-size-sm);
  padding: var(--space-xl) 0;
}

.diag-error {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-sm);
  color: var(--color-danger);
  font-size: var(--font-size-sm);
  padding: var(--space-xl) 0;
}

.section-divider {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--color-text-muted);
  margin-top: var(--space-md);
  margin-bottom: var(--space-xs);
}

.db-metrics-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: var(--space-sm);
  margin-top: var(--space-xs);
}

.metric-box {
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  border-radius: var(--radius-md);
  padding: var(--space-md) var(--space-sm);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
}

.metric-val {
  font-size: var(--font-size-lg);
  font-weight: 700;
  color: var(--color-text);
  font-family: var(--font-family);
}

.metric-lbl {
  font-size: 10px;
  font-weight: 500;
  color: var(--color-text-muted);
  text-align: center;
}

/* Animations */
.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}

.spinner-sm {
  display: inline-block;
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255, 255, 255, 0.2);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
