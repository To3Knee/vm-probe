# `vm-probe.sh` – **The Ultimate VM Health Probe**  
### *KVM Test → VMware Prod → One Script, All Power*  
  
  <!-- Glow Effect -->
  <circle cx="100" cy="100" r="70" fill="none" stroke="#00D1FF" stroke-width="2" opacity="0.3"/>
</svg>

<p align="center">
  <!-- Version Badge -->
  <a href="https://github.com/To3Knee/vm-probe/releases">
    <img src="https://img.shields.io/badge/Version-v1.0.0-blue?style=flat-square" alt="Version">
  </a>

  <!-- GitHub Stars -->
  <a href="https://github.com/To3Knee/vm-probe/stargazers">
    <img src="https://img.shields.io/github/stars/To3Knee/vm-probe?style=flat-square&color=yellow" alt="GitHub Stars">
  </a>

  <!-- License -->
  <a href="https://github.com/To3Knee/vm-probe/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-HIGH%20FIVE-yellow?style=flat-square" alt="License">
  </a>

  <!-- Platforms -->
  <img src="https://img.shields.io/badge/Platforms-VMware%20%7C%20KVM-blue?style=flat-square" alt="Platforms">

  <!-- Bash -->
  <img src="https://img.shields.io/badge/Bash-5.0%2B-green?style=flat-square" alt="Bash">

---

> **"Monitor like a pro — from inside the VM, with zero hypervisor access."**  

---

## What Is `vm-probe.sh`?

A **single, self-contained Bash script** that runs **inside any Linux VM** and reports **everything you care about** — **in one clean JSON payload**.

No agents. No API keys. No vCenter. Just **pure guest-side intelligence**.

---

## Features That Make You Say *"Wow"*

| Feature | Description |
|-------|-----------|
| **Auto Hypervisor Detection** | Works on **KVM (Unraid, Proxmox)** and **VMware (ESXi, vSphere)** |
| **Thin vs Provisioned Disk** | Shows **guest size** (`thin_total`) vs **actual disk size** (`provisioned_disk_size`) |
| **Human-Readable Everything** | `8.00 GB`, `68.7%`, `1.89 kbit/s`, `12d 7h 23m 22s` |
| **Multi-Interface Network** | All NICs, no junk |
| **CPU Ready %** | **True hypervisor contention** (VMware only) |
| **Uptime** | Real system uptime on KVM, VMware Tools uptime on VMware |
| **UTC Timestamp** | ISO-8601, always |
| **Configurable Output** | `stdout`, `file`, `both` |
| **No Overwrites** | Safe file mode with timestamped backups |
| **Zero External Deps** | Uses only `open-vm-tools` (VMware) or `qemu-guest-agent` (KVM) |

---

## Sample Output (KVM Test)

```json
{
  "vm_health": {
    "hypervisor": "kvm",
    "power_state": "Running",
    "tool_state": "qemu-guest-agent",
    "uptime": "0d 0h 35m 40s",
    "memory_allocated": "0.00 GB",
    "disk": {
      "thin_total": "12 GB",
      "used": "2 GB",
      "available": "10 GB",
      "used_percent": "17",
      "provisioned_disk_size": "60.00 GB"
    },
    "ram_used": "3.6%",
    "cpu_used": "0.0%",
    "cpu_ready": "N/A%",
    "host": {
      "esxi_hostname": "KVM Host",
      "vcenter": "N/A"
    },
    "network": [
      {"interface":"enp7s0","rx":"0 bit/s","tx":"0 bit/s"},
      {"interface":"enp6s0","rx":"1.89 kbit/s","tx":"32 bit/s"}
    ]
  },
  "timestamp": "2025-10-28T19:53:50+00:00"
}
```

---

## Sample Output (VMware Production)

```json
{
  "vm_health": {
    "hypervisor": "vmware",
    "power_state": "Running",
    "tool_state": "tools ok",
    "uptime": "5d 12h 3m 22s",
    "memory_allocated": "16.00 GB",
    "disk": {
      "thin_total": "100 GB",
      "used": "45 GB",
      "available": "55 GB",
      "used_percent": "45",
      "provisioned_disk_size": "200.00 GB"
    },
    "ram_used": "68.7%",
    "cpu_used": "22.1%",
    "cpu_ready": "2.3%",
    "host": {
      "esxi_hostname": "esxi01.prod.corp",
      "vcenter": "vcenter01.prod.corp"
    },
    "network": [
      {"interface":"ens192","rx":"1.19 Mbit/s","tx":"0.89 Mbit/s"}
    ]
  },
  "timestamp": "2025-10-28T20:00:00+00:00"
}
```

---

## Requirements

| Hypervisor | Required Package |
|-----------|------------------|
| **VMware** | `open-vm-tools` |
| **KVM** | `qemu-guest-agent` |

```bash
# RHEL 7/8/9 VMWare
sudo dnf install -y open-vm-tools

# RHEL 7/8/9 KVM
sudo dnf install -y qemu-guest-agent
```

---

## Installation

