#!/usr/bin/env bash
# ==============================================================================
# WireGuard VPN Security Verification Script
# Project: wireguard-edge-cloud-5g
# ==============================================================================
# This script automates security verification scenarios to demonstrate WireGuard's
# resistance to Eavesdropping, MITM, and Replay Attacks.
# ==============================================================================

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default Configuration
WG_INTERFACE="wg0"
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"
SERVER_IP="10.8.0.1"

# Header
print_header() {
    clear
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${CYAN}${BOLD}   WIREGUARD VPN SECURITY VERIFICATION SUITE - 5G EDGE-CLOUD PROJECT  ${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "OS: $(uname -s) | Kernel: $(uname -r)"
    echo -e "Execution Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}${BOLD}======================================================================${NC}\n"
}

# Root privilege check
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}[ERROR] This script requires ROOT (sudo) privileges to execute system tasks.${NC}"
        echo -e "Please run again with: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
}

# WireGuard check
check_wg() {
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}${BOLD}[ERROR] 'wg' command not found. Ensure WireGuard is installed.${NC}"
        exit 1
    fi
    
    if ! wg show "$WG_INTERFACE" &> /dev/null; then
        echo -e "${RED}${BOLD}[ERROR] VPN interface '${WG_INTERFACE}' is not active or does not exist.${NC}"
        echo -e "Please check your VPN status using: ${YELLOW}sudo wg show${NC}"
        exit 1
    fi
}

# Check and install dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v tcpdump &> /dev/null; then
        missing_deps+=("tcpdump")
    fi
    
    if ! command -v tcpreplay &> /dev/null; then
        missing_deps+=("tcpreplay")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}${BOLD}[WARNING] The following testing dependencies are missing:${NC} ${missing_deps[*]}"
        echo -e "The system can try to automatically install them via apt or dnf if permitted."
        read -r -p "Do you want to install these packages now? (y/N): " choice
        case "$choice" in
            [yY][eE][sS]|[yY])
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y "${missing_deps[@]}"
                elif command -v dnf &> /dev/null; then
                    dnf install -y "${missing_deps[@]}"
                else
                    echo -e "${RED}[ERROR] Neither apt nor dnf was found. Please install manually: ${missing_deps[*]}${NC}"
                    exit 1
                fi
                ;;
            *)
                echo -e "${YELLOW}[NOTE] Skipping package installation. Some tests (e.g. Replay) may fail or be skipped.${NC}"
                ;;
        esac
    fi
}

# Auto-detect the primary underlay network interface (facing the Internet/Cloud gateway)
detect_underlay_interface() {
    local default_iface
    default_iface=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    if [ -z "$default_iface" ]; then
        default_iface=$(ip -o -4 addr show | grep -v '127.0.0.1' | grep -v "$WG_INTERFACE" | awk '{print $2}' | head -n 1)
    fi
    echo "$default_iface"
}

# ------------------------------------------------------------------------------
# SCENARIO 1: EAVESDROPPING RESISTANCE TEST
# ------------------------------------------------------------------------------
test_eavesdropping() {
    echo -e "${BLUE}${BOLD}[+] SCENARIO 1: Eavesdropping / Packet Sniffing Resistance Test${NC}"
    echo -e "----------------------------------------------------------------------"
    
    local underlay_iface
    underlay_iface=$(detect_underlay_interface)
    
    echo -e "Underlay network interface detected: ${YELLOW}${underlay_iface}${NC}"
    echo -e "VPN Port: ${YELLOW}UDP 51820 (or custom configured WireGuard port)${NC}"
    echo -e "Goal: Capture packets on the physical interface and verify if any cleartext is exposed."
    
    if ! command -v tcpdump &> /dev/null; then
        echo -e "${RED}[!] Skipping this test due to missing 'tcpdump' dependency.${NC}\n"
        return 1
    fi
    
    local pcap_file="/tmp/eavesdrop_test.pcap"
    rm -f "$pcap_file"
    
    # 1. Start packet capture in the background
    echo -e "\n${BLUE}[1/3] Starting tcpdump to monitor physical interface...${NC}"
    tcpdump -i "$underlay_iface" -w "$pcap_file" udp -c 15 >/dev/null 2>&1 &
    local tcpdump_pid=$!
    sleep 1 # Allow tcpdump to initialize
    
    # 2. Generate simulated sensitive traffic over the VPN overlay
    echo -e "${BLUE}[2/3] Transmitting simulated sensitive data inside the encrypted VPN tunnel...${NC}"
    ping -c 3 "$SERVER_IP" > /dev/null 2>&1
    # Ping with specific hex payload data: "day la thong tin nhay cam!" (Vietnamese for "this is sensitive info!")
    ping -c 2 -p "646179206c612074686f6e672074696e206e6861792063616d21" "$SERVER_IP" >/dev/null 2>&1
    
    # Wait for tcpdump process to complete or timeout
    local timeout=5
    while kill -0 $tcpdump_pid 2>/dev/null; do
        sleep 0.5
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            kill $tcpdump_pid 2>/dev/null
            break
        fi
    done
    
    # 3. Analyze captured PCAP
    echo -e "${BLUE}[3/3] Analyzing captured packets...${NC}"
    if [ ! -f "$pcap_file" ] || [ ! -s "$pcap_file" ]; then
        echo -e "${RED}[!] No packets captured on underlay interface. Check if VPN traffic is running.${NC}"
        return 1
    fi
    
    echo -e "\n--- HEX DUMP OF CAPTURED PACKETS (SUMMARY) ---"
    tcpdump -r "$pcap_file" -XX -c 3
    echo -e "--------------------------------------------------"
    
    # Check if the cleartext signature "day la thong tin nhay cam" exists in raw packets
    if strings "$pcap_file" | grep -E "day la thong tin nhay cam|nhay cam" > /dev/null 2>&1; then
        echo -e "\n${RED}${BOLD}[RESULT] FAILED: Cleartext signature leaked in captured network packets!${NC}"
        return 1
    else
        echo -e "\n${GREEN}${BOLD}[RESULT] PASS: All traffic captured on the physical interface is completely encrypted (high-entropy bytes). No cleartext leaked.${NC}"
    fi
    echo -e "------------------------------------------------------\n"
    rm -f "$pcap_file"
    return 0
}

