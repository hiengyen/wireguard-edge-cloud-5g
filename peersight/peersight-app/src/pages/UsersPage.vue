<template>
  <div>
    <div class="page-header">
      <h1 class="page-title">Users</h1>
      <button class="btn btn-secondary" @click="userStore.fetchUsers()">
        <span class="material-symbols-outlined">refresh</span>
        Refresh
      </button>
    </div>

    <div v-if="error" class="card" style="border-color: var(--color-error); margin-bottom: 20px;">
      <p style="color: var(--color-error); margin: 0;">{{ error }}</p>
    </div>

    <div v-if="userStore.loading" style="text-align:center;padding:var(--space-2xl)">
      <div class="spinner" style="margin:0 auto"></div>
    </div>

    <div v-else class="card">
      <table class="data-table">
        <thead>
          <tr>
            <th>Email</th>
            <th>ID</th>
            <th>Role</th>
            <th>Created</th>
            <th style="text-align:right">Actions</th>
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
                class="form-control" 
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
                style="padding:4px 8px;color:var(--color-error);border-color:rgba(239,68,68,0.2)"
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
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useUserStore } from '@/stores/data.js'
import { useAuthStore } from '@/stores/auth.js'
import { shortId, formatTime } from '@/utils/format.js'

const userStore = useUserStore()
const authStore = useAuthStore()
const error = ref('')

onMounted(async () => {
  try {
    await userStore.fetchUsers()
  } catch (err) {
    if (err.response?.status === 403) {
      error.value = "Admin access required to view this page."
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
</style>
