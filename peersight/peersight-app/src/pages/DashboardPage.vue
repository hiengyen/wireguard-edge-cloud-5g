<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Dashboard</h1>
      <button class="btn btn-secondary" @click="refresh">
        <span class="material-symbols-outlined">refresh</span>
        Refresh
      </button>
    </div>

    <!-- Stat Cards -->
    <div class="stat-grid">
      <div class="stat-card">
        <div class="stat-icon blue">
          <span class="material-symbols-outlined">dns</span>
        </div>
        <div>
          <div class="stat-value">{{ hostStore.hosts.length }}</div>
          <div class="stat-label">Hosts</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon green">
          <span class="material-symbols-outlined">hub</span>
        </div>
        <div>
          <div class="stat-value">{{ peerStore.peers.length }}</div>
          <div class="stat-label">Peers</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon yellow">
          <span class="material-symbols-outlined">wifi</span>
        </div>
        <div>
          <div class="stat-value">{{ onlineHosts }}</div>
          <div class="stat-label">Online</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon red">
          <span class="material-symbols-outlined">warning</span>
        </div>
        <div>
          <div class="stat-value">{{ unresolvedAlerts }}</div>
          <div class="stat-label">Active Alerts</div>
        </div>
      </div>
    </div>

    <!-- Charts Row -->
    <div class="charts-row">
      <div class="card chart-card">
        <div class="card-header">
          <h2 class="card-title">Host Status</h2>
        </div>
        <div class="chart-container">
          <canvas ref="statusChartEl"></canvas>
        </div>
      </div>

      <div class="card chart-card">
        <div class="card-header">
          <h2 class="card-title">Alert Distribution</h2>
        </div>
        <div class="chart-container">
          <canvas ref="alertChartEl"></canvas>
        </div>
      </div>
    </div>

    <!-- Recent Hosts -->
    <div class="card" style="margin-bottom: var(--space-xl)">
      <div class="card-header">
        <h2 class="card-title">Recent Hosts</h2>
        <router-link to="/hosts" class="btn btn-secondary" style="font-size:var(--font-size-xs)">
          View All
        </router-link>
      </div>
      <div v-if="hostStore.loading" style="text-align:center;padding:var(--space-xl)">
        <div class="spinner" style="margin:0 auto"></div>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Agent Version</th>
            <th>Last Ping</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="host in recentHosts" :key="host.id" @click="$router.push(`/hosts/${host.id}`)" style="cursor:pointer">
            <td style="font-weight:500">{{ host.name }}</td>
            <td>
              <code style="font-size:var(--font-size-xs);color:var(--color-text-muted)">{{ host.agent_version || '—' }}</code>
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
          <tr v-if="recentHosts.length === 0">
            <td colspan="4" style="text-align:center;color:var(--color-text-muted);padding:var(--space-xl)">
              No hosts registered yet
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Recent Alerts -->
    <div class="card">
      <div class="card-header">
        <h2 class="card-title">Recent Alerts</h2>
        <router-link to="/alerts" class="btn btn-secondary" style="font-size:var(--font-size-xs)">
          View All
        </router-link>
      </div>
      <table class="data-table">
        <thead>
          <tr>
            <th>Level</th>
            <th>Message</th>
            <th>Time</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="alert in recentAlerts" :key="alert.id">
            <td>
              <span class="badge" :class="alertClass(alert.level)">{{ alert.level }}</span>
            </td>
            <td>{{ alert.message }}</td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
              {{ formatTime(alert.created_at) }}
            </td>
            <td>
              <span v-if="alert.resolved" class="badge online">Resolved</span>
              <span v-else class="badge warning">Active</span>
            </td>
          </tr>
          <tr v-if="recentAlerts.length === 0">
            <td colspan="4" style="text-align:center;color:var(--color-text-muted);padding:var(--space-xl)">
              No alerts
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Toast Notifications -->
    <Teleport to="body">
      <TransitionGroup name="toast" tag="div" class="toast-container">
        <div v-for="t in toasts" :key="t.id" class="toast" :class="t.level" @click="dismissToast(t.id)">
          <span class="material-symbols-outlined" style="font-size:18px">{{ alertIcon(t.level) }}</span>
          <span>{{ t.message }}</span>
        </div>
      </TransitionGroup>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useHostStore, usePeerStore, useAlertStore } from '@/stores/data.js'
import { formatTime, isOnline, alertClass, alertIcon } from '@/utils/format.js'

const hostStore = useHostStore()
const peerStore = usePeerStore()
const alertStore = useAlertStore()

// Chart refs
const statusChartEl = ref(null)
const alertChartEl = ref(null)
let statusChart = null
let alertChart = null

// Toast notifications
const toasts = ref([])
let toastId = 0

function addToast(level, message) {
  const id = ++toastId
  toasts.value.push({ id, level, message })
  setTimeout(() => dismissToast(id), 6000)
}

function dismissToast(id) {
  toasts.value = toasts.value.filter(t => t.id !== id)
}

// SSE connection for realtime alerts (#10)
let eventSource = null

function connectSSE() {
  const token = localStorage.getItem('peersight_token')
  const apiUrl = import.meta.env.VITE_API_URL || ''
  const url = `${apiUrl}/events/stream?token=${encodeURIComponent(token)}`

  try {
    eventSource = new EventSource(url)

    eventSource.addEventListener('alert', (e) => {
      try {
        const data = JSON.parse(e.data)
        addToast(data.level || 'info', data.message || 'New alert')
        alertStore.fetchAlerts()
      } catch { /* ignore parse errors */ }
    })

    eventSource.addEventListener('ping', () => {
      hostStore.fetchHosts()
    })

    eventSource.onerror = () => {
      // Reconnect after 10 seconds
      eventSource?.close()
      setTimeout(connectSSE, 10000)
    }
  } catch {
    // SSE not available, fallback to polling
    setInterval(() => {
      alertStore.fetchAlerts()
      hostStore.fetchHosts()
    }, 30000)
  }
}

