#!/bin/bash
echo "=== VM-PROBE SYSTEM COMPATIBILITY TEST ==="

# 1. Bash version
echo -n "Bash: "
bash --version | head -1

# 2. Required tools
echo "Checking tools..."
for cmd in awk date df free lsblk vmstat; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd"
    else
        echo "  ✗ $cmd MISSING"
    fi
done

# 3. Hypervisor detection
echo -n "Hypervisor: "
if command -v systemd-detect-virt &>/dev/null; then
    HYP=$(systemd-detect-virt 2>/dev/null || echo "unknown")
    echo "$HYP"
else
    echo "unknown (no systemd-detect-virt)"
fi

# 4. VMware tools (if VMware)
if [[ "$HYP" == "vmware" ]] || grep -q "VMware" /proc/scsi/scsi 2>/dev/null; then
    echo "VMware detected. Testing tools..."
    for tool in vmware-rpctool vmware-toolbox-cmd vmtoolsd; do
        if command -v "$tool" &>/dev/null; then
            echo "  ✓ $tool"
        else
            echo "  ✗ $tool MISSING"
        fi
    done
else
    echo "KVM or unknown. Skipping VMware tools."
fi

# 5. KVM guest agent
if [[ "$HYP" == "kvm" ]]; then
    if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then
        echo "  ✓ qemu-guest-agent running"
    else
        echo "  ✗ qemu-guest-agent not running or not installed"
    fi
fi

# 6. Disk detection test
echo -n "Root disk test: "
ROOT_DEV=$(df --output=source / 2>/dev/null | awk 'NR==2')
if [[ -n "$ROOT_DEV" ]]; then
    SIZE=$(lsblk -dbno SIZE "$ROOT_DEV" 2>/dev/null)
    if [[ "$SIZE" =~ ^[0-9]+$ ]]; then
        echo "$((SIZE/1024/1024/1024)) GB"
    else
        echo "unknown"
    fi
else
    echo "failed"
fi

# 7. Uptime test
echo -n "Uptime: "
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
d=$((UPTIME_SEC/86400)) h=$((UPTIME_SEC%86400/3600)) m=$((UPTIME_SEC%3600/60)) s=$((UPTIME_SEC%60))
printf "%dd %dh %dm %ds\n" "$d" "$h" "$m" "$s"

# 8. Network test
echo "Network interfaces (non-lo):"
grep -v '^ *lo:' /proc/net/dev | tail -n +3 | awk -F: '{print "  "$1}' | sed 's/ //g'

echo "=== TEST COMPLETE ==="
echo "If all tools are ✓ and values make sense → vm-probe.sh will work!"