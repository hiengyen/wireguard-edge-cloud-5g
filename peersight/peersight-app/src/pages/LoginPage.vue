<template>
  <div class="login-page">
    <div class="login-card">
      <div class="login-brand">
        <span class="material-symbols-outlined brand-icon">vpn_lock</span>
        <h1>peersight</h1>
        <p>{{ t('auth.loginTitle') }}</p>
      </div>

      <form @submit.prevent="handleLogin" class="login-form">
        <div v-if="error" class="login-error">{{ error }}</div>

        <div class="form-group">
          <label class="form-label">Email</label>
          <input
            v-model="email"
            type="email"
            class="form-input"
            placeholder="admin@example.com"
            required
            autofocus
          />
        </div>

        <div class="form-group">
          <label class="form-label">{{ t('settings.profile.password') }}</label>
          <input
            v-model="password"
            type="password"
            class="form-input"
            placeholder="••••••••"
            required
          />
        </div>

        <button type="submit" class="btn btn-primary login-btn" :disabled="loading">
          <span v-if="loading" class="spinner" style="width:16px;height:16px;border-width:2px"></span>
          <span v-else>{{ t('auth.loginBtn') }}</span>
        </button>

        <div style="text-align:center;margin-top:var(--space-lg);font-size:var(--font-size-sm);color:var(--color-text-muted)">
          {{ t('auth.noAccount') }}
          <router-link to="/signup" style="color:var(--color-accent);font-weight:500">{{ t('auth.signUpBtn') }}</router-link>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth.js'
import { useI18n } from '@/utils/i18n.js'

const router = useRouter()
const authStore = useAuthStore()
const { t } = useI18n()

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function handleLogin() {
  error.value = ''
  loading.value = true
  try {
    await authStore.login(email.value, password.value)
    router.push('/')
  } catch (e) {
    error.value = e.response?.data?.error || 'Login failed'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-bg-primary);
  padding: var(--space-md);
}

.login-card {
  width: 100%;
  max-width: 400px;
  background: var(--gradient-card);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-2xl);
  box-shadow: var(--shadow-lg);
}

.login-brand {
  text-align: center;
  margin-bottom: var(--space-xl);
}

.brand-icon {
  font-size: 48px;
  color: var(--color-accent);
  margin-bottom: var(--space-sm);
}

.login-brand h1 {
  font-size: var(--font-size-2xl);
  font-weight: 700;
  background: var(--gradient-brand);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.login-brand p {
  color: var(--color-text-muted);
  font-size: var(--font-size-sm);
  margin-top: var(--space-xs);
}

.login-error {
  background: rgba(248, 113, 113, 0.1);
  border: 1px solid rgba(248, 113, 113, 0.3);
  color: var(--color-danger);
  padding: var(--space-sm) var(--space-md);
  border-radius: var(--radius-sm);
  font-size: var(--font-size-sm);
  margin-bottom: var(--space-md);
}

.login-btn {
  width: 100%;
  justify-content: center;
  padding: var(--space-md);
  font-size: var(--font-size-md);
  margin-top: var(--space-sm);
}
</style>
