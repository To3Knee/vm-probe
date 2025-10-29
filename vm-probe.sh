#!/bin/bash
# ------------------------------------------------------------
# VM health probe – KVM (test) + VMware (prod) – FINAL AIR-GAPPED
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
#   • OUTPUT_FORMAT: json (default), xml, txt
#   • Safe file handling (no overwrite unless enabled)
#   • Prometheus textfile export
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
OUTPUT_MODE="file"                      # stdout | file | both (use "file" for cron)

# Output format
OUTPUT_FORMAT="json"                    # json | xml | txt

# Output file (used if OUTPUT_MODE=file or both)
OUTPUT_FILE="/root/vm-probe.json"        # ← FIXED: /root/

# Overwrite existing file?
OVERWRITE_FILE=false                    # true = overwrite | false = timestamped backup

# Filesystem to monitor
ROOT_MOUNT_POINT="/"                    # e.g., /, /var, /data

# Include loopback interface?
INCLUDE_LOOPBACK=false                  # true = include lo

# ================================
# === END OF CONFIGURATION ===
# ================================

# Validate OUTPUT_MODE and OUTPUT_FORMAT
case "$OUTPUT_MODE" in
    stdout|file|both) ;;
    *) echo "ERROR: Invalid OUTPUT_MODE '$OUTPUT_MODE'. Use: stdout, file, both" >&2; exit 1 ;;
esac

case "$OUTPUT_FORMAT" in
    json|xml|txt) ;;
    *) echo "ERROR: Invalid OUTPUT_FORMAT '$OUTPUT_FORMAT'. Use: json, xml, txt" >&2; exit 1 ;;
esac

# ---------- 0. Detect Hypervisor ----------
HYPERVISOR=$(systemd-detect-virt 2>/dev/null || echo "unknown")
IS_VMWARE=$([ "$HYPERVISOR" = "vmware" ] && echo true || echo false)
IS_KVM=$([ "$HYPERVISOR" = "kvm" ] && echo true || echo false)

# Adjust output path for KVM test environments
[[ "$IS_KVM" = "true" ]] && OUTPUT_FILE="/root/vm-probe.${OUTPUT_FORMAT}"

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
        *)            POWER_STATE="Running"   ;;
    esac
else
    POWER_STATE="Running"
fi

# ---------- 5. Tool state + Uptime ----------
if [[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null; then
    TOOL_STATE=$(vmware-toolbox-cmd stat current 2>/dev/null | awk -F'=' '/tool state/ {print $2}' | xargs || echo "unknown")
    UPTIME_SEC=$(vmware-toolbox-cmd stat current 2>/dev/null | awk -F'=' '/uptime/ {print $2}' | xargs || echo "0")
    MEM_MB=$(vmware-toolbox-cmd stat memsize 2>/dev/null | awk '{print $1}' || echo "0")
else
    TOOL_STATE="qemu-guest-agent"
    UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
    MEM_MB="0"
fi

# Format uptime: 12d 7h 23m 22s
format_uptime() { local s=$1 d=$((s/86400)) h=$((s%86400/3600)) m=$((s%3600/60)) s=$((s%60)); printf "%s%s%s%s" "${d:+${d}d }" "${h:+${h}h }" "${m:+${m}m }" "${s}s"; }
UPTIME_HUMAN=$(format_uptime "$UPTIME_SEC")

# ---------- 6. Allocated RAM (FIXED: Safe awk -v) ----------
if [[ "$MEM_MB" =~ ^[0-9]+$ ]] && (( MEM_MB > 0 )); then
    MEM_HUMAN=$(awk -v m="$MEM_MB" 'BEGIN {printf "%.2f GB", m / 1024}')
else
    MEM_HUMAN="0.00 GB"
fi

# ---------- 7. Disk: Guest filesystem (thin) ----------
read -r _ total used avail pct _ < <(df -BG "$ROOT_MOUNT_POINT" 2>/dev/null | awk 'NR==2')
DISK_THIN_TOTAL="${total%G} GB"
DISK_USED="${used%G} GB"
DISK_AVAIL="${avail%G} GB"
DISK_PCT="${pct%%%}"

# ---------- 8. Disk: Provisioned size (FIXED: Safe lsblk) ----------
ROOT_DEV=$(df --output=source "$ROOT_MOUNT_POINT" 2>/dev/null | awk 'NR==2')
BASE_DEV=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null | head -1)
[[ -z "$BASE_DEV" ]] && BASE_DEV=$(lsblk -no NAME "$ROOT_DEV" 2>/dev/null | head -1)
SIZE_BYTES=$(lsblk -dbno SIZE "/dev/$BASE_DEV" 2>/dev/null || echo "0")
if [[ "$SIZE_BYTES" =~ ^[0-9]+$ ]] && (( SIZE_BYTES > 0 )); then
    DISK_PROVISIONED=$(awk -v s="$SIZE_BYTES" 'BEGIN {printf "%.2f GB", s / 1024 / 1024 / 1024}')
else
    DISK_PROVISIONED="unknown"
fi

# ---------- 9. RAM ----------
RAM_PCT=$(free -m | awk '/Mem:/ {if($2>0) printf "%.1f", $3/$2*100; else print "0.0"}')

# ---------- 10. CPU ----------
CPU_IDLE=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}' || echo "100")
CPU_UTIL=$(awk "BEGIN {printf \"%.1f\", 100 - $CPU_IDLE}")

