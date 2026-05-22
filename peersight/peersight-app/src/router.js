import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth.js'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/pages/LoginPage.vue'),
    meta: { public: true }
  },
  {
    path: '/signup',
    name: 'Signup',
    component: () => import('@/pages/SignupPage.vue'),
    meta: { public: true }
  },
  {
    path: '/',
    name: 'Dashboard',
    component: () => import('@/pages/DashboardPage.vue')
  },
  {
    path: '/hosts',
    name: 'Hosts',
    component: () => import('@/pages/HostsPage.vue')
  },
  {
    path: '/hosts/:id',
    name: 'HostDetail',
    component: () => import('@/pages/HostDetailPage.vue')
  },
  {
    path: '/peers',
    name: 'Peers',
    component: () => import('@/pages/PeersPage.vue')
  },
  {
    path: '/peers/:id',
    name: 'PeerDetail',
    component: () => import('@/pages/PeerDetailPage.vue')
  },
  {
    path: '/alerts',
    name: 'Alerts',
    component: () => import('@/pages/AlertsPage.vue')
  },
  {
    path: '/users',
    name: 'Users',
    component: () => import('@/pages/UsersPage.vue'),
    meta: { requireAdmin: true }
  },
  {
    path: '/settings',
    name: 'Settings',
    component: () => import('@/pages/SettingsPage.vue'),
    meta: { requireAdmin: true }
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes
})

// Navigation guard
router.beforeEach((to) => {
  const authStore = useAuthStore()
  if (!to.meta.public && !authStore.isLoggedIn) {
    return { name: 'Login' }
  }
  if (to.meta.requireAdmin && !authStore.isAdmin) {
    return { name: 'Dashboard' }
  }
})

export default router
