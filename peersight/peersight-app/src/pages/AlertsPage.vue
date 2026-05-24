<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">{{ t('alerts.title') }}</h1>
      <div style="display:flex;gap:var(--space-sm);align-items:center;flex-wrap:wrap">
        <select v-model="filter" class="form-input" style="width:auto;margin:0" @change="selectedIds = []">
          <option value="all">{{ t('alerts.all') }}</option>
          <option value="active">{{ t('alerts.activeAlerts') }}</option>
          <option value="resolved">{{ t('alerts.resolvedAlerts') }}</option>
        </select>
        <select v-model="levelFilter" class="form-input" style="width:auto;margin:0" @change="selectedIds = []">
          <option value="">All levels</option>
          <option value="critical">Critical</option>
          <option value="warning">Warning</option>
          <option value="info">Info</option>
        </select>
        <input
          v-model.trim="typeFilter"
          class="form-input"
          style="width:180px;margin:0"
          placeholder="Type"
          @input="selectedIds = []"
        />
        
        <button
          v-if="hasActiveAlerts"
          class="btn btn-secondary"
          @click="handleResolveAllActive"
          style="display:flex;align-items:center;gap:6px;color:#a3e635;border-color:rgba(163,230,53,.2)"
        >
          <span class="material-symbols-outlined" style="font-size:18px">done_all</span>
          {{ t('alerts.resolveAllActive') }}
        </button>

        <button class="btn btn-secondary" @click="fetchAlertsWithFilters">
          <span class="material-symbols-outlined">refresh</span>
          {{ t('common.refresh') }}
        </button>
      </div>
    </div>

    <!-- Bulk Selection Banner -->
    <Transition name="fade">
      <div v-if="selectedIds.length > 0" class="bulk-banner">
        <div style="display:flex;align-items:center;gap:12px">
          <span class="material-symbols-outlined" style="color:var(--color-accent)">check_box</span>
          <span class="banner-text"><strong>{{ selectedIds.length }}</strong> {{ t('alerts.selectedAlerts') }}</span>
        </div>
        <div style="display:flex;gap:10px">
          <button class="btn btn-secondary" @click="selectedIds = []" style="padding:6px 14px;font-size:var(--font-size-sm)">
            {{ t('alerts.clearSelection') }}
          </button>
          <button class="btn btn-primary" @click="handleResolveSelected" style="padding:6px 16px;font-size:var(--font-size-sm);display:flex;align-items:center;gap:6px">
            <span class="material-symbols-outlined" style="font-size:16px">check</span>
            {{ t('alerts.resolveSelected') }}
          </button>
        </div>
      </div>
    </Transition>

    <div v-if="alertStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="filteredAlerts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">check_circle</span>
      <h3>{{ t('alerts.noAlertsTitle') }}</h3>
      <p>{{ t('dashboard.smoothRunning') }}</p>
    </div>

    <div v-else class="card animate-fade" style="padding: 0; overflow: hidden;">
      <div class="table-responsive">
        <table class="data-table resizable-table">
          <thead>
            <tr>
              <th style="width:40px; min-width:40px; max-width:40px; text-align:center">
                <input
                  type="checkbox"
                  class="checkbox-custom"
                  :checked="isAllSelected"
                  :disabled="unselectedFilteredAlerts.length === 0"
                  @change="toggleSelectAll"
                />
              </th>
              <th :style="{ width: colWidths.level + 'px' }">
                {{ t('common.level') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'level' }" @mousedown.stop.prevent="startResize($event, 'level')"></div>
              </th>
              <th :style="{ width: colWidths.type + 'px' }">
                {{ t('common.type') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'type' }" @mousedown.stop.prevent="startResize($event, 'type')"></div>
              </th>
              <th :style="{ width: colWidths.message + 'px' }">
                {{ t('common.message') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'message' }" @mousedown.stop.prevent="startResize($event, 'message')"></div>
              </th>
              <th :style="{ width: colWidths.time + 'px' }">
                {{ t('common.time') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'time' }" @mousedown.stop.prevent="startResize($event, 'time')"></div>
              </th>
              <th :style="{ width: colWidths.status + 'px' }">
                {{ t('common.status') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'status' }" @mousedown.stop.prevent="startResize($event, 'status')"></div>
              </th>
              <th :style="{ width: colWidths.actions + 'px' }">
                {{ t('users.actions') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'actions' }" @mousedown.stop.prevent="startResize($event, 'actions')"></div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="alert in filteredAlerts" :key="alert.id" :class="{ 'row-selected': selectedIds.includes(alert.id) }">
              <td style="text-align:center">
                <input
                  v-if="!alert.resolved"
                  type="checkbox"
                  class="checkbox-custom"
                  :value="alert.id"
                  v-model="selectedIds"
                />
                <span v-else class="disabled-chk">
                  <span class="material-symbols-outlined" style="font-size:16px;color:var(--color-text-muted)">done</span>
                </span>
              </td>
              <td>
                <span class="badge" :class="levelClass(alert.level)">
                  <span class="material-symbols-outlined" style="font-size:12px">{{ levelIcon(alert.level) }}</span>
                  {{ alert.level }}
                </span>
              </td>
              <td style="font-weight:600">{{ alert.type }}</td>
              <td :title="alert.message">
                {{ alert.message }}
              </td>
              <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
                {{ formatTime(alert.created_at) }}
              </td>
              <td>
                <span v-if="alert.resolved" class="badge online">
                  <span class="material-symbols-outlined" style="font-size:12px">check</span>
                  {{ t('common.resolved') }}
                </span>
                <span v-else class="badge warning">
                  <span class="badge-dot"></span>
                  {{ t('alerts.activeAlerts') }}
                </span>
              </td>
              <td>
                <button
                  v-if="!alert.resolved"
                  class="btn btn-secondary"
                  style="font-size:var(--font-size-xs);padding:4px 10px;display:flex;align-items:center;gap:4px"
                  @click="resolve(alert.id)"
                >
                  <span class="material-symbols-outlined" style="font-size:14px">check</span>
                  {{ t('alerts.resolve') }}
                </button>
                <span v-else style="color:var(--color-text-muted);font-size:var(--font-size-xs)">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useAlertStore } from '@/stores/data.js'
import { formatTime, alertClass as levelClass, alertIcon as levelIcon } from '@/utils/format.js'
import { useI18n } from '@/utils/i18n.js'

const alertStore = useAlertStore()
const { t } = useI18n()
const filter = ref('all')
const levelFilter = ref('')
const typeFilter = ref('')
const selectedIds = ref([])

// Resizable column widths (like Excel)
const colWidths = ref({
  level: 120,
  type: 180,
  message: 420,
  time: 160,
  status: 120,
  actions: 110
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

onMounted(() => fetchAlertsWithFilters())

watch([filter, levelFilter, typeFilter], () => {
  fetchAlertsWithFilters()
})

const filteredAlerts = computed(() => {
  return alertStore.alerts
})

function fetchAlertsWithFilters() {
  const params = { limit: 200 }
  if (filter.value !== 'all') params.status = filter.value
  if (levelFilter.value) params.level = levelFilter.value
  if (typeFilter.value) params.type = typeFilter.value
  return alertStore.fetchAlerts(params)
}

const unselectedFilteredAlerts = computed(() => {
  return filteredAlerts.value.filter(a => !a.resolved)
})

const isAllSelected = computed(() => {
  const activeFiltered = unselectedFilteredAlerts.value
  if (activeFiltered.length === 0) return false
  return activeFiltered.every(a => selectedIds.value.includes(a.id))
})

const hasActiveAlerts = computed(() => {
  return alertStore.alerts.some(a => !a.resolved)
})

function toggleSelectAll() {
  const activeFiltered = unselectedFilteredAlerts.value
  if (isAllSelected.value) {
    selectedIds.value = selectedIds.value.filter(id => !activeFiltered.some(a => a.id === id))
  } else {
    activeFiltered.forEach(a => {
      if (!selectedIds.value.includes(a.id)) {
        selectedIds.value.push(a.id)
      }
    })
  }
}

async function resolve(id) {
  await alertStore.resolveAlert(id)
  selectedIds.value = selectedIds.value.filter(selectedId => selectedId !== id)
}

async function handleResolveSelected() {
  if (selectedIds.value.length === 0) return
  await alertStore.resolveAlertsBulk(selectedIds.value)
  selectedIds.value = []
}

async function handleResolveAllActive() {
  const activeIds = alertStore.alerts.filter(a => !a.resolved).map(a => a.id)
  if (activeIds.length === 0) return
  await alertStore.resolveAlertsBulk(activeIds)
  selectedIds.value = []
}
</script>

<style scoped>
.bulk-banner {
  background: var(--color-bg-card, #1e1e24);
  border: 1px solid var(--color-accent, #5865f2);
  border-radius: var(--radius-md, 8px);
  padding: 10px 18px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-md);
  box-shadow: 0 4px 20px rgba(88,101,242,0.15);
}

.banner-text {
  font-size: var(--font-size-sm);
  color: var(--color-text);
}

.checkbox-custom {
  appearance: none;
  background-color: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  padding: 8px;
  border-radius: 4px;
  display: inline-block;
  position: relative;
  cursor: pointer;
  outline: none;
  transition: border-color var(--transition-fast), background-color var(--transition-fast);
}

.checkbox-custom:checked {
  background-color: var(--color-accent, #5865f2);
  border-color: var(--color-accent, #5865f2);
}

.checkbox-custom:checked::after {
  content: '\e5ca';
  font-family: 'Material Symbols Outlined';
  font-weight: 900;
  font-size: 13px;
  color: #fff;
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
}

.checkbox-custom:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.row-selected {
  background-color: rgba(88, 101, 242, 0.04);
}

.disabled-chk {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  background: rgba(255,255,255,0.02);
  border-radius: 4px;
}

.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}

/* Fade transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.22s ease, transform 0.22s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  transform: translateY(-8px);
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
</style>