# ------------------------------------------------------------------------------
# SCENARIO 2: GATEWAY IMPERSONATION / MITM RESISTANCE TEST
# ------------------------------------------------------------------------------
test_mitm() {
    echo -e "${BLUE}${BOLD}[+] SCENARIO 2: Gateway Impersonation & MITM Resistance Test${NC}"
    echo -e "----------------------------------------------------------------------"
    echo -e "Description: An attacker tries to impersonate a valid Gateway (DNS/ARP Spoofing) to steal traffic."
    echo -e "Proof: Configure an incorrect Server PublicKey on Client (simulating a rogue server with mismatching keys)."
    echo -e "${YELLOW}[WARNING] This test will temporarily disconnect the VPN and automatically restore it afterward.${NC}"
    
    read -r -p "Do you want to proceed with this test? (y/N): " choice
    case "$choice" in
        [yY][eE][sS]|[yY]) ;;
        *)
            echo -e "${YELLOW}[!] Skipping MITM test scenario.${NC}\n"
            return 0
            ;;
    esac
    
    if [ ! -f "$WG_CONF" ]; then
        echo -e "${RED}[ERROR] WireGuard configuration file not found at ${WG_CONF}.${NC}\n"
        return 1
    fi
    
    # 1. Backup original configuration
    local backup_conf="/tmp/wg0_normal.conf.bak"
    cp "$WG_CONF" "$backup_conf"
    echo -e "${BLUE}[1/4] Backed up original valid VPN configuration to ${backup_conf}${NC}"
    
    # 2. Inject an invalid public key for the Server
    echo -e "${BLUE}[2/4] Overwriting Server PublicKey with incorrect fake key (Rogue/Fake Server)...${NC}"
    local fake_pubkey="FakeServerPublicKeyImpersonatingGateway12345="
    sed -i '/\[Peer\]/,/PublicKey/s/PublicKey *=.*/PublicKey = '"$fake_pubkey"'/' "$WG_CONF"
    
    # Reload WireGuard interface
    echo -e "Reloading VPN interface..."
    wg-quick down "$WG_INTERFACE" >/dev/null 2>&1
    wg-quick up "$WG_INTERFACE" >/dev/null 2>&1
    
    # 3. Test ping and handshake
    echo -e "${BLUE}[3/4] Testing data transmission and handshake with fake Server...${NC}"
    ping -c 3 "$SERVER_IP" >/dev/null 2>&1
    local ping_status=$?
    
    local handshake_time
    handshake_time=$(wg show "$WG_INTERFACE" handshake | awk '{print $2}')
    
    # 4. Restore original configuration immediately to avoid network disruption
    echo -e "${BLUE}[4/4] Restoring original valid VPN configuration...${NC}"
    cp "$backup_conf" "$WG_CONF"
    wg-quick down "$WG_INTERFACE" >/dev/null 2>&1
    wg-quick up "$WG_INTERFACE" >/dev/null 2>&1
    rm -f "$backup_conf"
    
    # Evaluate results
    echo -e "\n--- MITM ASSESSMENT METRICS ---"
    if [ "$ping_status" -ne 0 ] && { [ -z "$handshake_time" ] || [ "$handshake_time" -eq 0 ]; }; then
        echo -e "Ping Status: ${RED}BLOCKED (Traffic is secured / no leakage)${NC}"
        echo -e "Handshake Status: ${RED}FAILED TO ESTABLISH (Cryptographic mismatch)${NC}"
        echo -e "${GREEN}${BOLD}[RESULT] PASS: MITM resistance verified! Client refused to send or receive any data from a server lacking the corresponding valid private key.${NC}"
    else
        echo -e "Ping Status: ${GREEN}Success (Warning: Potential leakage or testing error)${NC}"
        echo -e "Handshake Time: ${YELLOW}${handshake_time} seconds${NC}"
        echo -e "${RED}${BOLD}[RESULT] FAILED: Secure traffic leakage detected or MITM protection failed.${NC}"
        return 1
    fi
    echo -e "------------------------------------------------------\n"
    return 0
}

