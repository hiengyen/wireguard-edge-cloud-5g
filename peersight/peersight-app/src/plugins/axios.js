import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || '/api',
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' }
})

// Request interceptor: attach JWT token
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('peersight_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Track whether a refresh is already in progress to avoid infinite loops
let isRefreshing = false
let failedQueue = []

function processQueue(error, token = null) {
  failedQueue.forEach(prom => {
    if (token) {
      prom.resolve(token)
    } else {
      prom.reject(error)
    }
  })
  failedQueue = []
}

// Response interceptor: auto-refresh token on 401
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config

    // If 401 and not already retrying, attempt token refresh
    if (error.response?.status === 401 && !originalRequest._retry) {
      // Don't try to refresh if the failing request IS the refresh request
      if (originalRequest.url === '/sessions/refresh') {
        localStorage.removeItem('peersight_token')
        localStorage.removeItem('peersight_refresh_token')
        window.location.href = '/login'
        return Promise.reject(error)
      }

      if (isRefreshing) {
        // Queue this request until the refresh completes
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject })
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`
          return api(originalRequest)
        })
      }

      originalRequest._retry = true
      isRefreshing = true

      const refreshToken = localStorage.getItem('peersight_refresh_token')
      if (!refreshToken) {
        localStorage.removeItem('peersight_token')
        window.location.href = '/login'
        return Promise.reject(error)
      }

      try {
        const res = await api.post('/sessions/refresh', { refresh_token: refreshToken })
        const newToken = res.data.token

        localStorage.setItem('peersight_token', newToken)
        localStorage.setItem('peersight_refresh_token', res.data.refresh_token)
        localStorage.setItem('peersight_user_id', res.data.user_id)
        localStorage.setItem('peersight_role', res.data.role)

        originalRequest.headers.Authorization = `Bearer ${newToken}`
        processQueue(null, newToken)

        return api(originalRequest)
      } catch (refreshError) {
        processQueue(refreshError, null)
        localStorage.removeItem('peersight_token')
        localStorage.removeItem('peersight_refresh_token')
        window.location.href = '/login'
        return Promise.reject(refreshError)
      } finally {
        isRefreshing = false
      }
    }

    return Promise.reject(error)
  }
)

export default {
  install(app) {
    app.config.globalProperties.$api = api
    app.provide('api', api)
  }
}

export { api }
