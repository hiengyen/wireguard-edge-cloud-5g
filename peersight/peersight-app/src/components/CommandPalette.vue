<template>
  <Transition name="fade">
    <div v-if="isOpen" class="palette-overlay" @click.self="close">
      <div class="palette-card animate-pop">
        <!-- Search Input Header -->
        <div class="palette-header">
          <span class="material-symbols-outlined search-icon">search</span>
          <input
            ref="searchInput"
            v-model="query"
            type="text"
            class="palette-input"
            :placeholder="t('search.placeholder')"
            @keydown.down.prevent="navigateDown"
            @keydown.up.prevent="navigateUp"
            @keydown.enter.prevent="selectCurrent"
            @keydown.esc="close"
          />
          <div class="esc-badge" @click="close">ESC</div>
        </div>

        <!-- Results List -->
        <div class="palette-body" ref="resultsList">
          <div v-if="query.trim() === ''" class="palette-hint">
            <span class="material-symbols-outlined" style="font-size:24px;color:var(--color-text-muted)">keyboard</span>
            <p>{{ t('search.hint') }}</p>
          </div>

          <div v-else-if="totalResults === 0" class="palette-empty">
            <span class="material-symbols-outlined" style="font-size:24px;color:var(--color-danger)">search_off</span>
            <p>{{ t('search.noMatches').replace('{query}', query) }}</p>
          </div>

          <div v-else>
            <!-- Hosts Category -->
            <div v-if="filteredHosts.length > 0" class="palette-category">
              <div class="category-header">{{ t('search.hostsCat') }}</div>
              <div
                v-for="h in filteredHosts"
                :key="'host-' + h.id"
                :class="['palette-item', { active: activeIndex === getItemIndex('host', h.id) }]"
                @mouseenter="activeIndex = getItemIndex('host', h.id)"
                @click="goTo('/hosts/' + h.id)"
              >
                <span class="material-symbols-outlined item-icon host">dns</span>
                <div class="item-details">
                  <div class="item-title">{{ h.name }}</div>
                  <code class="item-subtitle">{{ h.id }}</code>
                </div>
                <span class="material-symbols-outlined item-arrow">arrow_forward</span>
              </div>
            </div>

            <!-- Peers Category -->
            <div v-if="filteredPeers.length > 0" class="palette-category">
              <div class="category-header">{{ t('search.peersCat') }}</div>
              <div
                v-for="p in filteredPeers"
                :key="'peer-' + p.id"
                :class="['palette-item', { active: activeIndex === getItemIndex('peer', p.id) }]"
                @mouseenter="activeIndex = getItemIndex('peer', p.id)"
                @click="goTo('/peers/' + p.id)"
              >
                <span class="material-symbols-outlined item-icon peer">key</span>
                <div class="item-details">
                  <div class="item-title">{{ p.name }}</div>
                  <code class="item-subtitle truncate">{{ truncateKey(p.public_key) }}</code>
                </div>
                <span class="material-symbols-outlined item-arrow">arrow_forward</span>
              </div>
            </div>

            <!-- Alerts Category -->
            <div v-if="filteredAlerts.length > 0" class="palette-category">
              <div class="category-header">{{ t('search.alertsCat') }}</div>
              <div
                v-for="a in filteredAlerts"
                :key="'alert-' + a.id"
                :class="['palette-item', { active: activeIndex === getItemIndex('alert', a.id) }]"
                @mouseenter="activeIndex = getItemIndex('alert', a.id)"
                @click="goTo('/alerts')"
              >
                <span class="material-symbols-outlined item-icon alert">warning</span>
                <div class="item-details">
                  <div class="item-title">{{ a.message }}</div>
                  <div class="item-subtitle">{{ a.level }} • {{ a.type }}</div>
                </div>
                <span class="material-symbols-outlined item-arrow">arrow_forward</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { useHostStore, usePeerStore, useAlertStore } from '@/stores/data.js'
import { useI18n } from '@/utils/i18n.js'
import { truncateKey } from '@/utils/format.js'

const router = useRouter()
const hostStore = useHostStore()
const peerStore = usePeerStore()
const alertStore = useAlertStore()
const { t } = useI18n()

const isOpen = ref(false)
const query = ref('')
const activeIndex = ref(0)
const searchInput = ref(null)
const resultsList = ref(null)

// Handle global key events
onMounted(() => {
  window.addEventListener('keydown', handleGlobalKeydown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleGlobalKeydown)
})

function handleGlobalKeydown(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
    e.preventDefault()
    toggle()
  } else if (e.key === 'Escape' && isOpen.value) {
    close()
  }
}

function toggle() {
  isOpen.value = !isOpen.value
  if (isOpen.value) {
    query.value = ''
    activeIndex.value = 0
    nextTick(() => {
      searchInput.value?.focus()
    })
  }
}

function close() {
  isOpen.value = false
}

// Category filter calculations
const filteredHosts = computed(() => {
  if (query.value.trim() === '') return []
  const q = query.value.toLowerCase()
  return hostStore.hosts.filter(h => h.name.toLowerCase().includes(q) || h.id.toLowerCase().includes(q))
})

const filteredPeers = computed(() => {
  if (query.value.trim() === '') return []
  const q = query.value.toLowerCase()
  return peerStore.peers.filter(p => p.name.toLowerCase().includes(q) || p.public_key.toLowerCase().includes(q))
})

