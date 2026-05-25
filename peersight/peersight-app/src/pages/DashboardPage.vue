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
      <div class="card-header border-b" style="display:flex;justify-content:space-between;align-items:center">
        <h2 class="card-title" style="display:flex;align-items:center;gap:8px">
          <span class="material-symbols-outlined" style="color:var(--color-accent)">hub</span>
          {{ t('dashboard.topologyMap') }}
        </h2>
        
        <!-- Floating graph control button -->
        <button class="btn btn-secondary" @click="showControls = !showControls" style="display:flex;align-items:center;gap:4px;font-size:12px;padding:4px 10px;height:auto">
          <span class="material-symbols-outlined" style="font-size:16px">tune</span>
          Graph Controls
        </button>
      </div>
      <div class="card-body topology-card-body">
        <!-- Floating Obsidian Graph Controls -->
        <div v-if="showControls" class="graph-controls-panel">
          <div class="controls-header">
            <h4>Graph Physics</h4>
            <button class="icon-btn-close" @click="showControls = false">
              <span class="material-symbols-outlined" style="font-size:14px">close</span>
            </button>
          </div>
          <div class="control-group">
            <div class="label-row">
              <span>Repulsion</span>
              <code>{{ graphRepulsion }}</code>
            </div>
            <input type="range" min="1000" max="15000" step="500" v-model.number="graphRepulsion" />
          </div>
          <div class="control-group">
            <div class="label-row">
              <span>Link Distance</span>
              <code>{{ graphLinkDist }}px</code>
            </div>
            <input type="range" min="50" max="250" step="10" v-model.number="graphLinkDist" />
          </div>
          <div class="control-group">
            <div class="label-row">
              <span>Gravity</span>
              <code>{{ graphGravity }}</code>
            </div>
            <input type="range" min="0.001" max="0.05" step="0.001" v-model.number="graphGravity" />
          </div>
        </div>

        <div class="topology-container">
          <svg class="topo-svg" :viewBox="isMobile ? '0 0 400 500' : '0 0 800 400'">
            <!-- Connection Lines -->
            <g v-for="node in nodesList" :key="'line-' + node.id">
              <path
                v-if="!node.isHub"
                :d="getConnectionPath(node)"
                :class="['connection-line', node.status === 'online' ? 'active' : 'inactive']"
              />
              <!-- Animated glowing flow indicator -->
              <circle
                v-if="!node.isHub && node.status === 'online'"
                r="3"
                fill="#818cf8"
                class="flow-particle"
              >
                <animateMotion
                  :path="getConnectionPath(node)"
                  dur="4s"
                  repeatCount="indefinite"
                />
              </circle>
            </g>

            <!-- Central Hub (Cloud Gateway) -->
            <g
              v-if="hubNode"
              :transform="`translate(${hubNode.x}, ${hubNode.y})`"
              class="topo-node central-hub"
              @mousedown="startDrag($event, hubNode)"
              @touchstart.passive="startDrag($event, hubNode)"
            >
              <circle r="36" fill="rgba(99, 102, 241, 0.15)" stroke="var(--color-accent)" stroke-width="1.5" class="outer-glow" />
              <circle r="20" fill="var(--color-accent)" />
              <text class="material-symbols-outlined" font-size="22" text-anchor="middle" y="7" fill="#ffffff">
                cloud
              </text>
              <text y="50" text-anchor="middle" fill="#ffffff" font-size="11" font-weight="700">{{ hubNode.name }}</text>
            </g>

            <!-- Edge Nodes (Obsidian Sleek Dot Style) -->
            <g
              v-for="node in edgeNodesOnly"
              :key="'node-' + node.id"
              :transform="`translate(${node.x}, ${node.y})`"
              class="topo-node edge-node"
              @mousedown="startDrag($event, node)"
              @touchstart.passive="startDrag($event, node)"
              @dblclick="$router.push(`/hosts/${node.id}`)"
            >
              <!-- Glowing outer ring -->
              <circle
                r="18"
                :fill="node.status === 'online' ? 'rgba(52, 211, 153, 0.15)' : 'rgba(239, 68, 68, 0.15)'"
                :stroke="node.status === 'online' ? 'rgba(52, 211, 153, 0.3)' : 'rgba(239, 68, 68, 0.3)'"
                stroke-width="1"
                class="outer-ring"
              />
              <!-- Solid core dot -->
              <circle
                r="6"
                :fill="node.status === 'online' ? '#34d399' : '#f87171'"
                class="core-dot"
              />
              <!-- Node Label -->
              <text
                y="30"
                text-anchor="middle"
                class="node-label"
              >
                {{ node.name }}
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
      refresh()
    })

    eventSource.onerror = () => {
      // Reconnect after 10 seconds
      eventSource?.close()
      setTimeout(connectSSE, 10000)
    }
  } catch {
    // SSE not available, fallback to polling
    setInterval(() => {
      refresh()
    }, 30000)
  }
}

// Graph View States & Configuration (Obsidian Style)
const showControls = ref(false)
const graphGravity = ref(0.01)
const graphRepulsion = ref(8000)
const graphLinkDist = ref(120)