onMounted(() => {
  refresh()
  connectSSE()
})

onUnmounted(() => {
  eventSource?.close()
  statusChart?.destroy()
  alertChart?.destroy()
})

function refresh() {
  hostStore.fetchHosts()
  peerStore.fetchPeers()
  alertStore.fetchAlerts()
}

const recentHosts = computed(() => hostStore.hosts.slice(0, 5))
const recentAlerts = computed(() => alertStore.alerts.slice(0, 5))

const onlineHosts = computed(() =>
  hostStore.hosts.filter(h => isOnline(h)).length
)

const unresolvedAlerts = computed(() =>
  alertStore.alerts.filter(a => !a.resolved).length
)

// Chart rendering
async function renderCharts() {
  const { Chart, DoughnutController, ArcElement, Tooltip, Legend, BarController, BarElement, CategoryScale, LinearScale } = await import('chart.js')
  Chart.register(DoughnutController, ArcElement, Tooltip, Legend, BarController, BarElement, CategoryScale, LinearScale)

  await nextTick()

  // Host status donut
  if (statusChartEl.value) {
    statusChart?.destroy()
    const online = onlineHosts.value
    const offline = hostStore.hosts.length - online
    statusChart = new Chart(statusChartEl.value, {
      type: 'doughnut',
      data: {
        labels: ['Online', 'Offline'],
        datasets: [{
          data: [online, offline],
          backgroundColor: ['#34d399', '#f87171'],
          borderColor: ['#059669', '#dc2626'],
          borderWidth: 2,
          hoverOffset: 6
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '65%',
        plugins: {
          legend: {
            position: 'bottom',
            labels: { color: '#8890a4', font: { family: 'Inter', size: 12 }, padding: 16 }
          }
        }
      }
    })
  }

  // Alert distribution bar chart
  if (alertChartEl.value) {
    alertChart?.destroy()
    const critical = alertStore.alerts.filter(a => a.level === 'critical' && !a.resolved).length
    const warning = alertStore.alerts.filter(a => a.level === 'warning' && !a.resolved).length
    const info = alertStore.alerts.filter(a => a.level === 'info' && !a.resolved).length
    const resolved = alertStore.alerts.filter(a => a.resolved).length

    alertChart = new Chart(alertChartEl.value, {
      type: 'bar',
      data: {
        labels: ['Critical', 'Warning', 'Info', 'Resolved'],
        datasets: [{
          data: [critical, warning, info, resolved],
          backgroundColor: ['rgba(248,113,113,0.7)', 'rgba(251,191,36,0.7)', 'rgba(96,165,250,0.7)', 'rgba(52,211,153,0.7)'],
          borderColor: ['#f87171', '#fbbf24', '#60a5fa', '#34d399'],
          borderWidth: 1,
          borderRadius: 6
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false }
        },
        scales: {
          x: {
            ticks: { color: '#8890a4', font: { family: 'Inter', size: 11 } },
            grid: { display: false }
          },
          y: {
            beginAtZero: true,
            ticks: { color: '#5c6378', stepSize: 1, font: { family: 'Inter', size: 11 } },
            grid: { color: 'rgba(42,46,66,0.5)' }
          }
        }
      }
    })
  }
}

// Watch for data changes and re-render charts
watch([() => hostStore.hosts.length, () => alertStore.alerts.length], () => {
  renderCharts()
}, { flush: 'post' })

watch([statusChartEl, alertChartEl], () => {
  if (statusChartEl.value && alertChartEl.value) renderCharts()
})
</script>

<style scoped>
.charts-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-md);
  margin-bottom: var(--space-xl);
}

.chart-card {
  padding: var(--space-lg);
}

.chart-container {
  height: 220px;
  position: relative;
}

@media (max-width: 768px) {
  .charts-row {
    grid-template-columns: 1fr;
  }
}

/* Toast notifications */
.toast-container {
  position: fixed;
  top: var(--space-lg);
  right: var(--space-lg);
  z-index: 9999;
  display: flex;
  flex-direction: column;
  gap: var(--space-sm);
  pointer-events: none;
}

.toast {
  display: flex;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-md);
  font-size: var(--font-size-sm);
  font-weight: 500;
  backdrop-filter: blur(12px);
  box-shadow: var(--shadow-lg);
  cursor: pointer;
  pointer-events: auto;
  min-width: 280px;
  animation: slideIn 0.3s ease;
}

.toast.critical, .toast.error {
  background: rgba(248, 113, 113, 0.15);
  border: 1px solid rgba(248, 113, 113, 0.4);
  color: #fca5a5;
}

.toast.warning {
  background: rgba(251, 191, 36, 0.15);
  border: 1px solid rgba(251, 191, 36, 0.4);
  color: #fde68a;
}

.toast.info {
  background: rgba(96, 165, 250, 0.15);
  border: 1px solid rgba(96, 165, 250, 0.4);
  color: #93c5fd;
}

.toast-enter-active { animation: slideIn 0.3s ease; }
.toast-leave-active { animation: slideOut 0.3s ease; }

@keyframes slideIn {
  from { transform: translateX(100%); opacity: 0; }
  to { transform: translateX(0); opacity: 1; }
}
@keyframes slideOut {
  from { transform: translateX(0); opacity: 1; }
  to { transform: translateX(100%); opacity: 0; }
}
</style>
