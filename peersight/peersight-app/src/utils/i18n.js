import { ref } from 'vue'

const locale = ref(localStorage.getItem('peersight_locale') || 'en')

const translations = {
  en: {
    common: {
      cancel: 'Cancel',
      save: 'Save',
      edit: 'Edit',
      delete: 'Delete',
      refresh: 'Refresh',
      loading: 'Loading...',
      status: 'Status',
      active: 'Active',
      resolved: 'Resolved',
      actions: 'Actions',
      time: 'Time',
      message: 'Message',
      level: 'Level',
      type: 'Type',
      online: 'Online',
      offline: 'Offline',
      none: 'None',
      copy: 'Copy',
      copied: 'Copied!'
    },
    nav: {
      dashboard: 'Dashboard',
      hosts: 'Hosts',
      peers: 'Peers',
      alerts: 'Alerts',
      users: 'Users',
      settings: 'Settings',
      logout: 'Logout',
      lightMode: 'Light Mode',
      darkMode: 'Dark Mode'
    },
    dashboard: {
      title: 'Dashboard',
      topologyMap: 'VPN Star Network Topology Map',
      recentAlerts: 'Recent Alerts',
      recentActivity: 'Recent Activity',
      hosts: 'Hosts',
      peers: 'Peers',
      online: 'Online',
      networkFlow: 'Network Flow',
      activeAlerts: 'Active Alerts',
      noAlerts: 'No Alerts',
      smoothRunning: 'Everything is running smoothly.',
      nodeHub: 'VPN Cloud HUB',
      nodeEdge: 'Edge Node'
    },
    hosts: {
      title: 'Hosts',
      registerNew: 'Register New Host',
      hostName: 'Host Name',
      hostId: 'Host ID',
      ipAddress: 'IP Address',
      lastSeen: 'Last Seen',
      interfaces: 'Interfaces',
      endpoints: 'Endpoints',
      changes: 'Changes',
      rename: 'Rename Host',
      deleteConfirm: 'Are you sure you want to delete host "{name}"?',
      deleteWarning: 'This will permanently remove the host and all cascaded endpoint interface configs!',
      installCommand: 'Agent Installation Command',
      installInstructions: 'Copy the command below and run it with superuser permissions on the target host to automatically configure and register the peersight agent:',
      noInterfaces: 'No interfaces configured for this host.',
      noEndpoints: 'No active WireGuard peer endpoints.'
    },
    peers: {
      title: 'Peers',
      detailTitle: 'Peer Details',
      publicKey: 'Public Key',
      lastHandshake: 'Last Handshake',
      rxFlow: 'Received Data',
      txFlow: 'Transmitted Data',
      endpointsList: 'Connected Endpoints',
      connectedHost: 'Connected Host',
      connectedInterface: 'Interface'
    },
    alerts: {
      title: 'Alerts',
      all: 'All Alerts',
      activeAlerts: 'Active',
      resolvedAlerts: 'Resolved',
      resolveAllActive: 'Resolve All Active',
      selectedAlerts: 'alerts selected',
      clearSelection: 'Clear Selection',
      resolveSelected: 'Resolve Selected',
      noAlertsTitle: 'No Alerts',
      noAlertsDesc: 'Your network infrastructure is running cleanly.',
      resolve: 'Resolve'
    },
    settings: {
      title: 'Settings',
      refreshDiagnostics: 'Refresh Diagnostics',
      tokensCardTitle: 'Agent Authorization Tokens',
      tokensDesc: 'Generate long-lived tokens (valid for 10 years) to authenticate and initialize peersight-agent on your edge and gateway nodes.',
      generateToken: 'Generate New Agent Token',
      tokenSuccess: 'Token generated successfully!',
      tokenWarning: 'Make sure to copy this token now. For security, you will not be able to view it again after leaving this page.',
      diagnosticsTitle: 'System Diagnostics',
      diagLoading: 'Fetching live API state...',
      diagError: 'Failed to contact backend API. Host might be offline.',
      apiStatus: 'API Service Status',
      version: 'Software Version',
      uptime: 'API Service Uptime',
      dbPool: 'PostgreSQL Connections',
      dbTotal: 'Total Pool Size',
      dbActive: 'Active',
      dbIdle: 'Idle',
      profileTitle: 'User Profile Settings',
      accountRole: 'Account Role',
      userId: 'User ID',
      changePass: 'Change Password',
      newPass: 'New Password',
      confirmPass: 'Confirm Password',
      updatePass: 'Update Password',
      passSuccess: 'Password updated successfully!',
      auditTitle: 'Configuration Audit Logs',
      auditEmpty: 'No Logs Recorded',
      auditEmptyDesc: 'Configuration changes pushed to agents will appear here.',
      timestamp: 'Timestamp',
      hostNode: 'Host Node',
      actionType: 'Action Type',
      targetPayload: 'Target Payload',
      executedAt: 'Executed At'
    },
    users: {
      title: 'User Management',
      createUser: 'Create User',
      email: 'Email Address',
      role: 'Role',
      actions: 'Actions',
      addBtn: 'Add User',
      deleteConfirm: 'Are you sure you want to delete user {email}?'
    },
    auth: {
      loginTitle: 'Sign In to peerSight',
      signUpTitle: 'Create an Account',
      loginBtn: 'Sign In',
      signUpBtn: 'Sign Up',
      noAccount: 'Don\'t have an account?',
      hasAccount: 'Already have an account?',
      creating: 'Creating account...',
      signingIn: 'Signing in...'
    },
    search: {
      placeholder: 'Search hosts, peers, alerts... (Use ↑↓ to navigate, Enter to select)',
      hint: 'Type to search across edge infrastructure',
      noMatches: 'No matches found for "{query}"',
      hostsCat: 'Hosts',
      peersCat: 'Peers',
      alertsCat: 'Active Alerts'
    }
  },
  vi: {
    common: {
      cancel: 'Hủy',
      save: 'Lưu',
      edit: 'Chỉnh sửa',
      delete: 'Xóa',
      refresh: 'Làm mới',
      loading: 'Đang tải...',
      status: 'Trạng thái',
      active: 'Hoạt động',
      resolved: 'Đã xử lý',
      actions: 'Thao tác',
      time: 'Thời gian',
      message: 'Nội dung',
      level: 'Mức độ',
      type: 'Loại',
      online: 'Trực tuyến',
      offline: 'Ngoại tuyến',
      none: 'Không có',
      copy: 'Sao chép',
      copied: 'Đã chép!'
    },
    nav: {
      dashboard: 'Bảng điều khiển',
      hosts: 'Thiết bị (Hosts)',
      peers: 'Kết nối (Peers)',
      alerts: 'Cảnh báo',
      users: 'Người dùng',
      settings: 'Cấu hình',
      logout: 'Đăng xuất',
      lightMode: 'Giao diện sáng',
      darkMode: 'Giao diện tối'
    },
    dashboard: {
      title: 'Bảng điều khiển',
      topologyMap: 'Bản đồ cấu trúc mạng hình sao VPN Cloud-Edge',
      recentAlerts: 'Cảnh báo gần đây',
      recentActivity: 'Hoạt động gần đây',
      hosts: 'Thiết bị',
      peers: 'Kết nối',
      online: 'Trực tuyến',
      networkFlow: 'Lưu lượng mạng',
      activeAlerts: 'Cảnh báo hoạt động',
      noAlerts: 'Không có cảnh báo',
      smoothRunning: 'Mọi hệ thống đang hoạt động ổn định.',
      nodeHub: 'Trạm trung tâm VPN Cloud HUB',
      nodeEdge: 'Edge Node'
    },
    hosts: {
      title: 'Danh sách thiết bị (Hosts)',
      registerNew: 'Đăng ký thiết bị mới',
      hostName: 'Tên thiết bị',
      hostId: 'Mã thiết bị',
      ipAddress: 'Địa chỉ IP',
      lastSeen: 'Kết nối cuối',
      interfaces: 'Cổng kết nối',
      endpoints: 'Cổng đầu cuối',
      changes: 'Thay đổi',
      rename: 'Đổi tên thiết bị',
      deleteConfirm: 'Bạn có chắc chắn muốn xóa thiết bị "{name}"?',
      deleteWarning: 'Hành động này sẽ xóa vĩnh viễn thiết bị và toàn bộ cấu hình interface/endpoint liên quan!',
      installCommand: 'Lệnh cài đặt Agent',
      installInstructions: 'Sao chép lệnh dưới đây và chạy với quyền root (sudo) trên thiết bị Edge/Gateway để tự động thiết lập và đăng ký peersight-agent:',
      noInterfaces: 'Không có interface nào được cấu hình cho thiết bị này.',
      noEndpoints: 'Không có WireGuard peer endpoint nào đang hoạt động.'
    },
    peers: {
      title: 'Kết nối (Peers)',
      detailTitle: 'Chi tiết kết nối (Peer)',
      publicKey: 'Khóa công khai (Public Key)',
      lastHandshake: 'Bắt tay cuối (Handshake)',
      rxFlow: 'Lưu lượng nhận',
      txFlow: 'Lưu lượng gửi',
      endpointsList: 'Danh sách cổng đầu cuối kết nối',
      connectedHost: 'Thiết bị kết nối',
      connectedInterface: 'Cổng Interface'
    },
    alerts: {
      title: 'Cảnh báo hệ thống',
      all: 'Tất cả cảnh báo',
      activeAlerts: 'Đang hoạt động',
      resolvedAlerts: 'Đã xử lý',
      resolveAllActive: 'Xử lý tất cả đang hoạt động',
      selectedAlerts: 'cảnh báo được chọn',
      clearSelection: 'Bỏ chọn',
      resolveSelected: 'Xử lý đã chọn',
      noAlertsTitle: 'Không có cảnh báo',
      noAlertsDesc: 'Hạ tầng mạng của bạn đang vận hành ổn định.',
      resolve: 'Xử lý'
    },
    settings: {
      title: 'Cấu hình hệ thống',
      refreshDiagnostics: 'Làm mới chẩn đoán',
      tokensCardTitle: 'Mã xác thực Agent',
      tokensDesc: 'Sinh mã xác thực dài hạn (có hiệu lực trong 10 năm) để kết nối và khởi tạo peersight-agent trên các thiết bị gateway và edge node.',
      generateToken: 'Sinh mã Agent mới',
      tokenSuccess: 'Sinh mã xác thực thành công!',
      tokenWarning: 'Hãy sao chép mã này ngay. Vì lý do bảo mật, bạn sẽ không thể xem lại mã này sau khi rời khỏi trang.',
      diagnosticsTitle: 'Chẩn đoán hệ thống',
      diagLoading: 'Đang tải trạng thái API trực tiếp...',
      diagError: 'Lỗi kết nối tới hệ thống API backend. Máy chủ có thể đang ngoại tuyến.',
      apiStatus: 'Trạng thái API Service',
      version: 'Phiên bản phần mềm',
      uptime: 'Thời gian hoạt động API',
      dbPool: 'Kết nối database PostgreSQL',
      dbTotal: 'Tổng số pool',
      dbActive: 'Đang hoạt động',
      dbIdle: 'Nhàn rỗi',
      profileTitle: 'Thông tin tài khoản',
      accountRole: 'Vai trò tài khoản',
      userId: 'Mã người dùng',
      changePass: 'Đổi mật khẩu',
      newPass: 'Mật khẩu mới',
      confirmPass: 'Xác nhận mật khẩu',
      updatePass: 'Cập nhật mật khẩu',
      passSuccess: 'Đổi mật khẩu thành công!',
      auditTitle: 'Lịch sử cấu hình hệ thống',
      auditEmpty: 'Chưa ghi nhận lịch sử',
      auditEmptyDesc: 'Các cấu hình thay đổi đẩy xuống thiết bị agent sẽ xuất hiện ở đây.',
      timestamp: 'Thời gian',
      hostNode: 'Thiết bị Node',
      actionType: 'Loại hành động',
      targetPayload: 'Nội dung thay đổi',
      executedAt: 'Thời điểm thực thi'
    },
    users: {
      title: 'Quản lý người dùng',
      createUser: 'Thêm tài khoản',
      email: 'Địa chỉ Email',
      role: 'Vai trò',
      actions: 'Thao tác',
      addBtn: 'Thêm người dùng',
      deleteConfirm: 'Bạn có chắc chắn muốn xóa tài khoản {email}?'
    },
    auth: {
      loginTitle: 'Đăng nhập vào peerSight',
      signUpTitle: 'Đăng ký tài khoản',
      loginBtn: 'Đăng nhập',
      signUpBtn: 'Đăng ký',
      noAccount: 'Chưa có tài khoản?',
      hasAccount: 'Đã có tài khoản?',
      creating: 'Đang tạo tài khoản...',
      signingIn: 'Đang đăng nhập...'
    },
    search: {
      placeholder: 'Tìm kiếm thiết bị, kết nối, cảnh báo... (Sử dụng ↑↓ để di chuyển, Enter để chọn)',
      hint: 'Nhập từ khóa để tìm kiếm trong hạ tầng mạng',
      noMatches: 'Không tìm thấy kết quả phù hợp cho "{query}"',
      hostsCat: 'Thiết bị (Hosts)',
      peersCat: 'Kết nối (Peers)',
      alertsCat: 'Cảnh báo đang hoạt động'
    }
  }
}

export function useI18n() {
  function t(key, defaultValue = '') {
    const keys = key.split('.')
    let current = translations[locale.value]
    for (const k of keys) {
      if (current && current[k] !== undefined) {
        current = current[k]
      } else {
        return defaultValue || key
      }
    }
    return current
  }

  function setLocale(newLocale) {
    if (newLocale === 'en' || newLocale === 'vi') {
      locale.value = newLocale
      localStorage.setItem('peersight_locale', newLocale)
    }
  }

  return {
    locale,
    t,
    setLocale
  }
}
