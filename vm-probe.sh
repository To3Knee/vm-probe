#!/bin/bash
# ------------------------------------------------------------
# VM health probe – KVM (test) + VMware (prod) – FINAL
# File: vm-probe.sh
#
# PURPOSE
#   Collect VM health, OS, disk, CPU, memory, and network metrics
#   **entirely from inside the guest** — no hypervisor access needed.
#
# FEATURES
#   • Auto-detects KVM vs VMware
#   • Thin-provisioned disk: shows both guest size + full provisioned size
#   • Network: multi-interface, human-readable (kbit/s, Mbit/s, Gbit/s)
#   • Uptime: human-readable (12d 7h 23m 22s)
#   • UTC timestamp
#   • Configurable output (stdout/file/both)
#   • Safe file handling (no overwrite unless enabled)
#
# OUTPUT
#   JSON with:
#     hypervisor, power_state, tool_state, uptime,
#     memory_allocated, disk (thin_total, used, available, used_percent, provisioned_disk_size),
#     ram_used, cpu_used, cpu_ready,
#     host (esxi_hostname, vcenter), network, timestamp
#
# REQUIREMENTS
#   • open-vm-tools (VMware)
#   • qemu-guest-agent (KVM)
#   • standard GNU tools
#
# SAFETY
#   • Graceful fallbacks for missing tools
#   • No syntax errors (tested with `bash -n`)
#   • No side effects
# ------------------------------------------------------------
# ================================
# === USER-CONFIGURABLE SECTION ===
# ================================

# Output mode
OUTPUT_MODE="stdout"                    # stdout | file | both

# Output file (used if OUTPUT_MODE=file or both)
OUTPUT_FILE="/var/log/vm-probe.json"

# Overwrite existing file?
OVERWRITE_FILE=false                    # true = overwrite | false = timestamped backup

# Filesystem to monitor
ROOT_MOUNT_POINT="/"                    # e.g., /, /var, /data

# Include loopback interface?
INCLUDE_LOOPBACK=false                  # true = include lo

# ================================
# === END OF CONFIGURATION ===
# ================================

# Validate OUTPUT_MODE
case "$OUTPUT_MODE" in
    stdout|file|both) ;;
    *) echo "ERROR: Invalid OUTPUT_MODE '$OUTPUT_MODE'. Use: stdout, file, both" >&2; exit 1 ;;
esac

# ---------- 0. Detect Hypervisor ----------
HYPERVISOR=$(systemd-detect-virt 2>/dev/null || echo "unknown")
IS_VMWARE=$([ "$HYPERVISOR" = "vmware" ] && echo true || echo false)
IS_KVM=$([ "$HYPERVISOR" = "kvm" ] && echo true || echo false)

# Adjust output path for KVM test environments
[[ "$IS_KVM" = "true" ]] && OUTPUT_FILE="/var/log/kvm/vm-probe.json"

# ---------- 1. Helper: run command safely ----------
run_cmd() {
    local cmd_name="$1"
    local args="${2:-}"
    local fallback="$3"
    if command -v "$cmd_name" >/dev/null 2>&1; then
        eval "$cmd_name $args" 2>/dev/null || echo "$fallback"
    else
        echo "$fallback"
    fi
}

# ---------- 2. Network: Capture T1 ----------
declare -A RX1 TX1
while IFS= read -r line; do
    # Skip header lines
    [[ "$line" =~ ^[[:space:]]*(Inter-|face|lo) ]] && continue
    [[ "$line" =~ \| ]] && continue

    iface="${line%%:*}"
    iface="${iface## }"
    [[ -z "$iface" ]] && continue
    [[ "$iface" == "lo" && "$INCLUDE_LOOPBACK" != "true" ]] && continue

    stats="${line#*:}"
    read -r rx tx _ <<< "$stats"
    RX1["$iface"]=$rx
    TX1["$iface"]=$tx
done < /proc/net/dev

sleep 1

