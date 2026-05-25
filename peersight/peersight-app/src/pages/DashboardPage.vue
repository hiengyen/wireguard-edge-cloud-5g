<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">{{ t('dashboard.title') }}</h1>
      <button class="btn btn-secondary" @click="refresh">
        <span class="material-symbols-outlined">refresh</span>
        {{ t('common.refresh') }}
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
          <div class="stat-label">{{ t('dashboard.hosts') }}</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon green">
          <span class="material-symbols-outlined">hub</span>
        </div>
        <div>
          <div class="stat-value">{{ peerStore.peers.length }}</div>
          <div class="stat-label">{{ t('dashboard.peers') }}</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon green">
          <span class="material-symbols-outlined">wifi</span>
        </div>
        <div>
          <div class="stat-value">{{ onlineHosts }}</div>
          <div class="stat-label">{{ t('dashboard.online') }}</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon yellow">
          <span class="material-symbols-outlined">swap_calls</span>
        </div>
        <div>
          <div class="stat-value" style="font-size:var(--font-size-md);line-height:1.2;font-weight:700;white-space:nowrap">{{ totalBandwidth }}</div>
          <div class="stat-label">{{ t('dashboard.networkFlow') }}</div>
        </div>
      </div>

      <div class="stat-card">
        <div class="stat-icon red">
          <span class="material-symbols-outlined">warning</span>
        </div>
        <div>
          <div class="stat-value">{{ unresolvedAlerts }}</div>
          <div class="stat-label">{{ t('dashboard.activeAlerts') }}</div>
        </div>
      </div>
    </div>

    <!-- Charts Row -->
    <div class="charts-row">
      <div class="card chart-card">
        <div class="card-header">
          <h2 class="card-title">{{ t('hosts.title') }}</h2>
        </div>
        <div class="chart-container">
          <canvas ref="statusChartEl"></canvas>
        </div>
      </div>

      <div class="card chart-card">
        <div class="card-header">
          <h2 class="card-title">{{ t('alerts.title') }}</h2>
        </div>
        <div class="chart-container">
          <canvas ref="alertChartEl"></canvas>
        </div>
      </div>
    </div>

    <!-- Topology Map -->
    <div class="card" style="margin-bottom: var(--space-xl)">
      <div class="card-header border-b">
        <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
          <span class="material-symbols-outlined" style="color:var(--color-accent)">hub</span>
          {{ t('dashboard.topologyMap') }}
        </h2>
      </div>
      <div class="card-body topology-card-body">
        <div class="topology-container">
          <svg class="topo-svg" :viewBox="isMobile ? '0 0 400 500' : '0 0 800 400'">
            <!-- Connection Lines -->
            <g v-for="node in hostNodes" :key="'line-' + node.id">
              <path
                :d="getConnectionPath(node)"
                :class="['connection-line', isOnline(node) ? 'active' : 'inactive']"
              />
              <!-- Animated glowing flow indicator -->
              <circle
                v-if="isOnline(node)"
                r="5"
                fill="var(--color-accent, #5865f2)"
                class="flow-particle"
              >
                <animateMotion
                  :path="getConnectionPath(node)"
                  dur="4s"
                  repeatCount="indefinite"
                />
              </circle>
            </g>

            <!-- Central Hub -->
            <g :transform="`translate(${isMobile ? 200 : 400}, ${isMobile ? 250 : 200})`" class="topo-node central-hub">
              <circle r="40" fill="rgba(88, 101, 242, 0.12)" stroke="var(--color-accent)" stroke-width="2" />
              <circle r="30" fill="rgba(88, 101, 242, 0.25)" />
              <text class="material-symbols-outlined" font-size="34" text-anchor="middle" y="11" fill="var(--color-accent)">
                cloud
              </text>
              <text y="58" text-anchor="middle" fill="var(--color-text)" font-size="12" font-weight="700">{{ t('dashboard.nodeHub') }}</text>
            </g>

            <!-- Edge Nodes -->
            <g
              v-for="node in hostNodes"
              :key="'node-' + node.id"
              :transform="`translate(${node.x}, ${node.y})`"
              class="topo-node edge-node"
              @click="$router.push(`/hosts/${node.id}`)"
            >
              <circle r="28" :fill="isOnline(node) ? 'rgba(52, 211, 153, 0.1)' : 'rgba(239, 68, 68, 0.1)'" :stroke="isOnline(node) ? '#34d399' : '#f87171'" stroke-width="1.5" />
              <circle r="20" :fill="isOnline(node) ? 'rgba(52, 211, 153, 0.2)' : 'rgba(239, 68, 68, 0.2)'" />
              <text class="material-symbols-outlined" font-size="20" text-anchor="middle" y="7" :fill="isOnline(node) ? '#34d399' : '#f87171'">
                router
              </text>
              <text y="46" text-anchor="middle" fill="var(--color-text-secondary)" font-size="11" font-weight="600">
                {{ node.name }}
              </text>
              <rect x="-26" y="-44" width="52" height="14" rx="4" :fill="isOnline(node) ? 'rgba(52,211,153,0.1)' : 'rgba(239,68,68,0.1)'" />
              <text y="-34" text-anchor="middle" :fill="isOnline(node) ? '#34d399' : '#f87171'" font-size="8" font-weight="700">
                {{ isOnline(node) ? 'ONLINE' : 'OFFLINE' }}
              </text>
            </g>
          </svg>
        </div>
      </div>
    </div>

    <!-- Recent Hosts -->
    <div class="card" style="margin-bottom: var(--space-xl)">
      <div class="card-header">
        <h2 class="card-title">{{ t('dashboard.recentActivity') }} ({{ t('hosts.title') }})</h2>
        <router-link to="/hosts" class="btn btn-secondary" style="font-size:var(--font-size-xs)">
          {{ t('nav.hosts') }}
        </router-link>
      </div>
      <div v-if="hostStore.loading" style="text-align:center;padding:var(--space-xl)">
        <div class="spinner" style="margin:0 auto"></div>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>{{ t('hosts.hostName') }}</th>
            <th>Agent Version</th>
            <th>{{ t('hosts.lastSeen') }}</th>
            <th>{{ t('common.status') }}</th>
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
                {{ isOnline(host) ? t('common.online') : t('common.offline') }}
              </span>
            </td>
          </tr>
          <tr v-if="recentHosts.length === 0">
            <td colspan="4" style="text-align:center;color:var(--color-text-muted);padding:var(--space-xl)">
              {{ t('hosts.noInterfaces') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Recent Alerts -->
    <div class="card">
      <div class="card-header">
        <h2 class="card-title">{{ t('dashboard.recentAlerts') }}</h2>
        <router-link to="/alerts" class="btn btn-secondary" style="font-size:var(--font-size-xs)">
          {{ t('nav.alerts') }}
        </router-link>
      </div>
      <table class="data-table">
        <thead>
          <tr>
            <th>{{ t('common.level') }}</th>
            <th>{{ t('common.message') }}</th>
            <th>{{ t('common.time') }}</th>
            <th>{{ t('common.status') }}</th>
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
              <span v-if="alert.resolved" class="badge online">{{ t('common.resolved') }}</span>
              <span v-else class="badge warning">{{ t('common.active') }}</span>
            </td>
          </tr>
          <tr v-if="recentAlerts.length === 0">
            <td colspan="4" style="text-align:center;color:var(--color-text-muted);padding:var(--space-xl)">
              {{ t('dashboard.noAlerts') }}
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
import { formatTime, isOnline, alertClass, alertIcon, formatBytes } from '@/utils/format.js'
import { useI18n } from '@/utils/i18n.js'
import { api } from '@/plugins/axios.js'

const hostStore = useHostStore()
const peerStore = usePeerStore()
const alertStore = useAlertStore()
const { locale, t } = useI18n()

// Responsive handling for Topology Map
const isMobile = ref(false)
function handleResize() {
  isMobile.value = window.innerWidth <= 768
}

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
  handleResize()
  window.addEventListener('resize', handleResize)
})

