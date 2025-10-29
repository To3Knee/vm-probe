
<p align="center">
  <img src="logo.png" alt="VM-Probe Logo" width="260">
</p>

<h1 align="center">🖥️ VM-Probe: The Ultimate VM Health Probe 🖥️</h1>

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
</p>

---

> **"Monitor like a pro — from inside the VM, with zero hypervisor access."**  

---

## What Is `vm-probe.sh`?

A **single, self-contained Bash script** that runs **inside any Linux VM** and reports **everything you care about** — **in one clean JSON, XML, or TXT payload**.

No agents. No API keys. No vCenter. Just **pure guest-side intelligence**.

Built for **KVM (Unraid, Proxmox)** test labs and **VMware (ESXi, vSphere)** production — **one script, all power**.

---

## Features That Make You Say *"Wow"*

| Feature | Description |
|-------|-----------|
| **Auto Hypervisor Detection** | Works on **KVM** and **VMware** — no config changes needed |
| **Thin vs Provisioned Disk** | Shows **guest filesystem size** (`thin_total`) vs **hypervisor-provisioned size** (`provisioned_disk_size`) |
| **Human-Readable Everything** | `8.00 GB`, `68.7%`, `1.89 kbit/s`, `12d 7h 23m 22s` |
| **Multi-Interface Network** | All NICs monitored, clean output, no junk |
| **CPU Ready %** | **True hypervisor contention** (VMware only) |
| **Uptime** | Real system uptime on KVM, VMware Tools uptime on VMware |
| **UTC Timestamp** | ISO-8601, always |
| **Multiple Output Formats** | JSON (default), XML, TXT — choose your flavor |
| **Configurable Output** | `stdout`, `file`, `both` — with safe timestamped backups |
| **Prometheus Exporter** | Auto-generates `.prom` textfile for easy monitoring |
| **Zero External Deps** | Uses only `open-vm-tools` (VMware) or `qemu-guest-agent` (KVM) |
| **Air-Gapped Ready** | No internet, no Docker, just Bash |

---

## Sample Outputs (All Formats)

### JSON (Default)

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

### XML (For Structured Parsing)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<vm_health>
  <hypervisor>kvm</hypervisor>
  <power_state>Running</power_state>
  <tool_state>qemu-guest-agent</tool_state>
  <uptime>0d 0h 35m 40s</uptime>
  <memory_allocated>0.00 GB</memory_allocated>
  <disk>
    <thin_total>12 GB</thin_total>
    <used>2 GB</used>
    <available>10 GB</available>
    <used_percent>17</used_percent>
    <provisioned_disk_size>60.00 GB</provisioned_disk_size>
  </disk>
  <ram_used>3.6%</ram_used>
  <cpu_used>0.0%</cpu_used>
  <cpu_ready>N/A%</cpu_ready>
  <host>
    <esxi_hostname>KVM Host</esxi_hostname>
    <vcenter>N/A</vcenter>
  </host>
  <network>
    <interface name="enp7s0">
      <rx>0 bit/s</rx>
      <tx>0 bit/s</tx>
    </interface>
    <interface name="enp6s0">
      <rx>1.89 kbit/s</rx>
      <tx>32 bit/s</tx>
    </interface>
  </network>
  <timestamp>2025-10-28T19:53:50+00:00</timestamp>
</vm_health>
```

### TXT (For Simple Logs)

```
VM Health Report
Hypervisor: kvm
Power State: Running
Tool State: qemu-guest-agent
Uptime: 0d 0h 35m 40s
Memory Allocated: 0.00 GB
Disk Thin Total: 12 GB
Disk Used: 2 GB
Disk Available: 10 GB
Disk Used %: 17
Disk Provisioned: 60.00 GB
RAM Used: 3.6%
CPU Used: 0.0%
CPU Ready: N/A%
ESXi Host: KVM Host
vCenter: N/A
Timestamp: 2025-10-28T19:53:50+00:00
Network:
  enp7s0: RX 0 bit/s TX 0 bit/s
  enp6s0: RX 1.89 kbit/s TX 32 bit/s
```

### VMware Production Sample (JSON)

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
# RHEL 7/8/9  VMWare
sudo dnf install -y open-vm-tools

# RHEL 7/8/9  KVM
sudo dnf install -y qemu-guest-agent

# Enable
sudo systemctl enable --now vmtoolsd  # VMware
sudo systemctl enable --now qemu-guest-agent  # KVM
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
OUTPUT_FORMAT="json"           # json | xml | txt
OUTPUT_FILE="/var/log/vm-probe.json"
OVERWRITE_FILE=false           # true = overwrite | false = timestamped
ROOT_MOUNT_POINT="/"           # e.g., /, /var
INCLUDE_LOOPBACK=false         # true = include lo
# ================================
```

---

## Usage Examples

### 1. Run Manually (JSON)

```bash
/usr/local/bin/vm-probe.sh | jq .
```

### 2. Run Manually (XML)

```bash
OUTPUT_FORMAT="xml" /usr/local/bin/vm-probe.sh
```

### 3. Run Manually (TXT)

```bash
OUTPUT_FORMAT="txt" /usr/local/bin/vm-probe.sh
```

### 4. Add to Cron (Every 5 Minutes)

For background running (e.g., monitoring), use `OUTPUT_MODE="file"` to write to disk—no stdout needed.

```bash
crontab -e
```

```cron
*/5 * * * * /usr/local/bin/vm-probe.sh > /dev/null 2>&1
```

This updates `/var/log/vm-probe.json` (or `.xml` / `.txt`) every 5 minutes. Use `OVERWRITE_FILE=false` for timestamped versions (e.g., `vm-probe.json_2025-10-28T12:30:00+0000`).

### 5. Push to Zabbix/Prometheus

```bash
*/5 * * * * /usr/local/bin/vm-probe.sh | curl -X POST -H "Content-Type: application/json" -d @- http://zabbix/api/vm_metrics
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

Import this JSON into Grafana:

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

## RUN THE TEST SCRIPT 

The test script is to test the system before running vm-probe.sh 

---

## EXPECTED OUTPUT (Example)

```
=== VM-PROBE SYSTEM COMPATIBILITY TEST ===
Bash: GNU bash, version 5.1.16(1)-release
Checking tools...
  ✓ awk
  ✓ date
  ✓ df
  ✓ free
  ✓ lsblk
  ✓ vmstat
Hypervisor: vmware
VMware detected. Testing tools...
  ✓ vmware-rpctool
  ✓ vmware-toolbox-cmd
  ✓ vmtoolsd
Root disk test: 200 GB
Uptime: 12d 7h 23m 22s
Network interfaces (non-lo):
  ens192
  ens224
=== TEST COMPLETE ===
If all tools are ✓ and values make sense → vm-probe.sh will work!
```

---

## WHAT THIS TELLS YOU

| Check | Must Pass |
|------|----------|
| `awk`, `df`, `lsblk`, etc. | All must be `✓` |
| Hypervisor | `vmware` or `kvm` |
| VMware tools | `vmware-rpctool`, `vmware-toolbox-cmd` |
| KVM | `qemu-guest-agent` running |
| Disk size | Not `unknown` |
| Uptime | Not `0d 0h 0m 0s` |


---

## License

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
  <em>Built with 💖 by someone who hates broken monitoring.</em>
</p>