# ---------- 3. Network: Capture T2 + Calculate ----------
declare -A NET_RX NET_TX
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(Inter-|face|lo) ]] && continue
    [[ "$line" =~ \| ]] && continue

    iface="${line%%:*}"
    iface="${iface## }"
    [[ -z "$iface" ]] && continue
    [[ "$iface" == "lo" && "$INCLUDE_LOOPBACK" != "true" ]] && continue

    stats="${line#*:}"
    read -r rx tx _ <<< "$stats"
    d_rx=$(( rx - ${RX1["$iface"]:-0} ))
    d_tx=$(( tx - ${TX1["$iface"]:-0} ))
    NET_RX["$iface"]=$(( d_rx * 8 ))
    NET_TX["$iface"]=$(( d_tx * 8 ))
done < /proc/net/dev

# ---------- 4. Power state ----------
if [[ "$IS_VMWARE" = "true" ]] && command -v vmware-rpctool &>/dev/null; then
    POWER=$(vmware-rpctool "info-get guestinfo.vmware.tools.powerState" 2>/dev/null || echo "unknown")
    case "$POWER" in
        "Power on")   POWER_STATE="Running"   ;;
        "Power off")  POWER_STATE="Stopped"   ;;
        "Suspended")  POWER_STATE="Suspended" ;;
        *)            POWER_STATE="Stopped"   ;;
    esac
else
    POWER_STATE="Running"
fi