const filteredAlerts = computed(() => {
  if (query.value.trim() === '') return []
  const q = query.value.toLowerCase()
  return alertStore.alerts.filter(a => !a.resolved && (a.message.toLowerCase().includes(q) || a.type.toLowerCase().includes(q)))
})

// Flatten results list for index mapping
const allItemsFlattened = computed(() => {
  const list = []
  filteredHosts.value.forEach(h => list.push({ type: 'host', id: h.id, url: '/hosts/' + h.id }))
  filteredPeers.value.forEach(p => list.push({ type: 'peer', id: p.id, url: '/peers/' + p.id }))
  filteredAlerts.value.forEach(a => list.push({ type: 'alert', id: a.id, url: '/alerts' }))
  return list
})

const totalResults = computed(() => allItemsFlattened.value.length)

watch(query, () => {
  activeIndex.value = 0
})

function getItemIndex(type, id) {
  return allItemsFlattened.value.findIndex(item => item.type === type && item.id === id)
}

function navigateDown() {
  if (totalResults.value === 0) return
  activeIndex.value = (activeIndex.value + 1) % totalResults.value
  scrollIntoView()
}

function navigateUp() {
  if (totalResults.value === 0) return
  activeIndex.value = (activeIndex.value - 1 + totalResults.value) % totalResults.value
  scrollIntoView()
}

function selectCurrent() {
  const current = allItemsFlattened.value[activeIndex.value]
  if (current) {
    goTo(current.url)
  }
}

function goTo(url) {
  router.push(url)
  close()
}

function scrollIntoView() {
  nextTick(() => {
    const el = resultsList.value?.querySelector('.palette-item.active')
    if (el) {
      el.scrollIntoView({ block: 'nearest' })
    }
  })
}
</script>

<style scoped>
.palette-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(8px);
  display: flex;
  justify-content: center;
  padding-top: 14vh;
  z-index: 9999;
}

.palette-card {
  background: var(--color-bg-card, #1e1e24);
  border: 1px solid var(--color-border, #2d2d34);
  width: 90%;
  max-width: 640px;
  max-height: 480px;
  border-radius: var(--radius-lg, 12px);
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 50px rgba(0,0,0,0.8);
  overflow: hidden;
}

.animate-pop {
  animation: popUp 0.18s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes popUp {
  from { transform: scale(0.97) translateY(8px); opacity: 0; }
  to { transform: scale(1) translateY(0); opacity: 1; }
}

.palette-header {
  display: flex;
  align-items: center;
  padding: var(--space-md);
  border-bottom: 1px solid var(--color-border, #2d2d34);
  gap: 12px;
}

.search-icon {
  color: var(--color-text-muted);
  font-size: 22px;
  flex-shrink: 0;
}

.palette-input {
  background: transparent;
  border: none;
  color: var(--color-text);
  font-size: var(--font-size-md);
  width: 100%;
  outline: none;
  font-family: var(--font-family);
}

.esc-badge {
  background: var(--color-bg-input, #0f0f13);
  border: 1px solid var(--color-border, #2d2d34);
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 700;
  color: var(--color-text-muted);
  cursor: pointer;
  flex-shrink: 0;
}

.palette-body {
  overflow-y: auto;
  flex: 1;
}

.palette-hint, .palette-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--space-2xl);
  color: var(--color-text-muted);
  text-align: center;
  gap: var(--space-sm);
}

.palette-hint p, .palette-empty p {
  margin: 0;
  font-size: var(--font-size-sm);
}

.palette-category {
  padding: var(--space-sm) 0;
}

.category-header {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  color: var(--color-text-muted);
  padding: 6px var(--space-md);
  letter-spacing: 0.05em;
}

.palette-item {
  display: flex;
  align-items: center;
  padding: 10px var(--space-md);
  cursor: pointer;
  gap: var(--space-md);
  transition: background-color 0.1s;
}

.palette-item.active {
  background-color: var(--color-bg-hover, rgba(255,255,255,0.04));
}

.item-icon {
  width: 32px;
  height: 32px;
  border-radius: var(--radius-sm, 6px);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  flex-shrink: 0;
}

.item-icon.host { background: rgba(59, 130, 246, 0.1); color: #3b82f6; }
.item-icon.peer { background: rgba(34, 197, 94, 0.1); color: #22c55e; }
.item-icon.alert { background: rgba(239, 68, 68, 0.1); color: #ef4444; }

.item-details {
  flex: 1;
  min-width: 0;
}

.item-title {
  font-size: var(--font-size-sm);
  font-weight: 600;
  color: var(--color-text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.item-subtitle {
  font-size: 11px;
  color: var(--color-text-muted);
  margin-top: 2px;
  display: block;
}

.item-subtitle.truncate {
  font-family: monospace;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.item-arrow {
  color: var(--color-text-muted);
  font-size: 16px;
  opacity: 0;
  transition: opacity 0.1s, transform 0.1s;
}

.palette-item.active .item-arrow {
  opacity: 1;
  transform: translateX(2px);
  color: var(--color-accent);
}

/* Transitions */
.fade-enter-active, .fade-leave-active {
  transition: opacity 0.15s ease;
}
.fade-enter-from, .fade-leave-to {
  opacity: 0;
}
</style>
