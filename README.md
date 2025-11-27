# Host & VM Management Notes

<img width="813" height="614" alt="image" src="https://github.com/user-attachments/assets/fb784199-11a5-45a3-a34c-2e1667c4739d" />


## Host Summary
- Hostname: `srv.yourdomain.com`
- Hardware: Gigabyte Technology Co., Ltd. (desktop chassis, firmware F3)
- Architecture: `x86_64`
- Operating system: Debian GNU/Linux 13 (trixie) `13.2`
- Kernel: `Linux 6.12.57+deb13-amd64` (PREEMPT_DYNAMIC)

## Virtualization Stack
- Hypervisor: KVM managed through libvirt/virsh (`qemu:///session` for per-user and `qemu:///system` for host-wide domains).
- Interactive TUI helper: **VIRT SPINNER v0.7** (`spinner.sh`) is a full-featured terminal UI built with `fzf`, `gum`, and `dialog`:
  
  **Core Features:**
  - Stylized ASCII art header with "VIRT SPINNER" logo using `gum` styling
  - **Live Host Stats Panel** displayed side-by-side with header showing:
    - CPU usage (color-coded: green/yellow/red based on load)
    - RAM usage with percentage (color-coded)
    - Load averages (1/5/15 min)
    - System uptime
    - Disk usage for all mounted drives
  - Scans both session and system libvirt connections automatically
  - Uses `fzf` for fuzzy VM selection with live state indicators (🟢 running, ⚫ shut off, 🟡 paused)
  - Dynamic menus that adapt based on VM state
  - Human-readable VM info display showing vCPUs, memory, disk size/allocation, state
  - Continuous loop—returns to VM list after each action
  - **Persistent Settings** saved to `~/.spinner_settings`
 
<img width="354" height="364" alt="image" src="https://github.com/user-attachments/assets/14a5c586-503c-4e65-b6d8-5efd2ecd1e02" />

  
  **Main Menu Options:**
  - **➕ Create New VM**: Full VM creation wizard
  - **📸 Snapshot Manager**: Complete snapshot management system (NEW in v0.7)
  - **📊 Live System Monitor**: Full-screen htop-lite view with live-updating:
    - CPU usage bar (color-coded)
    - Memory usage bar (color-coded)
    - All disk usage bars
    - Load averages
    - System uptime
    - Running VM count
    - Configurable refresh rate (default: 2 seconds)
    - Exit with Ctrl+C, ESC, or 'q'
  - **⚙️ Settings**: Configure application preferences:
    - Monitor refresh rate (1-10 seconds)
    - Disk cache mode (writeback/writethrough/none)
    - CPU mode (host-passthrough/host-model)
    - **Snapshot Settings** (NEW in v0.7):
      - Auto-snapshot enable/disable
      - Snapshot name template with placeholders: `{vm}`, `{date}`, `{time}`, `{n}`
      - Snapshot limit per VM (default: 5, 0=unlimited)
    - Settings persist across sessions
  - **🔧 Run Diagnostics**: System health checks with smart orphan detection
  - **❌ Exit**: Quit the application
  
  **📸 Snapshot System (NEW in v0.7):**
  - **Snapshot Manager** (main menu):
    - Lists all VMs with snapshot counts
    - Per-VM snapshot management submenu
    - **Snapshot Tree View**: Shows snapshot hierarchy
  - **Create Snapshot** options:
    - **Live Snapshot (with memory)**: VM stays running, saves full state like hibernate
    - **Disk-only Snapshot**: Faster, no memory state saved
    - **Graceful Shutdown + Snapshot**: Cleanly stops VM first
    - **Force Stop + Snapshot**: Immediate stop, then snapshot
    - Custom name or auto-generated from template
    - Optional description/comment for each snapshot
  - **Restore/Revert Snapshot**:
    - List shows date/time and descriptions
    - Choose graceful or force shutdown before restore
    - Double confirmation for safety
    - Warning about data loss
  - **Delete Snapshot**:
    - List with timestamps
    - Two confirmation dialogs required
  - **Snapshot Info**: Detailed view of any snapshot
  - **📸 Quick Snapshot**: Fast snapshot from VM actions menu
  - **Auto-Features**:
    - Automatic oldest snapshot deletion when limit reached
    - Name generation from configurable template

