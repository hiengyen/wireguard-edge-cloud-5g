<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">{{ t('settings.title') }}</h1>
      <button class="btn btn-secondary" @click="fetchDiagnostics" style="display:flex;align-items:center;gap:6px">
        <span class="material-symbols-outlined" style="font-size:18px">sync</span>
        {{ t('settings.refreshDiagnostics') }}
      </button>
    </div>

    <div class="settings-grid">
      <!-- User Profile Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-info)">account_circle</span>
            {{ t('settings.profileTitle') }}
          </h2>
        </div>
        <div class="card-body">
          <div style="margin-bottom:var(--space-md)">
            <div class="diag-row" style="padding-top:0">
              <span class="diag-label">{{ t('settings.accountRole') }}</span>
              <span class="badge online" style="text-transform:capitalize">
                {{ authStore.role || 'User' }}
              </span>
            </div>
            <div class="diag-row">
              <span class="diag-label">{{ t('settings.userId') }}</span>
              <code style="font-size:var(--font-size-xs)">{{ authStore.userId || '—' }}</code>
            </div>
          </div>

          <div class="section-divider">{{ t('settings.changePass') }}</div>
          
          <form @submit.prevent="handleChangePassword" style="margin-top:var(--space-sm)">
            <div class="form-group">
              <label class="form-label">{{ t('settings.newPass') }}</label>
              <input
                v-model="newPassword"
                type="password"
                class="form-input"
                placeholder="Minimum 6 characters"
                required
                :disabled="passLoading"
              />
            </div>
            
            <div class="form-group">
              <label class="form-label">{{ t('settings.confirmPass') }}</label>
              <input
                v-model="confirmPassword"
                type="password"
                class="form-input"
                placeholder="Repeat new password"
                required
                :disabled="passLoading"
              />
            </div>

            <div v-if="passSuccess" class="success-alert" style="margin-bottom:var(--space-md)">
              <span class="material-symbols-outlined">check_circle</span>
              <span>{{ t('settings.passSuccess') }}</span>
            </div>

            <div v-if="passError" class="warning-alert" style="margin-bottom:var(--space-md)">
              <span class="material-symbols-outlined">error</span>
              <span>{{ passError }}</span>
            </div>

            <button type="submit" class="btn btn-primary" :disabled="passLoading" style="display:flex;align-items:center;gap:8px;width:100%;justify-content:center">
              <span v-if="passLoading" class="spinner-sm"></span>
              <span v-else class="material-symbols-outlined" style="font-size:18px">lock_reset</span>
              {{ t('settings.updatePass') }}
            </button>
          </form>
        </div>
      </div>

      <!-- Agent Token Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-accent)">key</span>
            {{ t('settings.tokensCardTitle') }}
          </h2>
        </div>
        <div class="card-body">
          <p class="settings-desc">
            {{ t('settings.tokensDesc') }}
          </p>

          <div v-if="generatedToken" class="token-result animate-fade">
            <div class="success-alert">
              <span class="material-symbols-outlined">check_circle</span>
              <span>{{ t('settings.tokenSuccess') }}</span>
            </div>
            
            <div class="token-box">
              <code class="token-text">{{ showToken ? generatedToken : maskToken(generatedToken) }}</code>
              <div class="token-actions">
                <button class="icon-btn" @click="showToken = !showToken" :title="showToken ? 'Hide token' : 'Show token'">
                  <span class="material-symbols-outlined">{{ showToken ? 'visibility_off' : 'visibility' }}</span>
                </button>
                <button class="icon-btn" @click="copyToken" :title="copied ? t('common.copied') : t('common.copy')">
                  <span class="material-symbols-outlined">{{ copied ? 'check' : 'content_copy' }}</span>
                </button>
              </div>
            </div>

            <div class="warning-alert">
              <span class="material-symbols-outlined">warning</span>
              <span>{{ t('settings.tokenWarning') }}</span>
            </div>
          </div>

          <div class="btn-wrap">
            <button class="btn btn-primary" :disabled="loading" @click="generateToken" style="display:flex;align-items:center;gap:8px">
              <span v-if="loading" class="spinner-sm"></span>
              <span v-else class="material-symbols-outlined" style="font-size:18px">vpn_key</span>
              {{ t('settings.generateToken') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Broker Token Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-success)">router</span>
            {{ t('settings.brokerTokenCardTitle') }}
          </h2>
        </div>
        <div class="card-body">
          <p class="settings-desc">
            {{ t('settings.brokerTokenDesc') }}
          </p>

          <div v-if="generatedBrokerToken" class="token-result animate-fade">
            <div class="success-alert">
              <span class="material-symbols-outlined">check_circle</span>
              <span>{{ t('settings.tokenSuccess') }}</span>
            </div>
            
            <div class="token-box">
              <code class="token-text">{{ showBrokerToken ? generatedBrokerToken : maskToken(generatedBrokerToken) }}</code>
              <div class="token-actions">
                <button class="icon-btn" @click="showBrokerToken = !showBrokerToken" :title="showBrokerToken ? 'Hide token' : 'Show token'">
                  <span class="material-symbols-outlined">{{ showBrokerToken ? 'visibility_off' : 'visibility' }}</span>
                </button>
                <button class="icon-btn" @click="copyBrokerToken" :title="copiedBroker ? t('common.copied') : t('common.copy')">
                  <span class="material-symbols-outlined">{{ copiedBroker ? 'check' : 'content_copy' }}</span>
                </button>
              </div>
            </div>

            <div class="warning-alert">
              <span class="material-symbols-outlined">warning</span>
              <span>{{ t('settings.tokenWarning') }}</span>
            </div>
          </div>

          <div class="btn-wrap">
            <button class="btn btn-primary" :disabled="brokerLoading" @click="generateBrokerTokenAction" style="display:flex;align-items:center;gap:8px">
              <span v-if="brokerLoading" class="spinner-sm"></span>
              <span v-else class="material-symbols-outlined" style="font-size:18px">api</span>
              {{ t('settings.generateBrokerToken') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Diagnostics Card -->
      <div class="card settings-card">
        <div class="card-header border-b">
          <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
            <span class="material-symbols-outlined" style="color:var(--color-success)">analytics</span>
            {{ t('settings.diagnosticsTitle') }}
          </h2>
        </div>
        <div class="card-body">
          <div v-if="diagnosticsLoading" class="diag-loading">
            <div class="spinner-sm"></div>
            <span>{{ t('settings.diagLoading') }}</span>
          </div>

          <div v-else-if="diagnosticsError" class="diag-error">
            <span class="material-symbols-outlined">error</span>
            <span>{{ t('settings.diagError') }}</span>
          </div>

          <div v-else class="diagnostics-info animate-fade">
            <!-- Health Row -->
            <div class="diag-row">
              <span class="diag-label">{{ t('settings.apiStatus') }}</span>
              <span class="badge" :class="diagnostics.status === 'healthy' ? 'online' : 'offline'">
                <span class="badge-dot"></span>
                {{ diagnostics.status || 'Offline' }}
              </span>
            </div>

            <!-- Version Row -->
            <div class="diag-row">
              <span class="diag-label">{{ t('settings.version') }}</span>
              <code>v{{ diagnostics.version || '0.1.0' }}</code>
            </div>

            <!-- Uptime Row -->
            <div class="diag-row">
              <span class="diag-label">{{ t('settings.uptime') }}</span>
              <span style="font-weight:500;color:var(--color-text)">{{ diagnostics.uptime || '—' }}</span>
            </div>

            <!-- Database Stats Divider -->
            <div class="section-divider">{{ t('settings.dbPool') }}</div>

            <div class="db-metrics-grid">
              <div class="metric-box">
                <span class="metric-val">{{ diagnostics.database?.total_conns ?? '—' }}</span>
                <span class="metric-lbl">{{ t('settings.dbTotal') }}</span>
              </div>
              <div class="metric-box">
                <span class="metric-val" style="color:var(--color-accent)">{{ diagnostics.database?.acquired ?? '—' }}</span>
                <span class="metric-lbl">{{ t('settings.dbActive') }}</span>
              </div>
              <div class="metric-box">
                <span class="metric-val" style="color:var(--color-text-muted)">{{ diagnostics.database?.idle_conns ?? '—' }}</span>
                <span class="metric-lbl">{{ t('settings.dbIdle') }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Audit Logs Section -->
    <div class="card animate-fade" style="margin-top: var(--space-xl)">
      <div class="card-header border-b">
        <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
          <span class="material-symbols-outlined" style="color:var(--color-accent)">history</span>
          {{ t('settings.auditTitle') }}
        </h2>
        <button class="btn btn-secondary" @click="fetchAuditLogs" style="font-size:var(--font-size-xs)">
          <span class="material-symbols-outlined">sync</span>
        </button>
      </div>

      <div v-if="auditLoading" style="text-align:center;padding:var(--space-xl)">
        <div class="spinner" style="margin:0 auto"></div>
      </div>

      <div v-else-if="auditLogs.length === 0" class="empty-state">
        <span class="material-symbols-outlined">history</span>
        <h3>{{ t('settings.auditEmpty') }}</h3>
        <p>{{ t('settings.auditEmptyDesc') }}</p>
      </div>

      <div v-else class="table-wrap">
        <table class="data-table">
          <thead>
            <tr>
              <th>{{ t('settings.timestamp') }}</th>
              <th>{{ t('settings.hostNode') }}</th>
              <th>{{ t('settings.actionType') }}</th>
              <th>{{ t('settings.targetPayload') }}</th>
              <th>{{ t('common.status') }}</th>
              <th>{{ t('settings.executedAt') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="log in auditLogs" :key="log.id">
              <td style="white-space:nowrap;color:var(--color-text-secondary);font-size:var(--font-size-xs)">
                {{ formatDate(log.created_at) }}
              </td>
              <td style="font-weight:600">
                <router-link :to="`/hosts/${log.host_id}`" class="host-link">
                  {{ log.host_name || 'System' }}
                </router-link>
              </td>
              <td>
                <span class="action-type">{{ log.type }}</span>
              </td>
              <td style="max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">
                <code class="mono-payload" :title="log.payload">{{ log.payload }}</code>
              </td>
              <td>
                <span class="badge" :class="stateClass(log.state)">
                  <span class="badge-dot" v-if="log.state === 'pending'"></span>
                  {{ log.state }}
                </span>
              </td>
              <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
                {{ log.executed_at ? formatDate(log.executed_at) : 'Pending execution' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { useAuthStore } from '@/stores/auth.js'
import { api } from '@/plugins/axios.js'
import { formatDate } from '@/utils/format.js'
import { useI18n } from '@/utils/i18n.js'

const hostStore = useHostStore()
const authStore = useAuthStore()
const { t } = useI18n()

const newPassword = ref('')
const confirmPassword = ref('')
const passLoading = ref(false)
const passSuccess = ref(false)
const passError = ref('')

async function handleChangePassword() {
  if (newPassword.value !== confirmPassword.value) {
    passError.value = 'Passwords do not match.'
    return
  }
  if (newPassword.value.length < 6) {
    passError.value = 'Password must be at least 6 characters long.'
    return
  }
  
  passLoading.value = true
  passError.value = ''
  passSuccess.value = false
  try {
    await api.post('/profile/change-password', { password: newPassword.value })
    passSuccess.value = true
    newPassword.value = ''
    confirmPassword.value = ''
  } catch (err) {
    passError.value = err.response?.data?.error || 'Failed to update password.'
  } finally {
    passLoading.value = false
  }
}

const loading = ref(false)
const generatedToken = ref('')
const showToken = ref(false)
const copied = ref(false)

const brokerLoading = ref(false)
const generatedBrokerToken = ref('')
const showBrokerToken = ref(false)
const copiedBroker = ref(false)

const diagnostics = ref({})
const diagnosticsLoading = ref(false)
const diagnosticsError = ref(false)

onMounted(() => {
  fetchDiagnostics()
  fetchAuditLogs()
})

const auditLogs = ref([])
const auditLoading = ref(false)

async function fetchAuditLogs() {
  auditLoading.value = true
  try {
    const res = await api.get('/admin/changes')
    auditLogs.value = res.data.data || []
  } catch (err) {
    console.error('Failed to fetch audit logs:', err)
  } finally {
    auditLoading.value = false
  }
}

function stateClass(state) {
  if (state === 'executed') return 'online'
  if (state === 'failed') return 'offline'
  return 'warning'
}

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

async function generateBrokerTokenAction() {
  brokerLoading.value = true
  showBrokerToken.value = false
  copiedBroker.value = false
  try {
    const token = await hostStore.generateBrokerToken()
    if (token) {
      generatedBrokerToken.value = token
    }
  } catch (err) {
    console.error('Failed to generate broker token:', err)
  } finally {
    brokerLoading.value = false
  }
}

function copyBrokerToken() {
  if (!generatedBrokerToken.value) return
  navigator.clipboard.writeText(generatedBrokerToken.value)
  copiedBroker.value = true
  setTimeout(() => {
    copiedBroker.value = false
  }, 2000)
}
</script>

<style scoped>
.settings-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: var(--space-lg);
  align-items: start;
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

.host-link {
  color: var(--color-text);
  text-decoration: none;
  transition: color var(--transition-fast);
}

.host-link:hover {
  color: var(--color-accent);
}

.action-type {
  font-weight: 600;
  font-size: var(--font-size-xs);
  color: var(--color-accent);
  background: rgba(79, 110, 247, 0.08);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}

.mono-payload {
  font-family: monospace;
  font-size: 11px;
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: 4px;
}
</style>
