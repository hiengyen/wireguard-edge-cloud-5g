<template>
  <div v-if="authStore.isLoggedIn" class="app-layout">
    <SidebarNav />
    <main class="app-main">
      <router-view />
    </main>
  </div>
  <div v-else>
    <router-view />
  </div>
</template>

<script setup>
import SidebarNav from '@/components/SidebarNav.vue'
import { useAuthStore } from '@/stores/auth.js'
import { initTheme } from '@/utils/theme.js'

initTheme()
const authStore = useAuthStore()
</script>