const nodesList = ref([])
let physicsFrameId = null
const draggedNode = ref(null)

const edgeNodesOnly = computed(() => nodesList.value.filter(n => !n.isHub))
const hubNode = computed(() => nodesList.value.find(n => n.isHub) || null)

function initOrUpdateNodes() {
  const hosts = hostStore.hosts
  const width = isMobile.value ? 400 : 800
  const height = isMobile.value ? 500 : 400
  const centerX = width / 2
  const centerY = height / 2

  let hub = nodesList.value.find(n => n.isHub)
  if (!hub) {
    hub = {
      id: 'hub',
      name: 'VPN Cloud HUB',
      isHub: true,
      x: centerX,
      y: centerY,
      vx: 0,
      vy: 0,
      isDragging: false,
      status: 'online'
    }
  } else {
    if (!hub.isDragging) {
      hub.x = centerX
      hub.y = centerY
    }
  }

  const newNodes = [hub]

  hosts.forEach(h => {
    let existing = nodesList.value.find(n => n.id === h.id)
    if (!existing) {
      const angle = Math.random() * Math.PI * 2
      const radius = 100 + Math.random() * 50
      existing = {
        id: h.id,
        name: h.name,
        isHub: false,
        x: centerX + Math.cos(angle) * radius,
        y: centerY + Math.sin(angle) * radius,
        vx: 0,
        vy: 0,
        isDragging: false,
        status: isOnline(h) ? 'online' : 'offline',
        agent_version: h.agent_version || h.agent_ver || ''
      }
    } else {
      existing.status = isOnline(h) ? 'online' : 'offline'
      existing.agent_version = h.agent_version || h.agent_ver || ''
    }
    newNodes.push(existing)
  })

  nodesList.value = newNodes
}

function updatePhysics() {
  const width = isMobile.value ? 400 : 800
  const height = isMobile.value ? 500 : 400
  const centerX = width / 2
  const centerY = height / 2

  const k = 0.05
  const restLength = graphLinkDist.value
  const repulsion = graphRepulsion.value
  const centerGravity = graphGravity.value
  const damping = 0.85

  for (let i = 0; i < nodesList.value.length; i++) {
    const nodeA = nodesList.value[i]
    if (nodeA.isDragging) continue

    const dxCenter = centerX - nodeA.x
    const dyCenter = centerY - nodeA.y
    nodeA.vx += dxCenter * centerGravity
    nodeA.vy += dyCenter * centerGravity

    for (let j = 0; j < nodesList.value.length; j++) {
      if (i === j) continue
      const nodeB = nodesList.value[j]

      const dx = nodeA.x - nodeB.x
      const dy = nodeA.y - nodeB.y
      const distSq = dx * dx + dy * dy + 0.1
      const dist = Math.sqrt(distSq)

      if (dist < 300) {
        const force = repulsion / distSq
        nodeA.vx += (dx / dist) * force
        nodeA.vy += (dy / dist) * force
      }
    }
  }

  const hub = nodesList.value.find(n => n.isHub)
  if (hub) {
    nodesList.value.forEach(node => {
      if (node.isHub || node.isDragging) return
      
      const dx = hub.x - node.x
      const dy = hub.y - node.y
      const dist = Math.sqrt(dx * dx + dy * dy) + 0.1
      
      const force = k * (dist - restLength)
      node.vx += (dx / dist) * force
      node.vy += (dy / dist) * force
    })
  }

  nodesList.value.forEach(node => {
    if (node.isDragging) {
      node.vx = 0
      node.vy = 0
      return
    }

    node.x += node.vx
    node.y += node.vy

    node.vx *= damping
    node.vy *= damping

    const padding = 40
    if (node.x < padding) { node.x = padding; node.vx *= -0.5; }
    if (node.x > width - padding) { node.x = width - padding; node.vx *= -0.5; }
    if (node.y < padding) { node.y = padding; node.vy *= -0.5; }
    if (node.y > height - padding) { node.y = height - padding; node.vy *= -0.5; }
  })

  physicsFrameId = requestAnimationFrame(updatePhysics)
}

function startDrag(event, node) {
  draggedNode.value = node
  node.isDragging = true

  const svg = document.querySelector('.topo-svg')
  if (!svg) return
  const rect = svg.getBoundingClientRect()

  const handleMove = (e) => {
    if (!draggedNode.value) return
    const clientX = e.touches ? e.touches[0].clientX : e.clientX
    const clientY = e.touches ? e.touches[0].clientY : e.clientY
    
    const scaleX = (isMobile.value ? 400 : 800) / rect.width
    const scaleY = (isMobile.value ? 500 : 400) / rect.height
    
    draggedNode.value.x = (clientX - rect.left) * scaleX
    draggedNode.value.y = (clientY - rect.top) * scaleY
  }

  const handleEnd = () => {
    if (draggedNode.value) {
      draggedNode.value.isDragging = false
      draggedNode.value = null
    }
    document.removeEventListener('mousemove', handleMove)
    document.removeEventListener('mouseup', handleEnd)
    document.removeEventListener('touchmove', handleMove)
    document.removeEventListener('touchend', handleEnd)
  }

  document.addEventListener('mousemove', handleMove)
  document.addEventListener('mouseup', handleEnd)
  document.addEventListener('touchmove', handleMove, { passive: false })
  document.addEventListener('touchend', handleEnd)
}

