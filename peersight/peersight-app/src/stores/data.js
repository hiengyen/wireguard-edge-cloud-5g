import { defineStore } from 'pinia'
import { ref } from 'vue'
import { api } from '@/plugins/axios.js'

export const useHostStore = defineStore('hosts', () => {
  const hosts = ref([])
  const loading = ref(false)

  async function fetchHosts() {
    loading.value = true
    try {
      const res = await api.get('/hosts')
      hosts.value = res.data.data || []
    } finally {
      loading.value = false
    }
  }

  async function createHost(name) {
    loading.value = true
    try {
      const res = await api.post('/hosts', { name })
      if (res.data && res.data.data) {
        hosts.value.unshift(res.data.data)
        return res.data.data
      }
    } finally {
      loading.value = false
    }
  }

  async function generateAgentToken() {
    const res = await api.post('/admin/agent-tokens')
    return res.data?.agent_token || null
  }

  async function updateHost(id, name) {
    const res = await api.put(`/hosts/${id}`, { name })
    const updated = res.data?.data
    if (updated) {
      const idx = hosts.value.findIndex(h => h.id === id)
      if (idx !== -1) hosts.value[idx] = updated
    }
    return updated
  }

  async function deleteHost(id) {
    await api.delete(`/hosts/${id}`)
    hosts.value = hosts.value.filter(h => h.id !== id)
  }

  return { hosts, loading, fetchHosts, createHost, generateAgentToken, updateHost, deleteHost }
})

export const usePeerStore = defineStore('peers', () => {
  const peers = ref([])
  const loading = ref(false)

  async function fetchPeers() {
    loading.value = true
    try {
      const res = await api.get('/peers')
      peers.value = res.data.data || []
    } finally {
      loading.value = false
    }
  }

  async function deletePeer(id) {
    await api.delete(`/peers/${id}`)
    peers.value = peers.value.filter(p => p.id !== id)
  }

  return { peers, loading, fetchPeers, deletePeer }
})

export const useAlertStore = defineStore('alerts', () => {
  const alerts = ref([])
  const loading = ref(false)

  async function fetchAlerts() {
    loading.value = true
    try {
      const res = await api.get('/alerts')
      alerts.value = res.data.data || []
    } finally {
      loading.value = false
    }
  }

  async function resolveAlert(id) {
    await api.post(`/alerts/${id}/resolve`)
    const alert = alerts.value.find(a => a.id === id)
    if (alert) alert.resolved = true
  }

  return { alerts, loading, fetchAlerts, resolveAlert }
})

export const useUserStore = defineStore('users', () => {
  const users = ref([])
  const loading = ref(false)

  async function fetchUsers() {
    loading.value = true
    try {
      const res = await api.get('/admin/users')
      users.value = res.data.data || []
    } finally {
      loading.value = false
    }
  }

  async function updateUserRole(id, role) {
    await api.put(`/admin/users/${id}/role`, { role })
    const user = users.value.find(u => u.id === id)
    if (user) user.role = role
  }

  async function createUser(payload) {
    const res = await api.post('/admin/users', payload)
    if (res.data) {
      users.value.unshift({
        id: res.data.user_id,
        email: res.data.email,
        role: res.data.role,
        created_at: new Date().toISOString()
      })
    }
  }

  async function deleteUser(id) {
    await api.delete(`/admin/users/${id}`)
    users.value = users.value.filter(u => u.id !== id)
  }

  return { users, loading, fetchUsers, createUser, updateUserRole, deleteUser }
})