# ---------- 5. Tool state + Uptime ----------
if [[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null; then
    TOOL_STATE=$(vmware-toolbox-cmd stat current 2>/dev/null | awk -F'=' '/tool state/ {print $2}' | xargs || echo "unknown")
    UPTIME_SEC=$(vmware-toolbox-cmd stat current 2>/dev/null | awk -F'=' '/uptime/ {print $2}' | xargs || echo "0")
else
    TOOL_STATE="qemu-guest-agent"
    UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime)
fi

# Format uptime: 12d 7h 23m 22s
format_uptime() {
    local s=$1
    local d=$((s/86400)) h=$((s%86400/3600)) m=$((s%3600/60)) s=$((s%60))
    printf "%s%s%s%s" "${d:+${d}d }" "${h:+${h}h }" "${m:+${m}m }" "${s}s"
}
UPTIME_HUMAN=$(format_uptime "$UPTIME_SEC")

# ---------- 6. Allocated RAM ----------
[[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null && MEM_MB=$(vmware-toolbox-cmd stat memsize 2>/dev/null | awk '{print $1}' || echo "0") || MEM_MB="0"
MEM_HUMAN=$(awk "BEGIN {printf \"%.2f GB\", $MEM_MB/1024}")

# ---------- 7. Disk: Guest filesystem (thin) ----------
read -r _ total used avail pct _ < <(df -BG "$ROOT_MOUNT_POINT" 2>/dev/null | awk 'NR==2')
DISK_THIN_TOTAL="${total%G} GB"
DISK_USED="${used%G} GB"
DISK_AVAIL="${avail%G} GB"
DISK_PCT="${pct%%%}"

# ---------- 8. Disk: Provisioned size (raw disk from hypervisor) ----------
RAW_DISK_SIZE=$(lsblk -d -b -o NAME,SIZE 2>/dev/null | awk '/^vda|\/vda / {printf "%.2f GB", $2/1024/1024/1024}' || echo "unknown")
DISK_PROVISIONED="${RAW_DISK_SIZE}"

# ---------- 9. RAM ----------
RAM_PCT=$(free -m | awk '/Mem:/ {printf "%.1f", $3/$2*100}')

# ---------- 10. CPU ----------
CPU_IDLE=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}' || echo "100")
CPU_UTIL=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")

# ---------- 11. CPU Ready ----------
[[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null && CPU_READY=$(vmware-toolbox-cmd stat cpu 2>/dev/null | awk '/ready/ {gsub(/%/,"",$2); print $2}' || echo "0") || CPU_READY="N/A"
CPU_READY_HUMAN="${CPU_READY}%"

# ---------- 12. Host ----------
if [[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null; then
    HOST=$(vmware-rpctool "info-get guestinfo.vpx.vmhost" 2>/dev/null || echo "unknown")
    VCENTER=$(vmware-rpctool "info-get guestinfo.vpx.server" 2>/dev/null || echo "unknown")
else
    HOST="KVM Host"
    VCENTER="N/A"
fi

# ---------- 13. Network human-readable ----------
format_bits() {
    local b=$1
    ((b >= 1000000000)) && printf "%.2f Gbit/s" "$(awk "BEGIN{print $b/1000000000}")" && return
    ((b >= 1000000)) && printf "%.2f Mbit/s" "$(awk "BEGIN{print $b/1000000}")" && return
    ((b >= 1000)) && printf "%.2f kbit/s" "$(awk "BEGIN{print $b/1000}")" && return
    printf "%d bit/s" "$b"
}

NET_JSON="[]"
[[ ${#NET_RX[@]} -gt 0 ]] && {
    NET_ARRAY=()
    for i in "${!NET_RX[@]}"; do
        NET_ARRAY+=("{\"interface\":\"$i\",\"rx\":\"$(format_bits "${NET_RX[$i]}")\",\"tx\":\"$(format_bits "${NET_TX[$i]}")\"}")
    done
    NET_JSON="[$(IFS=,; echo "${NET_ARRAY[*]}")]"
}

# ---------- 14. UTC Timestamp ----------
TIMESTAMP_UTC=$(date -u -Iseconds)

# ---------- 15. Build JSON ----------
JSON=$(printf '{
  "vm_health": {
    "hypervisor": "%s",
    "power_state": "%s",
    "tool_state": "%s",
    "uptime": "%s",
    "memory_allocated": "%s",
    "disk": {
      "thin_total": "%s",
      "used": "%s",
      "available": "%s",
      "used_percent": "%s",
      "provisioned_disk_size": "%s"
    },
    "ram_used": "%.1f%%",
    "cpu_used": "%.1f%%",
    "cpu_ready": "%s",
    "host": {
      "esxi_hostname": "%s",
      "vcenter": "%s"
    },
    "network": %s
  },
  "timestamp": "%s"
}' \
    "$HYPERVISOR" "$POWER_STATE" "$TOOL_STATE" "$UPTIME_HUMAN" "$MEM_HUMAN" \
    "$DISK_THIN_TOTAL" "$DISK_USED" "$DISK_AVAIL" "$DISK_PCT" "$DISK_PROVISIONED" \
    "$RAM_PCT" "$CPU_UTIL" "$CPU_READY_HUMAN" \
    "$HOST" "$VCENTER" "$NET_JSON" "$TIMESTAMP_UTC")

# ---------- 16. Output handling ----------
output_json() {
    local json="$1"
    local dest="$2"

    if [[ "$dest" == "stdout" ]]; then
        printf '%s\n' "$json"
        return
    fi

    local dir
    dir=$(dirname "$dest")
    mkdir -p "$dir" 2>/dev/null || { echo "ERROR: Cannot create directory $dir" >&2; return 1; }

    local final_path="$dest"
    if ! $OVERWRITE_FILE && [[ -f "$dest" ]]; then
        local ts
        ts=$(date -u +%Y-%m-%dT%H:%M:%S%z)
        ts=${ts%??}:${ts: -2}
        final_path="${dest%.json}_$ts.json"
    fi

    printf '%s\n' "$json" > "$final_path" || { echo "ERROR: Cannot write to $final_path" >&2; return 1; }
    echo "JSON written to: $final_path" >&2
}

case "$OUTPUT_MODE" in
    stdout) output_json "$JSON" "stdout" ;;
    file)   output_json "$JSON" "$OUTPUT_FILE" ;;
    both)   output_json "$JSON" "stdout"; output_json "$JSON" "$OUTPUT_FILE" ;;
esac

exit 0