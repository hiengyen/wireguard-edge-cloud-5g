# VPN Security Verification Guide | Hướng Dẫn Kịch Bản Kiểm Thử Bảo Mật VPN

🇬🇧 [English](#-english) | 🇻🇳 [Tiếng Việt](#-tiếng-việt)

---

## 🇬🇧 English

## VPN Security Verification Guide
### Verifying Resistance to Eavesdropping, MITM, and Replay Attacks

This document provides practical, safe test scenarios to demonstrate the core security properties of the WireGuard VPN solution deployed in the `wireguard-edge-cloud-5g` project.

The VPN system in this project utilizes a **Client-to-Site (Edge-to-Cloud)** model with the overlay subnet `10.8.0.0/24` (Cloud Gateway: `10.8.0.1`, Edge Clients: `10.8.0.2/32`, `10.8.0.3/32`, ...). Because WireGuard is built on modern cryptographic foundations (**Noise Protocol Framework**, **Curve25519**, **ChaCha20**, **Poly1305**, **BLAKE2s**), it resists common network attacks by default without requiring complex configurations.

Below are practical scenarios that engineering teams or security auditors can perform to verify these security guarantees.

---

```mermaid
graph TD
    subgraph Edge Node (10.8.0.2)
        A[Application / Alloy] -->|Cleartext| B(wg0 interface)
    end
    subgraph Underlay Network (Physical Network / Internet)
        B -->|ChaCha20-Poly1305 Encryption| C{Network Transmission Channel}
        C -->|Encrypted packet on port 51820| D[Attacker / Sniffer]
    end
    subgraph Cloud Gateway (10.8.0.1)
        C -->|Decryption & MAC Check| E(wg0 interface)
        E -->|Cleartext| F[Prometheus / Loki / Grafana]
    end
    style D fill:#ffcccc,stroke:#ff3333,stroke-width:2px;
```

---

### 1. Scenario 1: Proving Eavesdropping / Sniffing Resistance

#### Goal
Prove that an attacker situated on the physical transmission path (e.g., sharing the same Wi-Fi, at the ISP level, or controlling a transit router) can only see encrypted UDP packets and cannot read the actual data payloads moving through the VPN tunnel.

#### Steps to Execute

1. **Environment Preparation:**
   - Ensure the VPN connection between the Edge Client (`10.8.0.2`) and Cloud Gateway (`10.8.0.1`) is active and stable.
   - Identify the physical network interface (underlay interface, e.g., `eth0`, `wlan0`, or 5G `wwan0`) and the virtual VPN interface (`wg0`).

2. **Launch Sniffer on the Physical Network Interface:**
   On the Edge Client or an intermediate transit node, run `tcpdump` to capture packets on the public physical interface:
   ```bash
   # Replace eth0 with your actual physical interface
   sudo tcpdump -i eth0 udp port 51820 -XX -c 20 -w /tmp/underlay_traffic.pcap
   ```
   *(This captures 20 packets on WireGuard port `51820` and saves them to a pcap file).*

3. **Generate Traffic inside the VPN:**
   While `tcpdump` is running, open another terminal on the Edge Node and send sensitive data across the overlay network (e.g., ping or send system logs to Loki):
   ```bash
   ping -c 5 10.8.0.1
   # Or test Alloy's log push flow
   curl -H "Content-Type: application/json" -XPOST -d '{"streams": [{"stream": {"job": "test"}, "values": [["'"$(date +%s%N)"'", "This is extremely sensitive information!"]]}]}' http://10.8.0.1:3100/loki/api/v1/push
   ```

4. **Analyze the Captured Output:**
   Read the captured pcap file to inspect packet contents:
   ```bash
   tcpdump -r /tmp/underlay_traffic.pcap -XX
   ```

#### Expected Results & Security Proof
* **No Internal IP Leakage:** The source and destination IPs shown on the packets are only the physical public IPs of the Edge Node and the Cloud Gateway. The overlay IP addresses (`10.8.0.1` or `10.8.0.2`) are completely hidden.
* **Integrity and Encryption:** The data displayed in hex and ASCII consists entirely of high-entropy random bytes. You will not find any cleartext strings like `"This is extremely sensitive information!"` or application protocol structures (HTTP, Loki, syslog).
* **Conclusion:** The eavesdropping attack fails completely because all packets passing through the physical network are symmetrically encrypted using the **ChaCha20** algorithm.

---

### 2. Scenario 2: Proving Resistance to Man-in-the-Middle (MITM) & Tampering

MITM attacks against VPNs typically focus on either **(A) Impersonation** or **(B) Data Tampering**.

### Vector A: Server Impersonation

#### How WireGuard Protects
WireGuard uses static public-key cryptography for pre-shared authentication. The client only accepts handshakes from servers whose private keys match the configured server public key in the client configuration `/etc/wireguard/wg0.conf`.

#### Simulated Attack Scenario
Assume an attacker performs DNS Spoofing or ARP Spoofing to redirect traffic from the Edge Client to a rogue gateway under their control.

#### Steps to Execute
1. **Apply Faulty Configuration (Simulating Rogue Server Public Key):**
   On the Edge Client, modify the Server Public Key in the configuration to an invalid key (simulating a server without the correct matching private key).
   ```bash
   # Backup original config
   sudo cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak
   
   # Edit the configuration, changing the server PublicKey to a dummy valid string
   ```

2. **Restart the VPN Interface:**
   ```bash
   sudo wg-quick down wg0
   sudo wg-quick up wg0
   ```

3. **Check Connection Status:**
   ```bash
   sudo wg show wg0
   ping -c 3 10.8.0.1
   ```

#### Expected Results & Security Proof
* The `wg0` interface fails to establish a connection. Running `sudo wg show` will not display a `latest handshake` timestamp, or the handshake attempt duration will increase indefinitely without establishing.
* All outgoing packets from the client, encrypted with the incorrect public key, are silently discarded by the real server, and the client similarly rejects any responses from a server lacking the matching private key.
* **Conclusion:** An attacker attempting MITM cannot decrypt the initial handshake packets and cannot establish a tunnel, even if they successfully route the traffic to their own server.

---

### Vector B: Data Tampering

#### How WireGuard Protects
Every packet transported in the WireGuard tunnel is authenticated and encrypted using AEAD (Authenticated Encryption with Associated Data) via **ChaCha20-Poly1305**. Poly1305 produces a 16-byte Message Authentication Code (MAC) tag for every packet.

#### Simulated Attack Scenario
An attacker intercepts packets on the physical path, modifies one or more bits (e.g., altering a command or metric sent to the API), and forwards the tampered packet to the destination.

#### Steps & Theoretical Proof
Because AEAD encryption is handled directly in the OS kernel driver:
1. When the Cloud Gateway receives a tampered VPN packet, the WireGuard kernel module recalculates the Poly1305 tag using the symmetric session key.
2. Due to the modified payload, the recalculated Poly1305 tag will **not match** the tag embedded in the packet.
3. WireGuard **immediately drops the packet silently** without sending any error response to the sender (preventing side-channel leakage).

#### Verification via Kernel Logs
You can enable WireGuard debug logging on the Cloud Gateway to observe the system's response to invalid or tampered packets:
```bash
# Enable dynamic debug log for the wireguard module (requires root)
echo "module wireguard +p" | sudo tee /sys/kernel/debug/dynamic_debug/control

# Monitor system logs in real time
sudo dmesg -wT | grep wireguard
```
When a tampered or corrupted packet is received on port `51820`, the kernel logs lines such as:
`wireguard: wg0: Packet has invalid mac...` or `Packet has invalid tag...` and discards it silently, ensuring absolute application-level security.

---

### 3. Scenario 3: Proving Replay Attack Resistance

#### Goal
Prove that capturing a valid packet from the wire (such as a Handshake Initiation packet, or a transport packet containing an alert trigger) and replaying it later will be completely rejected by WireGuard, causing no duplicated action or session hijack.

```mermaid
sequenceDiagram
    autonumber
    participant Edge as Edge Node (10.8.0.2)
    participant Attacker as Replayer (Attacker)
    participant Cloud as Cloud Gateway (10.8.0.1)

    Edge->>Cloud: Send Handshake Initiation (Contains Timestamp T1)
    Note over Attacker: Intercepts & clones packet
    Cloud-->>Edge: Responds with Handshake Response (Success)

    Note over Attacker: Waits 30 seconds...
    Attacker->>Cloud: Replays Handshake Initiation (Timestamp T1)
    Note over Cloud: Checks Timestamp T1 <= T_max (T1)<br/>SILENTLY DROPS PACKET
```

#### How WireGuard Protects against Replay
1. **For Handshake Initiation Packets:**
   - WireGuard incorporates a **TAI64N** timestamp (nanosecond precision) inside the handshake payload.
   - The server maintains the largest timestamp received from each peer (`T_max`).
   - If the server receives a new handshake initiation with timestamp `T_new` where `T_new <= T_max`, the server **drops the packet immediately**.
2. **For Transport Data Packets:**
   - Every data packet contains a monotonically increasing 64-bit sequence counter.
   - The receiver uses a **sliding window** of size 2048 packets to track received sequences.
   - Any packet with a duplicate sequence number or a sequence that falls too far behind the sliding window is discarded immediately.

#### Practical Verification Steps

1. **Prepare Capture & Replay Tools:**
   We will use `tcpdump` to capture a handshake packet from the Edge Client and `tcpreplay` (or `netcat`) to replay it on the physical interface.

2. **Capture the Handshake Initiation Packet:**
   On the Edge Client, stop the VPN and prepare the capture:
   ```bash
   sudo wg-quick down wg0
   
   # Capture exactly 1 Handshake Initiation packet (usually the first outgoing UDP packet)
   sudo tcpdump -i eth0 udp port 51820 -c 1 -w /tmp/handshake_init.pcap
   ```
   In a separate terminal, bring the VPN up to trigger the handshake:
   ```bash
   sudo wg-quick up wg0
   ```
   `/tmp/handshake_init.pcap` now contains exactly one valid, encrypted Handshake Initiation packet.

3. **Execute the Replay Attack:**
   Wait 10-20 seconds for the legitimate session to establish. On an attacker-simulated node (or on the client host simulating a compromised physical NIC), replay the captured handshake packet:
   ```bash
   # Replay the captured handshake packet
   sudo tcpreplay -i eth0 /tmp/handshake_init.pcap
   ```

4. **Verify the Cloud Gateway Reaction:**
   Monitor kernel logs and VPN state on the Cloud Gateway:
   ```bash
   sudo wg show wg0
   sudo dmesg -wT | grep wireguard
   ```

#### Expected Results & Security Proof
* The active session between the Edge Client and Cloud Gateway **remains entirely uninterrupted**. The `transfer` statistics and the `latest handshake` timestamp are not reset or altered.
* The Cloud Gateway does not respond to the replayed packet. The packet is dropped at the kernel driver layer because the replayed TAI64N timestamp is less than or equal to the recorded timestamp already received from the client.
* **Conclusion:** Replay attacks fail completely. The system is immune to both handshake and data replays.

---

### 4. Summary of Security Verification Results

| Attack Vector | Attack Method | WireGuard Defense Mechanism | Test Status | Security Conclusion |
| :--- | :--- | :--- | :---: | :--- |
| **Eavesdropping** | Sniff traffic on router/ISP using `tcpdump`. | Symmetric encryption via **ChaCha20** on all payloads and inner IPs. | **PASS** | Captured bytes are completely random; inner architecture is hidden. |
| **MITM - Impersonation** | Redirect traffic to a Rogue Server (DNS/ARP Spoofing). | Noise_IK handshake bound to Server **Static Public Key** configured on Client. | **PASS** | Client refuses to handshake; traffic block is maintained. |
| **MITM - Tampering** | Mutate bits on physical line before forwarding. | Integrity check using **Poly1305 MAC** tag on every AEAD transport packet. | **PASS** | Recipient recalculates MAC tag, detects mismatch, and drops packet at kernel layer. |
| **Replay Attack** | Intercept and replay old handshake or data packet. | **TAI64N timestamps** for handshakes and **sliding window sequence numbers** for data. | **PASS** | Replayed packet is ignored instantly; current session runs uninterrupted. |

---
> [!NOTE]
> To maintain this absolute security level, it is critical to protect the private keys (`private.key`) on both the Cloud Gateway (`/etc/wireguard/private.key`) and the Edge Nodes. Access to these keys should be strictly restricted (`chmod 600`, root access only).

---

## 🇻🇳 Tiếng Việt

## Hướng dẫn Kịch bản Kiểm thử Bảo mật VPN
### Xác minh khả năng chống Eavesdropping, MITM và Replay Attacks

Tài liệu này cung cấp các kịch bản kiểm thử thực tế và an toàn nhằm chứng minh các tính chất bảo mật cốt lõi của giải pháp WireGuard VPN được triển khai trong dự án `wireguard-edge-cloud-5g`. 

Hệ thống VPN trong dự án sử dụng mô hình **Client-to-Site (Edge-to-Cloud)** với dải mạng overlay `10.8.0.0/24` (Cloud Gateway: `10.8.0.1`, Edge Clients: `10.8.0.2/32`, `10.8.0.3/32`,...). Do WireGuard được xây dựng trên nền tảng mật mã hiện đại (**Noise Protocol Framework**, **Curve25519**, **ChaCha20**, **Poly1305**, **BLAKE2s**), nó mặc định có khả năng chống lại các kiểu tấn công mạng phổ biến mà không cần cấu hình phức tạp.

Dưới đây là các kịch bản thực tế để đội ngũ kỹ thuật hoặc kiểm toán bảo mật (security auditor) có thể thực hiện nhằm xác minh các cam kết bảo mật này.

---

```mermaid
graph TD
    subgraph Edge Node (10.8.0.2)
        A[Ứng dụng / Alloy] -->|Dữ liệu rõ / Cleartext| B(Giao diện wg0)
    end
    subgraph Underlay Network (Môi trường mạng vật lý / Internet)
        B -->|Mã hóa ChaCha20-Poly1305| C{Kênh truyền dẫn mạng}
        C -->|Gói tin mã hóa port 51820| D[Kẻ tấn công / Sniffer]
    end
    subgraph Cloud Gateway (10.8.0.1)
        C -->|Giải mã & Kiểm tra MAC| E(Giao diện wg0)
        E -->|Dữ liệu rõ / Cleartext| F[Prometheus / Loki / Grafana]
    end
    style D fill:#ffcccc,stroke:#ff3333,stroke-width:2px;
```

---

## 1. Kịch bản 1: Chứng minh Khả năng chống Nghe lén (Eavesdropping / Sniffing)

### Mục tiêu
Chứng minh rằng kẻ tấn công nằm trên đường truyền vật lý (ví dụ: cùng mạng Wi-Fi, tại ISP, hoặc chiếm quyền kiểm soát router trung gian) chỉ có thể thấy các gói tin UDP mã hóa và không thể đọc được nội dung dữ liệu thực tế di chuyển trong kênh truyền VPN.

### Các bước thực hiện

1. **Chuẩn bị môi trường:** 
   - Đảm bảo kết nối VPN giữa Edge Client (`10.8.0.2`) và Cloud Gateway (`10.8.0.1`) đang hoạt động ổn định.
   - Xác định giao diện mạng vật lý (underlay interface, ví dụ: `eth0`, `wlan0` hoặc giao diện 5G `wwan0`) và giao diện ảo VPN (`wg0`).

2. **Khởi chạy Sniffer trên giao diện mạng vật lý:**
   Trên Edge Client hoặc một node trung gian, chạy công cụ capture gói tin `tcpdump` để lắng nghe trên cổng vật lý hướng ra ngoài Internet:
   ```bash
   # Thay thế eth0 bằng giao diện mạng vật lý thực tế của bạn
   sudo tcpdump -i eth0 udp port 51820 -XX -c 20 -w /tmp/underlay_traffic.pcap
   ```
   *(Lệnh trên sẽ bắt 20 gói tin đi/đến cổng WireGuard `51820` và lưu thành file pcap).*

3. **Tạo lưu lượng truy cập (Traffic) trong VPN:**
   Trong khi `tcpdump` đang chạy, mở một terminal khác trên Edge Node và gửi dữ liệu nhạy cảm qua mạng overlay (ví dụ: ping hoặc gửi log hệ thống tới Loki):
   ```bash
   ping -c 5 10.8.0.1
   # Hoặc kiểm tra luồng gửi log của Alloy
   curl -H "Content-Type: application/json" -XPOST -d '{"streams": [{"stream": {"job": "test"}, "values": [["'"$(date +%s%N)"'", "Day la thong tin cuc ky nhay sam!"]]}]}' http://10.8.0.1:3100/loki/api/v1/push
   ```

4. **Phân tích kết quả capture:**
   Đọc file pcap đã capture để kiểm tra nội dung gói tin:
   ```bash
   tcpdump -r /tmp/underlay_traffic.pcap -XX
   ```

### Kết quả & Chứng minh an toàn
* **Không lộ cấu trúc IP mạng nội bộ:** Địa chỉ nguồn và đích hiển thị trên gói tin chỉ là IP vật lý công cộng của Edge Node và Cloud Gateway. Địa chỉ IP overlay (`10.8.0.1` hay `10.8.0.2`) hoàn toàn bị ẩn đi.
* **Mã hóa toàn vẹn:** Dữ liệu hiển thị ở dạng hex và ASCII chỉ là các chuỗi byte ngẫu nhiên (high entropy bytes). Bạn sẽ không thể tìm thấy bất kỳ chuỗi văn bản rõ nào như `"Day la thong tin cuc ky nhay sam!"` hay cấu trúc giao thức ứng dụng (HTTP, Loki, syslog).
* **Kết luận:** Tấn công nghe lén thất bại hoàn toàn vì toàn bộ gói tin đi qua mạng vật lý đã được mã hóa đối xứng bằng thuật toán **ChaCha20**.

---

## 2. Kịch bản 2: Chứng minh Khả năng chống Tấn công giả mạo & Xen giữa (MITM)

Tấn công MITM đối với VPN thường chia làm hai hướng: **(A) Giả mạo thực thể (Impersonation)** và **(B) Thay đổi dữ liệu trên đường truyền (Data Tampering)**.

### Hướng A: Giả mạo Cloud Gateway (Server Impersonation)

#### Cách thức hoạt động của WireGuard
WireGuard sử dụng cơ chế xác thực dựa trên **Khóa công khai tĩnh (Static Public Key)** được cấu hình trước (Pre-shared). Client chỉ chấp nhận bắt tay (handshake) với Server có Private Key tương ứng với Public Key được chỉ định trong file cấu hình `/etc/wireguard/wg0.conf`.

#### Kịch bản kiểm thử giả định
Giả sử kẻ tấn công thực hiện DNS Spoofing hoặc ARP Spoofing để chuyển hướng lưu lượng từ Edge Client tới một máy chủ giả mạo do kẻ tấn công kiểm soát (Rogue Gateway).

#### Các bước thực hiện
1. **Thiết lập cấu hình lỗi (Mô phỏng bắt tay với Server giả mạo):**
   On the Edge Client (trên máy khách Edge), sao chép cấu hình để dự phòng:
   ```bash
   # Sao lưu cấu hình cũ
   sudo cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak
   
   # Sửa đổi cấu hình, thay đổi khóa PublicKey của Server thành một chuỗi sai ngẫu nhiên
   ```

2. **Khởi động lại giao diện VPN:**
   ```bash
   sudo wg-quick down wg0
   sudo wg-quick up wg0
   ```

3. **Kiểm tra trạng thái kết nối:**
   ```bash
   sudo wg show wg0
   ping -c 3 10.8.0.1
   ```

#### Kết quả & Chứng minh an toàn
* Giao diện `wg0` không thể thiết lập kết nối thành công. Lệnh `sudo wg show` sẽ không hiển thị trường `latest handshake` hoặc thời gian handshake sẽ tăng liên tục mà không có phản hồi thành công.
* Toàn bộ gói tin gửi đi từ Client được mã hóa bằng khóa công khai sai sẽ bị loại bỏ âm thầm bởi Server thực tế, và ngược lại, Client cũng từ chối mọi phản hồi từ Server không có Private Key tương ứng.
* **Kết luận:** Kẻ tấn công MITM dù có định tuyến được traffic về phía máy chủ của họ cũng không thể giải mã được gói tin bắt tay ban đầu và không thể thiết lập kênh truyền.

---

### Hướng B: Giả mạo/Thay đổi dữ liệu trên đường truyền (Data Tampering)

#### Cách thức hoạt động của WireGuard
Mỗi gói tin vận chuyển trong đường hầm WireGuard đều được đóng gói bằng AEAD (Authenticated Encryption with Associated Data) sử dụng **ChaCha20-Poly1305**. Poly1305 tạo ra một thẻ xác thực (MAC tag) 16-byte cho mỗi gói tin.

#### Kịch bản kiểm thử giả định
Kẻ tấn công xen giữa bắt giữ gói tin trên đường truyền vật lý, thay đổi 1 hoặc một vài bit dữ liệu (ví dụ: thay đổi mã lệnh hoặc tham số hệ thống gửi về API), sau đó chuyển tiếp gói tin đã sửa đổi tới đích.

#### Các bước thực hiện (Phân tích lý thuyết & Nhật ký hệ thống)
Do cơ chế mã hóa AEAD được xử lý trực tiếp ở tầng Kernel của hệ điều hành:
1. Khi Cloud Gateway nhận được một gói tin VPN bị thay đổi nội dung, module Kernel WireGuard sẽ thực hiện tính toán lại thẻ Poly1305 bằng khóa phiên đối xứng (symmetric session key).
2. Do dữ liệu bị thay đổi, thẻ Poly1305 được tính toán lại chắc chắn sẽ **không trùng khớp** với thẻ đính kèm trong gói tin.
3. WireGuard sẽ **ngay lập tức hủy gói tin (silent drop)** mà không gửi lại bất kỳ phản hồi lỗi nào cho kẻ tấn công (để tránh rò rỉ thông tin qua kênh phụ - side-channel leaks).

#### Cách chứng minh qua công cụ giám sát
Chúng ta có thể bật debug log của WireGuard trên Cloud Gateway để quan sát phản ứng của hệ thống khi có gói tin lỗi/bị can thiệp:
```bash
# Bật dynamic debug log cho module wireguard (yêu cầu quyền root)
echo "module wireguard +p" | sudo tee /sys/kernel/debug/dynamic_debug/control

# Theo dõi log hệ thống trong thời gian thực
sudo dmesg -wT | grep wireguard
```
Khi có gói tin bị giả mạo hoặc sai định dạng MAC gửi tới cổng `51820`, hệ thống sẽ ghi nhận các thông báo dạng:
`wireguard: wg0: Packet has invalid mac...` hoặc `Packet has invalid tag...` và tự động hủy bỏ, giữ an toàn tuyệt đối cho ứng dụng phía sau.

---

## 3. Kịch bản 3: Chứng minh Khả năng chống Tấn công Phát lại (Replay Attack)

### Mục tiêu
Chứng minh rằng kẻ tấn công bắt giữ một gói tin hợp lệ trên đường truyền (ví dụ: gói tin bắt tay khởi tạo kết nối Handshake Initiation, hoặc gói tin dữ liệu chứa hành vi kích hoạt cảnh báo) và gửi lại gói tin đó sau một khoảng thời gian sẽ bị WireGuard từ chối hoàn toàn, không thể gây ra hành vi trùng lặp hoặc giả mạo phiên.

```mermaid
sequenceDiagram
    autonumber
    participant Edge as Edge Node (10.8.0.2)
    participant Attacker as Kẻ tấn công (Replayer)
    participant Cloud as Cloud Gateway (10.8.0.1)

    Edge->>Cloud: Gửi Handshake Initiation (Chứa Timestamp T1)
    Note over Attacker: Bắt giữ & Sao chép gói tin này
    Cloud-->>Edge: Phản hồi Handshake Response (Thành công)

    Note over Attacker: Chờ 30 giây...
    Attacker->>Cloud: Phát lại gói tin Handshake ban đầu (Timestamp T1)
    Note over Cloud: Kiểm tra Timestamp T1 <= T_max (T1)<br/>HỦY GÓI TIN ÂM THẦM (Silent Drop)
```

### Cách thức hoạt động chống Replay của WireGuard

1. **Đối với gói tin Bắt tay (Handshake Initiation):**
   * WireGuard sử dụng cấu trúc thời gian **TAI64N** (độ chính xác nano giây) được mã hóa trong gói tin bắt tay.
   * Server luôn lưu trữ timestamp lớn nhất nhận được từ mỗi Peer (`T_max`).
   * Nếu Server nhận được gói tin bắt tay mới có timestamp `T_new` thỏa mãn `T_new <= T_max`, Server sẽ **loại bỏ gói tin ngay lập tức**.
2. **Đối với gói tin Dữ liệu (Transport Data):**
   * Mỗi gói tin dữ liệu chứa một số thứ tự tăng dần liên tục (64-bit sequence counter).
   * Đầu nhận sử dụng một **cửa sổ trượt (sliding window)** kích thước 2048 gói tin để theo dõi các số thứ tự đã nhận.
   * Mọi gói tin có số thứ tự bị trùng lặp hoặc tụt lại quá sâu phía sau cửa sổ trượt sẽ bị loại bỏ không điều kiện.

### Kịch bản thực hành xác minh an toàn

1. **Chuẩn bị công cụ Capture & Replay:**
   Chúng ta sẽ sử dụng `tcpdump` để bắt gói tin bắt tay từ Edge Client và công cụ `tcpreplay` hoặc `netcat` để phát lại gói tin đó trên giao diện vật lý.

2. **Bắt gói tin khởi tạo kết nối (Handshake):**
   Trên Edge Client, ngắt kết nối VPN và chuẩn bị bắt gói tin khi khởi động lại:
   ```bash
   sudo wg-quick down wg0
   
   # Bắt đầu nghe và lọc riêng gói tin Handshake Initiation (thường là gói tin UDP đầu tiên gửi đi)
   sudo tcpdump -i eth0 udp port 51820 -c 1 -w /tmp/handshake_init.pcap
   ```
   Trong một terminal khác, bật lại VPN để kích hoạt quá trình bắt tay:
   ```bash
   sudo wg-quick up wg0
   ```
   File `/tmp/handshake_init.pcap` hiện đã lưu trữ đúng 1 gói tin Handshake Initiation hợp lệ đã được mã hóa.

3. **Tiến hành tấn công phát lại (Replay Attack):**
   Đợi khoảng 10-20 giây để phiên kết nối hợp lệ thiết lập thành công. Lúc này, trên một máy tính giả lập kẻ tấn công nằm cùng phân đoạn mạng (hoặc ngay trên Edge Client mô phỏng card mạng bị hack), thực hiện phát lại gói tin đã lưu trữ:
   ```bash
   # Phát lại gói tin bắt tay hợp lệ vừa bắt được
   sudo tcpreplay -i eth0 /tmp/handshake_init.pcap
   ```

4. **Kiểm tra phản ứng của Cloud Gateway:**
   Quan sát log hệ thống và trạng thái kết nối trên Cloud Gateway:
   ```bash
   sudo wg show wg0
   sudo dmesg -wT | grep wireguard
   ```

### Kết quả & Chứng minh an toàn
* Phiên làm việc hiện tại giữa Edge Client và Cloud Gateway **không hề bị gián đoạn**. Trạng thái truyền nhận dữ liệu (`transfer`) và thời gian bắt tay gần nhất (`latest handshake`) không bị reset hoặc thay đổi.
* Cloud Gateway không phản hồi lại gói tin phát lại của kẻ tấn công, gói tin bị hủy hoàn toàn ở tầng driver kernel do timestamp TAI64N bên trong gói tin replayed nhỏ hơn hoặc bằng timestamp hiện tại đã ghi nhận từ Edge Client.
* **Kết luận:** Tấn công phát lại thất bại hoàn toàn. Hệ thống miễn nhiễm với cả replay handshake lẫn replay dữ liệu.

---

## 4. Bảng Tổng Hợp Kết Quả Đánh Giá An Toàn

| Kiểu Tấn Công | Phương Pháp Tấn Công | Cơ Chế Bảo Vệ Của WireGuard | Trạng Thế Kiểm Thử | Kết Luận Bảo Mật |
| :--- | :--- | :--- | :---: | :--- |
| **Nghe lén (Eavesdropping)** | Sniffing lưu lượng trên cổng vật lý của router/ISP bằng `tcpdump`. | Mã hóa đối xứng **ChaCha20** toàn bộ phần payload dữ liệu và IP nội bộ. | **ĐẠT (PASS)** | Dữ liệu thu được hoàn toàn là byte ngẫu nhiên, bảo mật tuyệt đối. |
| **Xen giữa (MITM) - Giả mạo** | Chuyển hướng traffic sang Server giả mạo (DNS/ARP Spoofing). | Bắt tay Noise_IK handshake ràng buộc bằng **Khóa công khai tĩnh** đã cấu hình trước của Server. | **ĐẠT (PASS)** | Client từ chối bắt tay với Server giả mạo; luồng dữ liệu bị khóa hoàn toàn. |
| **Xen giữa (MITM) - Sửa đổi** | Sửa đổi các bit dữ liệu trên đường truyền vật lý trước khi chuyển tiếp. | Xác thực toàn vẹn dữ liệu bằng thẻ **Poly1305 MAC** đi kèm mỗi gói tin AEAD. | **ĐẠT (PASS)** | Server/Client tự động phát hiện sai lệch MAC và hủy gói tin âm thầm ở tầng Kernel. |
| **Phát lại (Replay Attack)** | Bắt gói tin handshake hoặc gói dữ liệu cũ và gửi lại sau đó. | Sử dụng nhãn thời gian **TAI64N** cho handshake và **cửa sổ trượt sequence counter** cho dữ liệu. | **ĐẠT (PASS)** | Gói tin phát lại bị bỏ qua lập tức, không gây ảnh hưởng đến session đang chạy. |

---
> [!NOTE]
> Để duy trì mức độ bảo mật tuyệt đối này, điều quan trọng nhất là phải bảo vệ các tệp tin khóa riêng tư (`private.key`) trên cả Cloud Gateway (`/etc/wireguard/private.key`) và các Edge Node. Các khóa này cần được phân quyền nghiêm ngặt chỉ cho phép `root` đọc (`chmod 600`).