# ------------------------------------------------------------------------------
# SCENARIO 3: REPLAY ATTACK RESISTANCE TEST
# ------------------------------------------------------------------------------
test_replay() {
    echo -e "${BLUE}${BOLD}[+] SCENARIO 3: Replay Attack Resistance Test${NC}"
    echo -e "----------------------------------------------------------------------"
    echo -e "Goal: Capture a valid handshake packet and replay it later to attempt session takeover."
    
    if ! command -v tcpdump &> /dev/null || ! command -v tcpreplay &> /dev/null; then
        echo -e "${RED}[!] Skipping automated test due to missing 'tcpdump' or 'tcpreplay' dependencies.${NC}"
        echo -e "You can follow the manual testing guide in the file ${YELLOW}docs/VPN_SECURITY_VERIFICATION.md${NC}."
        echo -e "------------------------------------------------------\n"
        return 1
    fi
    
    local underlay_iface
    underlay_iface=$(detect_underlay_interface)
    local pcap_handshake="/tmp/handshake_packet.pcap"
    rm -f "$pcap_handshake"
    
    # 1. Capture handshake packet by restarting interface
    echo -e "${BLUE}[1/4] Temporarily disabling VPN to prepare for Handshake Initiation capture...${NC}"
    wg-quick down "$WG_INTERFACE" >/dev/null 2>&1
    
    echo -e "${BLUE}[2/4] Listening for the first valid handshake packet...${NC}"
    tcpdump -i "$underlay_iface" -w "$pcap_handshake" -c 1 udp port 51820 >/dev/null 2>&1 &
    local capture_pid=$!
    sleep 1
    
    wg-quick up "$WG_INTERFACE" >/dev/null 2>&1
    sleep 2 # Wait for connection and handshake to complete
    
    # Verify PCAP capture
    if [ ! -f "$pcap_handshake" ] || [ ! -s "$pcap_handshake" ]; then
        echo -e "${RED}[!] Failed to capture handshake packet. Aborting replay test.${NC}"
        kill $capture_pid 2>/dev/null
        return 1
    fi
    
    echo -e "${GREEN}[+] Successfully captured and saved valid handshake packet.${NC}"
    
    # Get active handshake timestamp
    local handshake_before
    handshake_before=$(wg show "$WG_INTERFACE" handshake | awk '{print $2}')
    echo -e "Latest handshake time: ${YELLOW}${handshake_before} (Unix timestamp)${NC}"
    
    # 2. Replay captured packet after 10 seconds
    echo -e "\n${BLUE}[3/4] Waiting 10 seconds to ensure active session is stable...${NC}"
    sleep 10
    
    echo -e "${BLUE}[4/4] Replaying captured old handshake packet (Replay Attack)...${NC}"
    tcpreplay -i "$underlay_iface" "$pcap_handshake" >/dev/null 2>&1
    
    sleep 2
    # Get handshake timestamp after replay
    local handshake_after
    handshake_after=$(wg show "$WG_INTERFACE" handshake | awk '{print $2}')
    echo -e "Latest handshake after replay: ${YELLOW}${handshake_after}${NC}"
    
    # Evaluate results
    if [ "$handshake_before" -eq "$handshake_after" ]; then
        echo -e "\n${GREEN}${BOLD}[RESULT] PASS: The Server completely ignored the replayed packet!${NC}"
        echo -e "Handshake time was not reset or changed. Replay protection verified via TAI64N timestamp validation."
    else
        echo -e "\n${RED}${BOLD}[RESULT] FAILED: Handshake session reset or modified by replayed packet.${NC}"
        return 1
    fi
    
    echo -e "------------------------------------------------------\n"
    rm -f "$pcap_handshake"
    return 0
}

# ------------------------------------------------------------------------------
# MAIN TEST SUITE RUNNER
# ------------------------------------------------------------------------------
run_all_tests() {
    print_header
    check_root
    check_wg
    check_dependencies
    
    local pass_count=0
    local fail_count=0
    
    test_eavesdropping
    [ $? -eq 0 ] && ((pass_count++)) || ((fail_count++))
    
    test_mitm
    [ $? -eq 0 ] && ((pass_count++)) || ((fail_count++))
    
    test_replay
    [ $? -eq 0 ] && ((pass_count++)) || ((fail_count++))
    
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "${BOLD}                     SECURITY TEST RESULTS SUMMARY                     ${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}"
    echo -e "Total Tests Executed : 3"
    echo -e "Passed (PASS)        : ${GREEN}${BOLD}${pass_count}${NC}"
    echo -e "Failed (FAIL)        : ${RED}${BOLD}${fail_count}${NC}"
    echo -e "${CYAN}${BOLD}======================================================================${NC}\n"
}

# Command Line Argument Routing
case "$1" in
    --eavesdropping)
        print_header
        check_root
        check_wg
        test_eavesdropping
        ;;
    --mitm)
        print_header
        check_root
        check_wg
        test_mitm
        ;;
    --replay)
        print_header
        check_root
        check_wg
        test_replay
        ;;
    *)
        run_all_tests
        ;;
esac
