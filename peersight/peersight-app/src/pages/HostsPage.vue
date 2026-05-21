<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Hosts</h1>
      <button class="btn btn-secondary" @click="hostStore.fetchHosts()">
        <span class="material-symbols-outlined">refresh</span>
        Refresh
      </button>
    </div>

    <div v-if="hostStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else-if="hostStore.hosts.length === 0" class="empty-state">
      <span class="material-symbols-outlined">dns</span>
      <h3>No Hosts Registered</h3>
      <p>Install the peersight-agent on a WireGuard host to get started.</p>
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
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import { useHostStore } from '@/stores/data.js'
import { shortId, isOnline, formatTime } from '@/utils/format.js'

const hostStore = useHostStore()
onMounted(() => hostStore.fetchHosts())
</script>

<style scoped>
.mono-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}
</style>
