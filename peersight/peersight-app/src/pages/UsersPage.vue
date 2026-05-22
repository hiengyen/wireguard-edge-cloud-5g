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

    <div v-else class="card">
      <div v-if="userStore.users.length === 0" class="empty-state">
        <span class="material-symbols-outlined">group</span>
        <h3>{{ t('users.noUsers') }}</h3>
        <p>{{ t('users.noUsersDesc') }}</p>
      </div>
      <table v-else class="data-table">
        <thead>
          <tr>
            <th>Email</th>
            <th>ID</th>
            <th>{{ t('settings.profile.role') }}</th>
            <th>{{ t('common.time') }}</th>
            <th style="text-align:right">{{ t('users.actions') }}</th>
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
                @click="deleteUser(user.id)"
                :disabled="user.id === authStore.userId"
              >
                <span class="material-symbols-outlined" style="font-size:16px">delete</span>
              </button>
            </td>
          </tr>
        </tbody>
      </table>
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
      error.value = "Failed to fetch users."
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

async function deleteUser(id) {
  if (!confirm('Are you sure you want to delete this user?')) return
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
</style>