<img width="354" height="364" alt="image" src="https://github.com/user-attachments/assets/ce4365b2-d399-4019-baf4-d09513c3849f" />

  
  **VM Operations:**
  - **Create New VM**: Interactive wizard for creating VMs with:
    - VM name and OS variant selection
    - Memory and vCPU configuration
    - CPU mode (host-passthrough/host-model/default)
    - Primary disk with size and cache mode
    - Optional second disk with independent cache settings
    - Boot ISO selection from `~/iso/` directory
    - Optional second ISO (e.g., drivers)
    - Graphics options (VNC with password/listen config, SPICE with password, or headless)
    - Network configuration (NAT, bridge, or none)
    - Autoconsole option
    - Post-create connection summary showing VNC/SPICE endpoint; for bridge mode it attempts to detect the guest IP (or tells you how to find it), for NAT it reminds you to connect via the host IP
    - Summary review before creation
  - **Show VM Info**: Detailed specs including CPU, memory, disk capacity/allocation
  - **Pause/Resume**: Suspend and resume VM execution (like VMware/VirtualBox pause)
  - **Restart**: Graceful reboot
  - **Graceful Shutdown**: ACPI shutdown signal
  - **Force Stop**: Immediate power-off (with data loss warning)
  - **Delete VM**: Permanently remove VM with:
    - Two confirmation dialogs for safety
    - Automatic shutdown if VM is running
    - Removes only managed qcow2 disks (preserves ISOs)
    - Automatic VM list refresh after deletion
  - **Clone VM**: Full-featured cloning with:
    - Auto-shutdown check (gracefully stops source VM if needed)
    - New VM name prompt with validation
    - Optional customization (disk expansion, extra disks)
    - CD-ROM ISO management: browse `~/iso/` to replace, keep, or remove ISOs
    - Disk expansion: expand primary disk to larger size
    - Additional storage: add extra disks with custom sizes
    - Automatic performance optimizations applied (CPU passthrough + disk cache)
    - Automatic VM list refresh after clone
  - **Export VM**: Creates a compressed `tar.gz` bundle with:
    - Timestamped filename (YYYY-MM-DD_HH-MM-SS format)
    - VM XML definition
    - Disk images only (ISOs are NOT exported)
    - Progress bar during disk copy and compression (requires `pv`)
    - Compression level selection (fast/balanced/max)
    - `restore.sh` helper script for easy import on another host
    - `manifest.csv` and `metadata.sh` for tracking
    - Ensures VM is shut off before exporting
  - **📸 Quick Snapshot**: Fast snapshot creation directly from VM menu (NEW in v0.7)
  - **Modify RAM**: Safely adjust RAM allocation with:
    - Requires VM to be shut off
    - Double warning/confirmation
    - Updates both max and current memory
  - **Modify CDROM**: Manage CD-ROM devices:
    - View currently mounted ISOs
    - Mount new ISO from `~/iso/` directory
    - Eject/unmount current ISO
    - Add new CDROM device
  - **Modify Storage**: Manage disk attachments:
    - View current storage devices
    - Add new qcow2 disk
    - Attach existing disk file
    - Detach disk
  - **Run Diagnostics**: Enhanced diagnostics with:
    - Session and system connection status
    - `/etc/libvirt/qemu` contents listing
    - **Smart Orphan Detection**: Automatically identifies orphaned disk images by:
      - Scanning all qcow2 files in `/var/lib/libvirt/images`
      - Checking which images are actually used by VMs
      - Color-coded display: 🟢 in use, 🔴 ORPHANED
      - Shows file sizes for orphaned images
      - Two confirmation dialogs before deletion
      - Only deletes truly orphaned images

<img width="395" height="541" alt="image" src="https://github.com/user-attachments/assets/a3e4a8b4-8d5c-4072-8839-a615950e6b9a" />

  
  **Configuration:**
  - Configurable paths at top of script: `ISO_DIR`, `DISK_DIR`, libvirt URIs
  - Performance settings: `DISK_CACHE` (writeback/none/writethrough), `CPU_MODE` (host-passthrough/host-model)
  - `MONITOR_REFRESH` for live monitor update interval (default: 2 seconds)
  - **Snapshot settings** (NEW in v0.7):
    - `SNAPSHOT_AUTO_ENABLED` - auto-snapshot before risky operations
    - `SNAPSHOT_NAME_TEMPLATE` - customizable naming with placeholders
    - `SNAPSHOT_LIMIT` - max snapshots per VM (auto-deletes oldest)
  - Auto-dependency check on startup (installs missing: `fzf`, `dialog`, `libvirt-clients`, `qemu-utils`, `virt-manager`, `rsync`, `net-tools`, `pv`, `gum`)
  - Clone and create operations automatically apply performance optimizations
  
  **Credits:** A project by Lefteris Iliadis (me@lefteros.com), made with help of Cursor.ai

- Usage: `bash /home/dietpi/spinner.sh` (dependencies auto-install on first run)
- Requirements: `dietpi` is in the `libvirt` and `kvm` groups, so you can run `virsh`/`virt-install` commands without prefixing `sudo` once you re-log or reboot.

## Backups
- Backups live under `/home/dietpi/backups`. When requested, archive the management scripts with maximum compression:
  ```
  mkdir -p ~/backups
  tar -cJf ~/backups/virt-spinner-$(date +%Y%m%d-%H%M%S).tar.xz \
    ~/spinner.sh ~/spin-win11.sh ~/README.md
  ```
  (Using `tar -cJf` applies xz compression at the highest ratio.)

## ISO Library
ISOs live in `/home/dietpi/iso` for convenient access during VM creation. Current images include:
- `DietPi_NativePC-BIOS-x86_64-Trixie_Installer.iso`
- `DietPi_NativePC-UEFI-x86_64-Trixie_Installer.iso`
- `proxmox-ve_9.1-1.iso`
- `virtio-win.iso`

The helper script `/home/dietpi/spin-win11.sh` uses the Tiny11 image plus the virtio drivers to install a lightweight Windows 11 VM with 4 vCPUs, 4 GiB RAM, and a 100 GiB virtio disk, exposing VNC on `0.0.0.0` with password `123456aA`. **Performance optimizations:** `cache=writeback` for faster disk I/O and `--cpu host-passthrough` for native CPU performance.

<img width="626" height="437" alt="image" src="https://github.com/user-attachments/assets/ad37cc54-9fb7-4429-91e3-5f533c97e897" />


## Quick Start
1. Ensure libvirtd is running: `sudo systemctl status libvirtd`.
2. Create/import guests as needed (see `spin-win11.sh` for a reference command; if a previous attempt left `garsonistas-w11.qcow2` behind, you can remove it directly from the diagnostics prompt).
3. Log out/in (or reboot) after the group change so your shell picks up the `libvirt` and `kvm` memberships.
4. Launch the management helper: `bash /home/dietpi/spinner.sh`.
5. Use the menu to start/stop/reboot guests, gather dominfo/domstats, or run diagnostics to verify definitions/disks across libvirt contexts.

