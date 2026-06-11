<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">{{ t('users.title') }}</h1>
      <div style="display:flex;gap:var(--space-sm);align-items:center">
        <button class="btn btn-primary" @click="showCreateModal = true">
          <span class="material-symbols-outlined">person_add</span>
          {{ t('users.add') }}
        </button>
        <button class="btn btn-secondary" @click="userStore.fetchUsers()">
          <span class="material-symbols-outlined">refresh</span>
          {{ t('common.refresh') }}
        </button>
      </div>
    </div>

    <div v-if="error" class="card" style="border-color: var(--color-danger); margin-bottom: 20px;">
      <p style="color: var(--color-danger); margin: 0;">{{ error }}</p>
    </div>

    <div v-if="userStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else class="card animate-fade" style="padding: 0; overflow: hidden;">
      <div v-if="userStore.users.length === 0" class="empty-state" style="padding: var(--space-xl)">
        <span class="material-symbols-outlined">group</span>
        <h3>{{ t('users.noUsers') }}</h3>
        <p>{{ t('users.noUsersDesc') }}</p>
      </div>
      <div v-else class="table-responsive">
        <table class="data-table resizable-table">
          <thead>
            <tr>
              <th :style="{ width: colWidths.email + 'px' }">
                Email
                <div class="resize-handle" :class="{ active: activeResizeCol === 'email' }" @mousedown.stop.prevent="startResize($event, 'email')"></div>
              </th>
              <th :style="{ width: colWidths.id + 'px' }">
                ID
                <div class="resize-handle" :class="{ active: activeResizeCol === 'id' }" @mousedown.stop.prevent="startResize($event, 'id')"></div>
              </th>
              <th :style="{ width: colWidths.role + 'px' }">
                {{ t('settings.profile.role') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'role' }" @mousedown.stop.prevent="startResize($event, 'role')"></div>
              </th>
              <th :style="{ width: colWidths.time + 'px' }">
                {{ t('common.time') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'time' }" @mousedown.stop.prevent="startResize($event, 'time')"></div>
              </th>
              <th :style="{ width: colWidths.actions + 'px' }" style="text-align:right">
                {{ t('users.actions') }}
                <div class="resize-handle" :class="{ active: activeResizeCol === 'actions' }" @mousedown.stop.prevent="startResize($event, 'actions')"></div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="user in userStore.users" :key="user.id">
              <td style="font-weight:600">
                <div style="display:flex;align-items:center;gap:8px">
                  <span class="material-symbols-outlined" style="font-size:18px;color:var(--color-accent)">person</span>
                  {{ user.email }}
                </div>
              </td>
              <td><code class="mono-id">{{ shortId(user.id) }}</code></td>
              <td>
                <select 
                  class="form-input"
                  v-model="user.role" 
                  @change="updateRole(user.id, user.role)"
                  style="padding: 4px 8px; font-size: 13px;"
                  :disabled="user.id === authStore.userId"
                >
                  <option value="admin">Admin</option>
                  <option value="operator">Operator</option>
                </select>
              </td>
              <td style="color:var(--color-text-secondary);font-size:var(--font-size-xs)">
                {{ formatTime(user.created_at) }}
              </td>
              <td style="text-align:right">
                <button
                  class="btn btn-secondary" 
                  style="padding:4px 8px;color:var(--color-danger);border-color:rgba(239,68,68,0.2)"
                  @click="deleteUser(user.id, user.email)"
                  :disabled="user.id === authStore.userId"
                >
                  <span class="material-symbols-outlined" style="font-size:16px">delete</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div v-if="showCreateModal" class="modal-overlay" @click.self="closeCreateModal">
      <div class="modal-content">
        <div class="modal-header">
          <h3>{{ t('users.add') }}</h3>
          <button class="modal-close" @click="closeCreateModal" aria-label="Close">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>

        <form @submit.prevent="createUser">
          <div class="form-group">
            <label class="form-label" for="new-user-email">Email</label>
            <input id="new-user-email" v-model.trim="newUser.email" class="form-input" type="email" autocomplete="email" required />
          </div>
          <div class="form-group">
            <label class="form-label" for="new-user-password">{{ t('settings.profile.password') }}</label>
            <input id="new-user-password" v-model="newUser.password" class="form-input" type="password" autocomplete="new-password" minlength="8" required />
          </div>
          <div class="form-group">
            <label class="form-label" for="new-user-role">{{ t('settings.profile.role') }}</label>
            <select id="new-user-role" v-model="newUser.role" class="form-input">
              <option value="operator">Operator</option>
              <option value="admin">Admin</option>
            </select>
          </div>

          <div v-if="createError" class="form-error">{{ createError }}</div>

          <div class="modal-actions">
            <button type="button" class="btn btn-secondary" @click="closeCreateModal">{{ t('common.cancel') }}</button>
            <button type="submit" class="btn btn-primary" :disabled="creating || !canCreateUser">
              <span class="material-symbols-outlined" style="font-size:16px">person_add</span>
              {{ t('common.save') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useUserStore } from '@/stores/data.js'
import { useAuthStore } from '@/stores/auth.js'
import { shortId, formatTime } from '@/utils/format.js'
import { useI18n } from '@/utils/i18n.js'

const userStore = useUserStore()
const authStore = useAuthStore()
const { t } = useI18n()
const error = ref('')
const showCreateModal = ref(false)
const creating = ref(false)
const createError = ref('')
const newUser = ref({ email: '', password: '', role: 'operator' })

// Resizable column widths (like Excel)
const colWidths = ref({
  email: 240,
  id: 140,
  role: 140,
  time: 160,
  actions: 120
})

const activeResizeCol = ref(null)
let startX = 0
let startWidth = 0

function startResize(event, colName) {
  activeResizeCol.value = colName
  startX = event.clientX
  startWidth = colWidths.value[colName]
  
  document.addEventListener('mousemove', handleResize)
  document.addEventListener('mouseup', stopResize)
  
  document.body.style.cursor = 'col-resize'
  document.body.style.userSelect = 'none'
}

function handleResize(event) {
  if (!activeResizeCol.value) return
  const diff = event.clientX - startX
  const newWidth = Math.max(startWidth + diff, 60)
  colWidths.value[activeResizeCol.value] = newWidth
}

function stopResize() {
  activeResizeCol.value = null
  document.removeEventListener('mousemove', handleResize)
  document.removeEventListener('mouseup', stopResize)
  
  document.body.style.cursor = ''
  document.body.style.userSelect = ''
}

const canCreateUser = computed(() =>
  newUser.value.email &&
  newUser.value.password.length >= 8 &&
  ['admin', 'operator'].includes(newUser.value.role)
)

onMounted(async () => {
  try {
    await userStore.fetchUsers()
  } catch (err) {
    if (err.response?.status === 403) {
      error.value = t('users.adminRequired')
    } else {
      error.value = t('users.fetchFailed')
    }
  }
})

async function updateRole(id, role) {
  try {
    error.value = ''
    await userStore.updateUserRole(id, role)
  } catch (err) {
    error.value = err.response?.data?.error || 'Failed to update role'
    await userStore.fetchUsers() // revert
  }
}

async function createUser() {
  if (!canCreateUser.value) return
  try {
    creating.value = true
    createError.value = ''
    await userStore.createUser({ ...newUser.value })
    closeCreateModal()
  } catch (err) {
    createError.value = err.response?.data?.error || 'Failed to create user'
  } finally {
    creating.value = false
  }
}

function closeCreateModal() {
  showCreateModal.value = false
  createError.value = ''
  newUser.value = { email: '', password: '', role: 'operator' }
}

async function deleteUser(id, email) {
  if (!confirm(t('users.deleteConfirm').replace('{email}', email))) return
  try {
    error.value = ''
    await userStore.deleteUser(id)
  } catch (err) {
    error.value = err.response?.data?.error || 'Failed to delete user'
  }
}
</script>

<style scoped>
.mono-id {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  background: var(--color-bg-input);
  padding: 2px 6px;
  border-radius: var(--radius-sm);
}

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 200;
  backdrop-filter: blur(4px);
}

.modal-content {
  background: var(--color-bg-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: var(--space-xl);
  max-width: 440px;
  width: min(92vw, 440px);
  box-shadow: var(--shadow-lg);
}

.modal-header,
.modal-actions {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--space-sm);
}

.modal-header {
  margin-bottom: var(--space-lg);
}

.modal-close {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  display: inline-flex;
  padding: 4px;
}

.modal-actions {
  justify-content: flex-end;
  margin-top: var(--space-lg);
}

.form-error {
  color: var(--color-danger);
  font-size: var(--font-size-xs);
}

/* Resizable columns & responsive styles */
.table-responsive {
  width: 100%;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}

.resizable-table {
  table-layout: fixed;
  width: 100%;
  border-collapse: collapse;
}

.resizable-table th {
  position: relative;
  user-select: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.resizable-table td {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.resize-handle {
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  width: 6px;
  cursor: col-resize;
  z-index: 100;
  border-right: 1px solid var(--color-border, #2a2e42);
  transition: border-right-color var(--transition-fast), background-color var(--transition-fast);
}

.resize-handle:hover,
.resize-handle.active {
  border-right: 2px solid var(--color-accent, #4f6ef7);
  background-color: rgba(79, 110, 247, 0.15);
}

.animate-fade {
  animation: fadeIn 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
