import { ref, watch } from 'vue'

const savedTheme = localStorage.getItem('peersight-theme') || 'dark'
export const currentTheme = ref(savedTheme)

export function toggleTheme() {
  currentTheme.value = currentTheme.value === 'dark' ? 'light' : 'dark'
}

export function initTheme() {
  document.documentElement.setAttribute('data-theme', currentTheme.value)
  
  watch(currentTheme, (newTheme) => {
    localStorage.setItem('peersight-theme', newTheme)
    document.documentElement.setAttribute('data-theme', newTheme)
  })
}
