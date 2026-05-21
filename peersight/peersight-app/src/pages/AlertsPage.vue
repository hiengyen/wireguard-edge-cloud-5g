<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Alerts</h1>
      <div style="display:flex;gap:var(--space-sm)">
        <select v-model="filter" class="form-input" style="width:auto">
          <option value="all">All Alerts</option>
          <option value="active">Active</option>
          <option value="resolved">Resolved</option>
        </select>
        <button class="btn btn-secondary" @click="alertStore.fetchAlerts()">
          <span class="material-symbols-outlined">refresh</span>
          Refresh
        </button>
      </div>
    </div>

    <div v-if="alertStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="filteredAlerts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">check_circle</span>
      <h3>No Alerts</h3>
      <p>Everything is running smoothly.</p>
    </div>

    <div v-else class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Level</th>
            <th>Type</th>
            <th>Message</th>
            <th>Time</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="alert in filteredAlerts" :key="alert.id">
            <td>
              <span class="badge" :class="levelClass(alert.level)">
                <span class="material-symbols-outlined" style="font-size:12px">{{ levelIcon(alert.level) }}</span>
                {{ alert.level }}
              </span>
            </td>
            <td style="font-weight:500">{{ alert.type }}</td>
            <td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">
              {{ alert.message }}
            </td>
            <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs);white-space:nowrap">
              {{ formatTime(alert.created_at) }}
            </td>
            <td>
              <span v-if="alert.resolved" class="badge online">
                <span class="material-symbols-outlined" style="font-size:12px">check</span>
                Resolved
              </span>
              <span v-else class="badge warning">
                <span class="badge-dot"></span>
                Active
              </span>
            </td>
            <td>
              <button
                v-if="!alert.resolved"
                class="btn btn-secondary"
                style="font-size:var(--font-size-xs);padding:4px 10px"
                @click="resolve(alert.id)"
              >
                Resolve
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAlertStore } from '@/stores/data.js'
import { formatTime, alertClass as levelClass, alertIcon as levelIcon } from '@/utils/format.js'

const alertStore = useAlertStore()
const filter = ref('all')

onMounted(() => alertStore.fetchAlerts())

const filteredAlerts = computed(() => {
  if (filter.value === 'active') return alertStore.alerts.filter(a => !a.resolved)
  if (filter.value === 'resolved') return alertStore.alerts.filter(a => a.resolved)
  return alertStore.alerts
})

async function resolve(id) {
  await alertStore.resolveAlert(id)
}
</script>