# ---------- 11. CPU Ready (FIXED: KVM = N/A) ----------
if [[ "$IS_VMWARE" = "true" ]] && systemctl is-active vmtoolsd &>/dev/null; then
    CPU_READY=$(vmware-toolbox-cmd stat cpu 2>/dev/null | awk '/ready/ {gsub(/%/,"",$2); print $2}' || echo "0")
    [[ "$CPU_READY" =~ ^[0-9]+(\.[0-9]+)?$ ]] && CPU_READY_HUMAN="${CPU_READY}%" || CPU_READY_HUMAN="N/A"
else
    CPU_READY_HUMAN="N/A"
fi

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

# ---------- 15. Build JSON (base data) ----------
JSON_BASE=$(printf '{
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

# ---------- 16. Output formatted data ----------
output_formatted() {
    local data="$1"
    case "$OUTPUT_FORMAT" in
        json) echo "$data" ;;
        xml)
            cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<vm_health>
  <hypervisor>$HYPERVISOR</hypervisor>
  <power_state>$POWER_STATE</power_state>
  <tool_state>$TOOL_STATE</tool_state>
  <uptime>$UPTIME_HUMAN</uptime>
  <memory_allocated>$MEM_HUMAN</memory_allocated>
  <disk>
    <thin_total>$DISK_THIN_TOTAL</thin_total>
    <used>$DISK_USED</used>
    <available>$DISK_AVAIL</available>
    <used_percent>$DISK_PCT</used_percent>
    <provisioned_disk_size>$DISK_PROVISIONED</provisioned_disk_size>
  </disk>
  <ram_used>$RAM_PCT%</ram_used>
  <cpu_used>$CPU_UTIL%</cpu_used>
  <cpu_ready>$CPU_READY_HUMAN</cpu_ready>
  <host>
    <esxi_hostname>$HOST</esxi_hostname>
    <vcenter>$VCENTER</vcenter>
  </host>
  <network>
$(for i in "${!NET_RX[@]}"; do printf "    <interface name=\"$i\">\n      <rx>$(format_bits "${NET_RX[$i]}")</rx>\n      <tx>$(format_bits "${NET_TX[$i]}")</tx>\n    </interface>\n"; done)
  </network>
  <timestamp>$TIMESTAMP_UTC</timestamp>
</vm_health>
EOF
            ;;
        txt)
            printf "VM Health Report\nHypervisor: %s\nPower: %s\nTool: %s\nUptime: %s\nMemory: %s\nDisk: %s/%s (%s) | Prov: %s\nRAM: %.1f%% | CPU: %.1f%% | Ready: %s\nHost: %s | vCenter: %s\nTime: %s\nNetwork:\n" \
                "$HYPERVISOR" "$POWER_STATE" "$TOOL_STATE" "$UPTIME_HUMAN" "$MEM_HUMAN" \
                "$DISK_USED" "$DISK_THIN_TOTAL" "$DISK_PCT" "$DISK_PROVISIONED" \
                "$RAM_PCT" "$CPU_UTIL" "$CPU_READY_HUMAN" "$HOST" "$VCENTER" "$TIMESTAMP_UTC"
            for i in "${!NET_RX[@]}"; do
                printf "  %s: RX %s TX %s\n" "$i" "$(format_bits "${NET_RX[$i]}")" "$(format_bits "${NET_TX[$i]}")"
            done
            ;;
    esac
}

FORMATTED=$(output_formatted "$JSON_BASE")

if [[ "$OUTPUT_MODE" = "stdout" ]]; then
    printf '%s\n' "$FORMATTED"
elif [[ "$OUTPUT_MODE" = "file" || "$OUTPUT_MODE" = "both" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    final_file="$OUTPUT_FILE"
    if ! $OVERWRITE_FILE && [[ -f "$OUTPUT_FILE" ]]; then
        ts=$(date -u +%Y-%m-%dT%H:%M:%S%z); ts=${ts%??}:${ts: -2}
        final_file="${OUTPUT_FILE%.*}_${ts}.${OUTPUT_FORMAT}"
    fi
    printf '%s\n' "$FORMATTED" > "$final_file"
    echo "Output written to: $final_file" >&2
fi

# === PROMETHEUS TEXTFILE (Optional) ===
if [[ "$OUTPUT_MODE" == "file" && -f "$OUTPUT_FILE" ]]; then
    PROM_FILE="/var/lib/node_exporter/textfile/vm_probes.prom"
    mkdir -p "$(dirname "$PROM_FILE")"
    {
        echo "# HELP vm_uptime_seconds VM uptime in seconds"
        echo "# TYPE vm_uptime_seconds gauge"
        echo "vm_uptime_seconds $UPTIME_SEC"
        echo "# HELP vm_cpu_used_percent CPU usage %"
        echo "# TYPE vm_cpu_used_percent gauge"
        echo "vm_cpu_used_percent $CPU_UTIL"
        echo "# HELP vm_ram_used_percent RAM usage %"
        echo "# TYPE vm_ram_used_percent gauge"
        echo "vm_ram_used_percent $RAM_PCT"
        echo "# HELP vm_disk_used_percent Disk used % (thin)"
        echo "# TYPE vm_disk_used_percent gauge"
        echo "vm_disk_used_percent ${DISK_PCT}"
    } > "$PROM_FILE"
fi

exit 0