function getConnectionPath(node) {
  const hub = nodesList.value.find(n => n.isHub)
  if (!hub) return ''
  return `M ${node.x} ${node.y} L ${hub.x} ${hub.y}`
}

onMounted(() => {
  refresh()
  connectSSE()
  handleResize()
  window.addEventListener('resize', handleResize)
  
  initOrUpdateNodes()
  physicsFrameId = requestAnimationFrame(updatePhysics)
})

onUnmounted(() => {
  eventSource?.close()
  statusChart?.destroy()
  alertChart?.destroy()
  window.removeEventListener('resize', handleResize)
  
  if (physicsFrameId) {
    cancelAnimationFrame(physicsFrameId)
  }
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
  initOrUpdateNodes()
  fetchBandwidthStats()
}, { deep: true })

async function refresh() {
  await Promise.allSettled([
    hostStore.fetchHosts(),
    peerStore.fetchPeers(),
    alertStore.fetchAlerts()
  ])
  await fetchBandwidthStats()
  initOrUpdateNodes()
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

.topology-card-body {
  padding: var(--space-xl);
  display: flex;
  justify-content: center;
  align-items: center;
  background: #09090b !important; /* Obsidian black background */
  background-image: radial-gradient(rgba(255, 255, 255, 0.04) 1px, transparent 1px);
  background-size: 24px 24px;
  border-radius: var(--radius-lg);
  overflow: hidden;
  position: relative;
  min-height: 400px;
}

@media (max-width: 768px) {
  .topology-card-body {
    padding: var(--space-md);
    min-height: 500px;
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
  overflow: visible;
}

/* Connection lines */
.connection-line {
  fill: none;
  stroke-width: 1px;
  transition: stroke 0.3s, stroke-width 0.3s;
}

.connection-line.active {
  stroke: rgba(99, 102, 241, 0.25); /* Delicate indigo line */
}

.connection-line.inactive {
  stroke: rgba(239, 68, 68, 0.15); /* Delicate red line */
}

/* Glowing flow packets */
.flow-particle {
  filter: drop-shadow(0 0 5px #818cf8);
}

/* Dynamic Nodes */
.topo-node {
  cursor: grab;
}
.topo-node:active {
  cursor: grabbing;
}

/* Core dot and outer rings */
.topo-node .outer-ring {
  transition: r 0.2s, stroke-width 0.2s, fill 0.2s, stroke 0.2s;
}

.topo-node:hover .outer-ring {
  r: 22;
  stroke-width: 1.5px;
}

.topo-node.central-hub .outer-glow {
  animation: pulse-glow 3s infinite ease-in-out;
}

@keyframes pulse-glow {
  0%, 100% {
    r: 34;
    stroke-opacity: 0.3;
  }
  50% {
    r: 39;
    stroke-opacity: 0.6;
  }
}

/* Obsidian labels */
.node-label {
  fill: #a1a1aa; /* Obsidian zinc-400 */
  font-family: inherit;
  font-size: 11px;
  font-weight: 500;
  pointer-events: none;
  transition: fill 0.2s, text-shadow 0.2s;
}

.topo-node:hover .node-label {
  fill: #ffffff;
  text-shadow: 0 0 6px rgba(255, 255, 255, 0.6);
}

/* Floating Obsidian Controls Panel */
.graph-controls-panel {
  position: absolute;
  top: 16px;
  right: 16px;
  width: 220px;
  background: rgba(24, 24, 27, 0.85); /* zinc-900 glassmorphism */
  backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: var(--radius-md);
  padding: 14px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
  z-index: 10;
  display: flex;
  flex-direction: column;
  gap: 12px;
  animation: slideDownIn 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes slideDownIn {
  from {
    transform: translateY(-8px);
    opacity: 0;
  }
  to {
    transform: translateY(0);
    opacity: 1;
  }
}

.controls-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  padding-bottom: 6px;
}

.controls-header h4 {
  margin: 0;
  font-size: 12px;
  font-weight: 600;
  color: #f4f4f5;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.icon-btn-close {
  background: transparent;
  border: none;
  color: #a1a1aa;
  cursor: pointer;
  padding: 2px;
  border-radius: 4px;
  display: flex;
}

.icon-btn-close:hover {
  color: #ffffff;
  background: rgba(255, 255, 255, 0.06);
}

.control-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.control-group .label-row {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
}

.control-group .label-row span {
  color: #a1a1aa;
}

.control-group .label-row code {
  color: #818cf8;
  font-family: monospace;
}

.control-group input[type="range"] {
  width: 100%;
  height: 4px;
  background: #3f3f46;
  border-radius: 2px;
  outline: none;
  -webkit-appearance: none;
}

.control-group input[type="range"]::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #818cf8;
  cursor: pointer;
  transition: background 0.15s, transform 0.15s;
}

.control-group input[type="range"]::-webkit-slider-thumb:hover {
  background: #a5b4fc;
  transform: scale(1.15);
}
</style>