```bash
sudo cp vm-probe.sh /usr/local/bin/vm-probe.sh
sudo chmod 755 /usr/local/bin/vm-probe.sh
```

---

## Configuration (Top of Script)

```bash
# === USER-CONFIGURABLE SECTION ===
OUTPUT_MODE="stdout"           # stdout | file | both
OUTPUT_FILE="/var/log/vm-probe.json"
OVERWRITE_FILE=false           # true = overwrite | false = timestamped
ROOT_MOUNT_POINT="/"           # e.g., /, /var
INCLUDE_LOOPBACK=false         # true = include lo
# ================================
```

---

## Usage Examples

### 1. **Run Once**
```bash
/usr/local/bin/vm-probe.sh | jq .
```

### 2. **Cron Every 5 Minutes**
```bash
crontab -e
*/5 * * * * /usr/local/bin/vm-probe.sh > /var/log/vm-probe.json 2>/dev/null
```

### 3. **Push to Zabbix**
```bash
*/5 * * * * /usr/local/bin/vm-probe.sh | curl -X POST -H "Content-Type: application/json" -d @- http://zabbix/api/vm_metrics
```

### 4. **Prometheus Textfile**
```bash
# Add to script (see below)
OUTPUT_MODE="prometheus" /usr/local/bin/vm-probe.sh
```

---

## Prometheus Exporter (Add to Script)

```bash
# === PROMETHEUS TEXTFILE ===
if [[ "$OUTPUT_MODE" == "prometheus" ]]; then
    PROM_FILE="/var/lib/node_exporter/textfile/vm_probes.prom"
    mkdir -p "$(dirname "$PROM_FILE")"
    {
        echo "# HELP vm_uptime_seconds VM uptime in seconds"
        echo "# TYPE vm_uptime_seconds gauge"
        echo "vm_uptime_seconds $UPTIME_SEC"
        echo "# HELP vm_memory_allocated_gb Allocated memory in GB"
        echo "# TYPE vm_memory_allocated_gb gauge"
        echo "vm_memory_allocated_gb $(awk "BEGIN {print $MEM_MB/1024}")"
        echo "# HELP vm_disk_used_percent Disk used %"
        echo "# TYPE vm_disk_used_percent gauge"
        echo "vm_disk_used_percent ${DISK_PCT}"
    } > "$PROM_FILE"
    exit 0
fi
```

---

## Grafana Dashboard

**Import this JSON** into Grafana:

```json
{
  "title": "VM Health - Thin vs Provisioned",
  "panels": [
    {
      "type": "stat",
      "title": "Power State",
      "targets": [{ "expr": "vm_power_state" }]
    },
    {
      "type": "stat",
      "title": "Uptime",
      "targets": [{ "expr": "vm_uptime_seconds", "format": "time_series" }],
      "fieldConfig": { "defaults": { "unit": "s" } }
    },
    {
      "type": "gauge",
      "title": "Disk Used % (Thin)",
      "targets": [{ "expr": "vm_disk_used_percent" }],
      "fieldConfig": { "defaults": { "unit": "percent" } }
    },
    {
      "type": "stat",
      "title": "Thin Total",
      "targets": [{ "expr": "vm_disk_thin_total_gb" }]
    },
    {
      "type": "stat",
      "title": "Provisioned Size",
      "targets": [{ "expr": "vm_disk_provisioned_gb" }],
      "fieldConfig": { "defaults": { "color": { "mode": "thresholds" } } }
    }
  ]
}
```

---

## Safety & Reliability

- **No syntax errors** → `bash -n vm-probe.sh`
- **Graceful fallbacks** → missing tools = safe defaults
- **Idempotent** → run every second if you want
- **Zero side effects** → read-only
- **Tested on**: RHEL 7, 8, 9 | KVM | VMware ESXi 7+

---

## Troubleshooting

| Symptom | Fix |
|-------|-----|
| `uptime: 0s` | Ensure `qemu-guest-agent` is running |
| `provisioned_disk_size: unknown` | Use `lsblk -d -b -o NAME,SIZE` |
| `tool_state: unknown` | Install `open-vm-tools` (VMware) |
| JSON not written | Check permissions on `OUTPUT_FILE` path |

---

## 📜 License

Licensed under the [High Five License](LICENSE) 🙌  
Give a high five to download, and a **super high, LOUD high five** to use **VM Probe**! 🎉 See the [LICENSE](LICENSE) file for the full, fist-bumping details! Permission is hereby granted, free of charge, to any person obtaining a copy...

---

## Star This Repo

If this saved you **hours of debugging**, **star it**  
If it made you look like a **genius**, **fork it**  
If it runs in production, **tell your boss**

---

> **"One script to rule them all."**  
> — *The VM Monitoring Fellowship*

---

**Deploy. Monitor. Dominate.**

---
<p align="center">
 <em>Built with 💖 by someone who hates broken monitoring.</em><br>
  <a href="https://github.com/To3Knee/vm-probe/stargazers"><img src="https://img.shields.io/github/stars/To3Knee/vm-probe?style=social" alt="GitHub Stars"></a>
 </p>