onUnmounted(() => {
  eventSource?.close()
  statusChart?.destroy()
  alertChart?.destroy()
  window.removeEventListener('resize', handleResize)
})

const totalRx = ref(0)
const totalTx = ref(0)

const totalBandwidth = computed(() => {
  return formatBytes(totalRx.value + totalTx.value)
})

async function fetchBandwidthStats() {
  totalRx.value = 0
  totalTx.value = 0
  try {
    const hosts = hostStore.hosts
    if (hosts.length === 0) return
    const promises = hosts.map(h => api.get(`/hosts/${h.id}/endpoints`))
    const results = await Promise.allSettled(promises)
    let rxSum = 0
    let txSum = 0
    results.forEach(res => {
      if (res.status === 'fulfilled') {
        const endpoints = res.value.data.data || []
        endpoints.forEach(ep => {
          rxSum += ep.rx_bytes || 0
          txSum += ep.tx_bytes || 0
        })
      }
    })
    totalRx.value = rxSum
    totalTx.value = txSum
  } catch (err) {
    console.error('Failed to aggregate dashboard bandwidth stats:', err)
  }
}

watch(() => hostStore.hosts, () => {
  fetchBandwidthStats()
}, { deep: true })

async function refresh() {
  await Promise.allSettled([
    hostStore.fetchHosts(),
    peerStore.fetchPeers(),
    alertStore.fetchAlerts()
  ])
  await fetchBandwidthStats()
}

