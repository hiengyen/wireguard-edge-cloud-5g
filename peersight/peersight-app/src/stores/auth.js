import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { api } from '@/plugins/axios.js'

export const useAuthStore = defineStore('auth', () => {
  const token = ref(localStorage.getItem('peersight_token') || '')
  const refreshToken = ref(localStorage.getItem('peersight_refresh_token') || '')
  const userId = ref(localStorage.getItem('peersight_user_id') || '')
  const role = ref(localStorage.getItem('peersight_role') || '')

  const isLoggedIn = computed(() => !!token.value)
  const isAdmin = computed(() => role.value === 'admin')
  const userRole = computed(() => role.value)

  function setTokens(data) {
    token.value = data.token
    refreshToken.value = data.refresh_token
    userId.value = data.user_id
    role.value = data.role

    localStorage.setItem('peersight_token', data.token)
    localStorage.setItem('peersight_refresh_token', data.refresh_token)
    localStorage.setItem('peersight_user_id', data.user_id)
    localStorage.setItem('peersight_role', data.role)
  }

  async function login(email, password) {
    const res = await api.post('/sessions', { email, password })
    setTokens(res.data)
  }

  async function refresh() {
    if (!refreshToken.value) throw new Error('No refresh token')
    const res = await api.post('/sessions/refresh', {
      refresh_token: refreshToken.value
    })
    setTokens(res.data)
  }

  function logout() {
    token.value = ''
    refreshToken.value = ''
    userId.value = ''
    role.value = ''
    localStorage.removeItem('peersight_token')
    localStorage.removeItem('peersight_refresh_token')
    localStorage.removeItem('peersight_user_id')
    localStorage.removeItem('peersight_role')
  }

  return { token, refreshToken, userId, role, userRole, isLoggedIn, isAdmin, login, refresh, logout, setTokens }
})
