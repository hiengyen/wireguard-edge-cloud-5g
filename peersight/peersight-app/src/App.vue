<template>
  <div v-if="authStore.isLoggedIn" class="app-layout">
    <!-- Mobile Top Bar -->
    <header class="mobile-header">
      <button class="menu-btn" @click="sidebarOpen = !sidebarOpen">
        <span class="material-symbols-outlined">menu</span>
      </button>
      <div class="mobile-brand">
        <span class="material-symbols-outlined" style="color: var(--color-accent); font-size: 20px;">vpn_lock</span>
        <h1>peersight</h1>
      </div>
      <div style="width: 24px;"></div>
    </header>

    <!-- Mobile Sidebar Backdrop -->
    <div v-if="sidebarOpen" class="sidebar-backdrop" @click="sidebarOpen = false"></div>

    <SidebarNav :class="{ open: sidebarOpen }" />
    
    <main class="app-main">
      <router-view />
    </main>
    <CommandPalette />
  </div>
  <div v-else>
    <router-view />
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import SidebarNav from '@/components/SidebarNav.vue'
import CommandPalette from '@/components/CommandPalette.vue'
import { useAuthStore } from '@/stores/auth.js'
import { initTheme } from '@/utils/theme.js'

initTheme()
const authStore = useAuthStore()
const sidebarOpen = ref(false)
const route = useRoute()

// Close mobile sidebar upon navigation
watch(() => route.path, () => {
  sidebarOpen.value = false
})
</script>
