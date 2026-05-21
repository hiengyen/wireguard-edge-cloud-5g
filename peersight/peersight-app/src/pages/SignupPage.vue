<template>
  <div class="login-page">
    <div class="login-card">
      <div class="login-brand">
        <span class="material-symbols-outlined brand-icon">vpn_lock</span>
        <h1>peersight</h1>
        <p>Create your account</p>
      </div>

      <form @submit.prevent="handleSignup" class="login-form">
        <div v-if="error" class="login-error">{{ error }}</div>

        <div class="form-group">
          <label class="form-label">Email</label>
          <input
            v-model="email"
            type="email"
            class="form-input"
            placeholder="you@example.com"
            required
            autofocus
          />
        </div>

        <div class="form-group">
          <label class="form-label">Password</label>
          <input
            v-model="password"
            type="password"
            class="form-input"
            placeholder="••••••••"
            required
            minlength="8"
          />
        </div>

        <div class="form-group">
          <label class="form-label">Confirm Password</label>
          <input
            v-model="confirmPassword"
            type="password"
            class="form-input"
            placeholder="••••••••"
            required
          />
        </div>

        <button type="submit" class="btn btn-primary login-btn" :disabled="loading">
          <span v-if="loading" class="spinner" style="width:16px;height:16px;border-width:2px"></span>
          <span v-else>Create Account</span>
        </button>

        <div class="signup-link">
          Already have an account?
          <router-link to="/login">Sign In</router-link>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth.js'
import { api } from '@/plugins/axios.js'

const router = useRouter()
const authStore = useAuthStore()

const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const error = ref('')
const loading = ref(false)

async function handleSignup() {
  error.value = ''

  if (password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match'
    return
  }

  if (password.value.length < 8) {
    error.value = 'Password must be at least 8 characters'
    return
  }

  loading.value = true
  try {
    const res = await api.post('/accounts/signup', {
      email: email.value,
      password: password.value
    })

    // Auto-login after signup
    authStore.setTokens(res.data)
    router.push('/')
  } catch (e) {
    error.value = e.response?.data?.error || 'Signup failed'
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

.signup-link {
  text-align: center;
  margin-top: var(--space-lg);
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
}

.signup-link a {
  color: var(--color-accent);
  font-weight: 500;
}
</style>
