/**
 * Shared utility functions for PeerSight App.
 * Centralizes formatting logic used across multiple pages.
 */

/**
 * Format a timestamp into a human-readable relative time string.
 * @param {string|null} ts - ISO timestamp
 * @returns {string}
 */
export function formatTime(ts) {
  if (!ts) return '—'
  const d = new Date(ts)
  const diff = Math.floor((Date.now() - d.getTime()) / 1000)
  if (diff < 60) return `${diff}s ago`
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`
  return d.toLocaleString()
}

/**
 * Check if a host is considered online (last ping within 2 minutes).
 * @param {object} host
 * @returns {boolean}
 */
export function isOnline(host) {
  if (!host?.last_ping) return false
  return Date.now() - new Date(host.last_ping).getTime() < 120000
}

/**
 * Format byte count into human-readable string.
 * @param {number} bytes
 * @returns {string}
 */
export function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i]
}

/**
 * Format a date for display.
 * @param {string|null} ts - ISO timestamp
 * @returns {string}
 */
export function formatDate(ts) {
  return ts ? new Date(ts).toLocaleDateString() : '—'
}

/**
 * Truncate a UUID for display.
 * @param {string} id
 * @returns {string}
 */
export function shortId(id) {
  return id ? id.substring(0, 8) + '…' : '—'
}

/**
 * Truncate a WireGuard public key for display.
 * @param {string} key
 * @returns {string}
 */
export function truncateKey(key) {
  if (!key) return '—'
  return key.substring(0, 4) + '***'
}

/**
 * Map alert level to badge CSS class.
 * @param {string} level
 * @returns {string}
 */
export function alertClass(level) {
  const map = { critical: 'offline', warning: 'warning', info: 'online' }
  return map[level] || 'online'
}

/**
 * Map alert level to Material icon name.
 * @param {string} level
 * @returns {string}
 */
export function alertIcon(level) {
  const map = { critical: 'error', warning: 'warning', info: 'info' }
  return map[level] || 'info'
}
