#!/usr/bin/env bash

# Database URL
DATABASE_URL="postgres://peersight:peersight@localhost:5432/peersight?sslmode=disable"

echo "Inserting test alerts with 4 different levels into PeerSight database..."

psql "$DATABASE_URL" <<EOF
INSERT INTO alerts (org_id, type, level, message, resolved, created_at) VALUES 
('00000000-0000-0000-0000-000000000001', 'test_info', 'info', 'Đây là cảnh báo thử nghiệm mức độ INFO (Tin nhắn thông báo hệ thống)', false, NOW() - INTERVAL '1 minute'),
('00000000-0000-0000-0000-000000000001', 'test_warning', 'warning', 'Đây là cảnh báo thử nghiệm mức độ WARNING (Cảnh báo tài nguyên/cấu hình)', false, NOW() - INTERVAL '2 minute'),
('00000000-0000-0000-0000-000000000001', 'test_critical', 'critical', 'Đây là cảnh báo thử nghiệm mức độ CRITICAL (Lỗi nghiêm trọng/Offline)', false, NOW() - INTERVAL '3 minute'),
('00000000-0000-0000-0000-000000000001', 'test_debug', 'debug', 'Đây là cảnh báo thử nghiệm mức độ DEBUG (Thông tin gỡ lỗi chi tiết)', false, NOW() - INTERVAL '4 minute');
EOF

echo "Done! Check your Alerts page to see the new alerts."
