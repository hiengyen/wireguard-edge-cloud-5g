<template>
  <aside class="app-sidebar">
    <div class="sidebar-brand">
      <span class="material-symbols-outlined" style="color: var(--color-accent);">vpn_lock</span>
      <h1>peersight</h1>
    </div>

    <nav class="sidebar-nav">
      <router-link to="/" class="nav-item" :class="{ active: $route.name === 'Dashboard' }">
        <span class="material-symbols-outlined">dashboard</span>
        <span>{{ t('nav.dashboard') }}</span>
      </router-link>

      <router-link to="/hosts" class="nav-item" :class="{ active: $route.name === 'Hosts' }">
        <span class="material-symbols-outlined">dns</span>
        <span>{{ t('nav.hosts') }}</span>
      </router-link>

      <router-link to="/peers" class="nav-item" :class="{ active: $route.name === 'Peers' }">
        <span class="material-symbols-outlined">hub</span>
        <span>{{ t('nav.peers') }}</span>
      </router-link>

      <router-link to="/alerts" class="nav-item" :class="{ active: $route.name === 'Alerts' }">
        <span class="material-symbols-outlined">notifications</span>
        <span>{{ t('nav.alerts') }}</span>
        <span v-if="unresolvedCount > 0" class="alert-count">{{ unresolvedCount }}</span>
      </router-link>

      <router-link v-if="authStore.isAdmin" to="/users" class="nav-item" :class="{ active: $route.name === 'Users' }">
        <span class="material-symbols-outlined">group</span>
        <span>{{ t('nav.users') }}</span>
      </router-link>

      <router-link v-if="authStore.isAdmin" to="/settings" class="nav-item" :class="{ active: $route.name === 'Settings' }">
        <span class="material-symbols-outlined">settings</span>
        <span>{{ t('nav.settings') }}</span>
      </router-link>

      <div style="flex:1"></div>

      <div class="nav-item" @click="toggleLocale" style="display:flex;align-items:center;justify-content:space-between;width:100%">
        <div style="display:flex;align-items:center;gap:var(--space-sm)">
          <span class="material-symbols-outlined">translate</span>
          <span>{{ locale === 'en' ? 'Tiếng Việt' : 'English' }}</span>
        </div>
        <span class="lang-badge">{{ locale.toUpperCase() }}</span>
      </div>

      <div class="nav-item" @click="toggleTheme">
        <span class="material-symbols-outlined">
          {{ currentTheme === 'dark' ? 'light_mode' : 'dark_mode' }}
        </span>
        <span>{{ currentTheme === 'dark' ? t('nav.lightMode') : t('nav.darkMode') }}</span>
      </div>

      <div class="nav-item" @click="logout">
        <span class="material-symbols-outlined">logout</span>
        <span>{{ t('nav.logout') }}</span>
      </div>
    </nav>
  </aside>
</template>

<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth.js'
import { useAlertStore } from '@/stores/data.js'
import { currentTheme, toggleTheme } from '@/utils/theme.js'
import { useI18n } from '@/utils/i18n.js'

const router = useRouter()
const authStore = useAuthStore()
const alertStore = useAlertStore()
const { locale, t, setLocale } = useI18n()

const unresolvedCount = computed(() =>
  alertStore.alerts.filter(a => !a.resolved).length
)

function toggleLocale() {
  setLocale(locale.value === 'en' ? 'vi' : 'en')
}

function logout() {
  authStore.logout()
  router.push('/login')
}
</script>

<style scoped>
.alert-count {
  margin-left: auto;
  background: var(--color-danger);
  color: white;
  font-size: 11px;
  font-weight: 700;
  min-width: 20px;
  height: 20px;
  border-radius: var(--radius-full);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 6px;
}

.lang-badge {
  background: rgba(79, 110, 247, 0.15);
  color: var(--color-accent);
  font-size: 10px;
  font-weight: 700;
  padding: 2px 6px;
  border-radius: 4px;
}
</style>