const recentHosts = computed(() => hostStore.hosts.slice(0, 5))
const recentAlerts = computed(() => alertStore.alerts.slice(0, 5))

const onlineHosts = computed(() =>
  hostStore.hosts.filter(h => isOnline(h)).length
)

const unresolvedAlerts = computed(() =>
  alertStore.alerts.filter(a => !a.resolved).length
)

const hostNodes = computed(() => {
  const hosts = hostStore.hosts
  const count = hosts.length
  if (count === 0) return []

  const hx = isMobile.value ? 200 : 400
  const hy = isMobile.value ? 250 : 200
  const rx = isMobile.value ? 120 : 260
  const ry = isMobile.value ? 175 : 130 // Vertical ellipse on mobile, horizontal ellipse on desktop!

  return hosts.map((h, i) => {
    let angle
    if (isMobile.value) {
      if (count === 1) {
        angle = -Math.PI / 2 // Top
      } else if (count === 2) {
        angle = i === 0 ? -Math.PI / 2 : Math.PI / 2 // Top and Bottom
      } else {
        angle = (i * 2 * Math.PI) / count - Math.PI / 2
      }
    } else {
      if (count === 1) {
        angle = Math.PI // Left
      } else if (count === 2) {
        angle = i === 0 ? 0 : Math.PI // Right and Left
      } else {
        angle = (i * 2 * Math.PI) / count - Math.PI / 2
      }
    }

    const x = hx + rx * Math.cos(angle)
    const y = hy + ry * Math.sin(angle)

    return {
      ...h,
      x,
      y
    }
  })
})

function getConnectionPath(node) {
  const hx = isMobile.value ? 200 : 400
  const hy = isMobile.value ? 250 : 200
  const cx1 = (node.x + hx) / 2
  const cy1 = node.y
  const cx2 = (node.x + hx) / 2
  const cy2 = hy
  return `M ${node.x} ${node.y} C ${cx1} ${cy1}, ${cx2} ${cy2}, ${hx} ${hy}`
}

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
        labels: [t('common.online'), t('common.offline')],
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
        labels: [t('common.level') + ' Critical', t('common.level') + ' Warning', 'Info', t('common.resolved')],
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
watch(locale, () => {
  renderCharts()
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

.border-b {
  border-bottom: 1px solid var(--color-border);
  padding-bottom: var(--space-md);
  margin-bottom: var(--space-md);
}

.topology-card-body {
  padding: var(--space-xl);
  display: flex;
  justify-content: center;
  align-items: center;
  background: #0d0d12;
  border-radius: var(--radius-lg);
  overflow: hidden;
}

@media (max-width: 768px) {
  .topology-card-body {
    padding: var(--space-md);
  }
}

.topology-container {
  width: 100%;
  max-width: 800px;
  position: relative;
}

.topo-svg {
  width: 100%;
  height: auto;
  display: block;
}

.connection-line {
  fill: none;
  stroke-width: 1.5;
  transition: stroke 0.3s, stroke-width 0.3s;
}

.connection-line.active {
  stroke: rgba(88, 101, 242, 0.4);
  stroke-dasharray: 4 4;
  animation: dash 30s linear infinite;
}

.connection-line.inactive {
  stroke: rgba(239, 68, 68, 0.2);
  stroke-dasharray: 6 6;
}

@keyframes dash {
  to {
    stroke-dashoffset: -1000;
  }
}

.flow-particle {
  filter: drop-shadow(0 0 4px var(--color-accent));
}

.topo-node {
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
}

.topo-node:hover {
  transform: scale(1.08);
}

.edge-node text.material-symbols-outlined {
  font-family: 'Material Symbols Outlined';
  dominant-baseline: middle;
}

.central-hub {
  cursor: default;
}
.central-hub:hover {
  transform: none;
}
</style>
