#!/bin/bash

set -euo pipefail

# Version and Author Info
VERSION="0.9"
AUTHOR_NAME="Lefteris Iliadis"
AUTHOR_EMAIL="me@lefteros.com"

#####################################################################
# VIRT SPINNER - Configuration Variables
# Modify these paths and settings as needed for your environment
#####################################################################

# Libvirt connection URIs
SESSION_URI="qemu:///session"
SYSTEM_URI="qemu:///system"

# ISO storage directory (used for VM creation and cloning)
ISO_DIR="$HOME/iso"

# VM disk storage directory
DISK_DIR="/var/lib/libvirt/images"

# Disk cache mode (none=safer/slower, writeback=faster, writethrough=balanced)
DISK_CACHE="writeback"

# CPU mode (host-passthrough for best performance, host-model for compatibility)
CPU_MODE="host-passthrough"

# Live monitor refresh rate in seconds (1-10)
MONITOR_REFRESH=2

# Snapshot settings
SNAPSHOT_AUTO_ENABLED=false          # Auto-snapshot before risky operations
SNAPSHOT_NAME_TEMPLATE="{vm}-{date}-{time}"  # Options: {vm}, {date}, {time}, {n}
SNAPSHOT_LIMIT=5                     # Max snapshots per VM (0=unlimited)

# Required packages for VIRT SPINNER
REQUIRED_PACKAGES=("fzf" "dialog" "libvirt-clients" "qemu-utils" "virt-manager" "rsync" "net-tools" "pv")

# Gum binary location
GUM_BIN="$HOME/.local/bin/gum"

# Settings file for persistent configuration
SETTINGS_FILE="$HOME/.spinner_settings"

#####################################################################
# End Configuration
#####################################################################

# Load saved settings if exists
if [[ -f "$SETTINGS_FILE" ]]; then
  source "$SETTINGS_FILE"
fi

# Ensure gum is in PATH
export PATH="$HOME/.local/bin:$PATH"

declare -a VM_NAMES VM_URIS VM_LABELS VM_STATES
declare -A VM_SEEN

# First-run welcome screen
show_welcome_screen() {
  clear
  
  # ASCII Art Banner
  cat << 'EOF'

  ██╗   ██╗██╗██████╗ ████████╗    ███████╗██████╗ ██╗███╗   ██╗███╗   ██╗███████╗██████╗ 
  ██║   ██║██║██╔══██╗╚══██╔══╝    ██╔════╝██╔══██╗██║████╗  ██║████╗  ██║██╔════╝██╔══██╗
  ██║   ██║██║██████╔╝   ██║       ███████╗██████╔╝██║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝
  ╚██╗ ██╔╝██║██╔══██╗   ██║       ╚════██║██╔═══╝ ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗
   ╚████╔╝ ██║██║  ██║   ██║       ███████║██║     ██║██║ ╚████║██║ ╚████║███████╗██║  ██║
    ╚═══╝  ╚═╝╚═╝  ╚═╝   ╚═╝       ╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝

EOF

  # Display dynamic version and author info
  echo "                    🚀 Your Advanced VM Management Tool 🚀"
  echo "                 Version $VERSION | by $AUTHOR_NAME <$AUTHOR_EMAIL>"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Create compact package list
  local pkg_compact="${REQUIRED_PACKAGES[0]}, ${REQUIRED_PACKAGES[1]}, ${REQUIRED_PACKAGES[2]}, +5 more"
  
  # Display info in columns using simple formatting (no gum dependency)
  echo "  👋 WELCOME - First Time Setup          🔧 SETUP STEPS                    ℹ️  IMPORTANT NOTES"
  echo ""
  echo "  Features:                              1. Detect your distro            • Sudo password required"
  echo "   🖥️  Create & manage VMs                2. Install packages:             • Auto-detects all distros"
  echo "   ⚡ Quick deployment                       $pkg_compact"
  echo "   📊 Real-time monitoring                3. Install gum toolkit           • Settings saved for later"
  echo "   💾 Snapshots & backups                 4. Detect libvirt paths          • Can skip (limited features)"
  echo "   🔄 Clone & manage VMs                  5. Save config"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Get user confirmation
  read -p "🚀 Ready to set up VIRT SPINNER? [Y/n]: " confirm
  confirm=${confirm,,}  # Convert to lowercase
  
  if [[ "$confirm" == "n" || "$confirm" == "no" ]]; then
    echo ""
    echo "❌ Setup cancelled. Run again anytime to complete setup."
    echo ""
    exit 0
  fi
  
  echo ""
  echo "✨ Great! Starting setup..."
  echo ""
  sleep 1
}

# Check if this is the first run
check_first_run() {
  # Consider it first run if settings file doesn't exist
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    show_welcome_screen
    
    # Mark that we've shown the welcome screen
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cat > "$SETTINGS_FILE" << EOF
# VIRT SPINNER Settings - Auto-generated
# This file is sourced by spinner.sh to persist configuration
# Created: $(date)

# First run completed
FIRST_RUN_DONE=true
EOF
  fi
}

# Detect actual libvirt images directory
detect_libvirt_images_dir() {
  local detected_dir=""
  local distro_info pkg_manager distro
  
  # Common libvirt image directories per distro family
  declare -A DISTRO_DIRS=(
    ["debian"]="/var/lib/libvirt/images"
    ["ubuntu"]="/var/lib/libvirt/images"
    ["fedora"]="/var/lib/libvirt/images"
    ["nobara"]="/var/lib/libvirt/images"
    ["rhel"]="/var/lib/libvirt/images"
    ["centos"]="/var/lib/libvirt/images"
    ["rocky"]="/var/lib/libvirt/images"
    ["alma"]="/var/lib/libvirt/images"
    ["arch"]="/var/lib/libvirt/images"
    ["manjaro"]="/var/lib/libvirt/images"
    ["omarchy"]="/var/lib/libvirt/images"
    ["endeavouros"]="/var/lib/libvirt/images"
    ["garuda"]="/var/lib/libvirt/images"
    ["opensuse"]="/var/lib/libvirt/images"
    ["sles"]="/var/lib/libvirt/images"
    ["void"]="/var/lib/libvirt/images"
    ["alpine"]="/var/lib/libvirt/images"
    ["gentoo"]="/var/lib/libvirt/images"
  )
  
  # Method 1: Check virsh pools (most reliable if libvirt is configured)
  if command -v virsh &>/dev/null; then
    # Try system connection first
    local pool_path
    pool_path=$(virsh -c qemu:///system pool-dumpxml default 2>/dev/null | grep -oP '(?<=<path>).*(?=</path>)' | head -1)
    
    if [[ -n "$pool_path" && -d "$pool_path" ]]; then
      detected_dir="$pool_path"
      echo "✓ Detected libvirt images directory from system pool: $detected_dir" >&2
      echo "$detected_dir"
      return 0
    fi
    
    # Try session connection
    pool_path=$(virsh -c qemu:///session pool-dumpxml default 2>/dev/null | grep -oP '(?<=<path>).*(?=</path>)' | head -1)
    
    if [[ -n "$pool_path" && -d "$pool_path" ]]; then
      detected_dir="$pool_path"
      echo "✓ Detected libvirt images directory from session pool: $detected_dir" >&2
      echo "$detected_dir"
      return 0
    fi
    
    # Try to find any active pool
    local pools
    pools=$(virsh -c qemu:///system pool-list --all 2>/dev/null | awk 'NR>2 {print $1}')
    for pool in $pools; do
      pool_path=$(virsh -c qemu:///system pool-dumpxml "$pool" 2>/dev/null | grep -oP '(?<=<path>).*(?=</path>)' | head -1)
      if [[ -n "$pool_path" && -d "$pool_path" ]]; then
        detected_dir="$pool_path"
        echo "✓ Detected libvirt images directory from pool '$pool': $detected_dir" >&2
        echo "$detected_dir"
        return 0
      fi
    done
  fi
  
  # Method 2: Check libvirt configuration files
  if [[ -f /etc/libvirt/storage/default.xml ]]; then
    local pool_path
    pool_path=$(grep -oP '(?<=<path>).*(?=</path>)' /etc/libvirt/storage/default.xml 2>/dev/null | head -1)
    if [[ -n "$pool_path" && -d "$pool_path" ]]; then
      detected_dir="$pool_path"
      echo "✓ Detected libvirt images directory from config: $detected_dir" >&2
      echo "$detected_dir"
      return 0
    fi
  fi
  
  # Method 3: Check distro-specific default
  distro_info=$(detect_distro 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    distro=$(echo "$distro_info" | cut -d'|' -f1)
    
    if [[ -n "${DISTRO_DIRS[$distro]}" ]]; then
      detected_dir="${DISTRO_DIRS[$distro]}"
      if [[ -d "$detected_dir" ]]; then
        echo "✓ Using distro default directory for $distro: $detected_dir" >&2
        echo "$detected_dir"
        return 0
      fi
    fi
  fi
  
  # Method 4: Check common locations
  local common_dirs=(
    "/var/lib/libvirt/images"
    "/var/lib/libvirt/storage"
    "$HOME/.local/share/libvirt/images"
    "$HOME/libvirt/images"
  )
  
  for dir in "${common_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      detected_dir="$dir"
      echo "✓ Found libvirt images directory at: $detected_dir" >&2
      echo "$detected_dir"
      return 0
    fi
  done
  
  # Method 5: Fallback to default
  detected_dir="/var/lib/libvirt/images"
  echo "⚠️  Could not detect libvirt images directory, using default: $detected_dir" >&2
  echo "$detected_dir"
  return 0
}

# Initialize and save libvirt images directory
init_libvirt_dir() {
  # Check if already saved and valid
  if [[ -n "$DISK_DIR" && -d "$DISK_DIR" ]]; then
    return 0
  fi
  
  # Detect the directory (suppress output from detect function)
  local new_disk_dir
  new_disk_dir=$(detect_libvirt_images_dir 2>/dev/null)
  
  if [[ -n "$new_disk_dir" ]]; then
    DISK_DIR="$new_disk_dir"
    
    # Save to settings file
    if [[ -f "$SETTINGS_FILE" ]]; then
      # Update existing setting
      if grep -q "^DISK_DIR=" "$SETTINGS_FILE"; then
        sed -i "s|^DISK_DIR=.*|DISK_DIR=\"$DISK_DIR\"|" "$SETTINGS_FILE"
      else
        echo "DISK_DIR=\"$DISK_DIR\"" >> "$SETTINGS_FILE"
      fi
    else
      # Create new settings file
      cat > "$SETTINGS_FILE" << EOF
# VIRT SPINNER Settings - Auto-generated
# This file is sourced by spinner.sh to persist configuration

# Detected libvirt images directory
DISK_DIR="$DISK_DIR"
EOF
    fi
  fi
}

# Check and setup ISO directory
init_iso_dir() {
  # Check if ISO directory setting exists and is valid
  if [[ -n "$ISO_DIR" && -d "$ISO_DIR" ]]; then
    return 0
  fi
  
  # Check common ISO locations
  local common_iso_dirs=(
    "$HOME/iso"
    "$HOME/ISOs"
    "$HOME/Downloads"
    "$HOME/VMs/iso"
    "/var/lib/libvirt/images"
  )
  
  local found_dir=""
  for dir in "${common_iso_dirs[@]}"; do
    if [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -name "*.iso" 2>/dev/null | grep -q .; then
      found_dir="$dir"
      break
    fi
  done
  
  if [[ -n "$found_dir" ]]; then
    ISO_DIR="$found_dir"
  else
    # Default to ~/iso
    ISO_DIR="$HOME/iso"
  fi
  
  # Save to settings file
  if [[ -f "$SETTINGS_FILE" ]]; then
    if grep -q "^ISO_DIR=" "$SETTINGS_FILE"; then
      sed -i "s|^ISO_DIR=.*|ISO_DIR=\"$ISO_DIR\"|" "$SETTINGS_FILE"
    else
      echo "ISO_DIR=\"$ISO_DIR\"" >> "$SETTINGS_FILE"
    fi
  fi
}

# Distro detection function
detect_distro() {
  local distro=""
  local distro_family=""
  local pkg_manager=""
  
  # Try /etc/os-release first (most modern distros)
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    distro="${ID:-unknown}"
    distro_family="${ID_LIKE:-$distro}"
    
    # Handle specific distros and their families
    case "$distro" in
      ubuntu|debian|linuxmint|pop|elementary|zorin|kali|parrot|mx|deepin)
        pkg_manager="apt"
        ;;
      nobara|fedora|rhel|centos|rocky|alma|oracle)
        pkg_manager="dnf"
        [[ ! -x "$(command -v dnf)" && -x "$(command -v yum)" ]] && pkg_manager="yum"
        ;;
      arch|manjaro|endeavouros|garuda|artix|omarchy|cachyos|crystal)
        pkg_manager="pacman"
        ;;
      opensuse*|sles|sled)
        pkg_manager="zypper"
        ;;
      void)
        pkg_manager="xbps"
        ;;
      alpine)
        pkg_manager="apk"
        ;;
      gentoo|funtoo)
        pkg_manager="emerge"
        ;;
      solus)
        pkg_manager="eopkg"
        ;;
      nixos)
        pkg_manager="nix"
        ;;
      clearlinux)
        pkg_manager="swupd"
        ;;
      mageia)
        pkg_manager="urpmi"
        ;;
      slackware)
        pkg_manager="slackpkg"
        ;;
      *)
        # Try to guess based on ID_LIKE
        if [[ "$distro_family" == *"debian"* ]] || [[ "$distro_family" == *"ubuntu"* ]]; then
          pkg_manager="apt"
        elif [[ "$distro_family" == *"fedora"* ]] || [[ "$distro_family" == *"rhel"* ]]; then
          pkg_manager="dnf"
          [[ ! -x "$(command -v dnf)" && -x "$(command -v yum)" ]] && pkg_manager="yum"
        elif [[ "$distro_family" == *"arch"* ]]; then
          pkg_manager="pacman"
        elif [[ "$distro_family" == *"suse"* ]]; then
          pkg_manager="zypper"
        fi
        ;;
    esac
  fi
  
  # Fallback detection if /etc/os-release doesn't exist or didn't work
  if [[ -z "$pkg_manager" ]]; then
    if command -v apt-get &>/dev/null; then
      pkg_manager="apt"
      distro="debian-based"
    elif command -v dnf &>/dev/null; then
      pkg_manager="dnf"
      distro="fedora-based"
    elif command -v yum &>/dev/null; then
      pkg_manager="yum"
      distro="rhel-based"
    elif command -v pacman &>/dev/null; then
      pkg_manager="pacman"
      distro="arch-based"
    elif command -v zypper &>/dev/null; then
      pkg_manager="zypper"
      distro="suse-based"
    elif command -v xbps-install &>/dev/null; then
      pkg_manager="xbps"
      distro="void"
    elif command -v apk &>/dev/null; then
      pkg_manager="apk"
      distro="alpine"
    elif command -v emerge &>/dev/null; then
      pkg_manager="emerge"
      distro="gentoo"
    elif command -v eopkg &>/dev/null; then
      pkg_manager="eopkg"
      distro="solus"
    elif command -v nix-env &>/dev/null; then
      pkg_manager="nix"
      distro="nixos"
    elif command -v swupd &>/dev/null; then
      pkg_manager="swupd"
      distro="clearlinux"
    else
      echo "❌ Unable to detect package manager!"
      return 1
    fi
  fi
  
  echo "$distro|$pkg_manager"
}

# Check if a package is installed
is_package_installed() {
  local pkg="$1"
  local pkg_manager="$2"
  
  case "$pkg_manager" in
    apt)
      dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
      ;;
    dnf|yum)
      rpm -q "$pkg" &>/dev/null
      ;;
    pacman)
      pacman -Qi "$pkg" &>/dev/null
      ;;
    zypper)
      rpm -q "$pkg" &>/dev/null
      ;;
    xbps)
      xbps-query "$pkg" &>/dev/null
      ;;
    apk)
      apk info -e "$pkg" &>/dev/null
      ;;
    emerge)
      qlist -I "$pkg" &>/dev/null || equery list "$pkg" &>/dev/null
      ;;
    eopkg)
      eopkg list-installed | grep -q "^$pkg"
      ;;
    nix)
      nix-env -q | grep -q "^$pkg"
      ;;
    swupd)
      swupd bundle-list | grep -q "^$pkg"
      ;;
    urpmi)
      rpm -q "$pkg" &>/dev/null
      ;;
    slackpkg)
      ls /var/log/packages/ | grep -q "^$pkg"
      ;;
    *)
      return 1
      ;;
  esac
}

# Install packages using the appropriate package manager
install_packages() {
  local pkg_manager="$1"
  shift
  local packages=("$@")
  
  echo "Installing packages using $pkg_manager: ${packages[*]}"
  
  case "$pkg_manager" in
    apt)
      sudo apt-get update && sudo apt-get install -y "${packages[@]}"
      ;;
    dnf)
      sudo dnf install -y "${packages[@]}"
      ;;
    yum)
      sudo yum install -y "${packages[@]}"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "${packages[@]}"
      ;;
    zypper)
      sudo zypper install -y "${packages[@]}"
      ;;
    xbps)
      sudo xbps-install -Sy "${packages[@]}"
      ;;
    apk)
      sudo apk add --no-cache "${packages[@]}"
      ;;
    emerge)
      sudo emerge --ask=n "${packages[@]}"
      ;;
    eopkg)
      sudo eopkg install -y "${packages[@]}"
      ;;
    nix)
      nix-env -iA "${packages[@]}"
      ;;
    swupd)
      sudo swupd bundle-add "${packages[@]}"
      ;;
    urpmi)
      sudo urpmi --auto "${packages[@]}"
      ;;
    slackpkg)
      sudo slackpkg install "${packages[@]}"
      ;;
    *)
      echo "❌ Unsupported package manager: $pkg_manager"
      return 1
      ;;
  esac
}

# Map package names to distro-specific equivalents
map_package_name() {
  local pkg="$1"
  local pkg_manager="$2"
  
  # Return the appropriate package name for the distro
  case "$pkg_manager" in
    pacman)
      # Arch-specific package name mappings
      case "$pkg" in
        libvirt-clients) echo "libvirt" ;;
        qemu-utils) echo "qemu-base" ;;
        virt-manager) echo "virt-manager" ;;
        net-tools) echo "net-tools" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    dnf|yum)
      # Fedora/RHEL-specific mappings
      case "$pkg" in
        libvirt-clients) echo "libvirt-client" ;;
        qemu-utils) echo "qemu-img" ;;
        virt-manager) echo "virt-manager" ;;
        net-tools) echo "net-tools" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    zypper)
      # openSUSE-specific mappings
      case "$pkg" in
        libvirt-clients) echo "libvirt-client" ;;
        qemu-utils) echo "qemu-tools" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    apk)
      # Alpine-specific mappings
      case "$pkg" in
        libvirt-clients) echo "libvirt-client" ;;
        qemu-utils) echo "qemu-img" ;;
        virt-manager) echo "virt-manager" ;;
        *) echo "$pkg" ;;
      esac
      ;;
    *)
      # Default: return original name
      echo "$pkg"
      ;;
  esac
}

# Check and install dependencies
check_dependencies() {
  # Temporarily disable errexit since package checks return non-zero for missing packages
  set +e
  
  local missing=()
  local is_first_run=false
  
  # Check if this is first run (settings file was just created)
  if [[ -f "$SETTINGS_FILE" ]] && grep -q "FIRST_RUN_DONE=true" "$SETTINGS_FILE"; then
    is_first_run=true
  fi
  
  # Detect distro and package manager
  echo "📦 [1/4] Detecting Your System..."
  
  local distro_info pkg_manager distro
  distro_info=$(detect_distro)
  if [[ $? -ne 0 ]]; then
    echo "❌ Could not detect distribution. Please install manually: ${REQUIRED_PACKAGES[*]}"
    return 1
  fi
  
  distro=$(echo "$distro_info" | cut -d'|' -f1)
  pkg_manager=$(echo "$distro_info" | cut -d'|' -f2)
  
  echo "   ✅ $distro | $pkg_manager"
  
  # Check system packages
  echo ""
  echo "📋 [2/4] Checking Packages..."
  
  local installed_count=0
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    local mapped_pkg
    mapped_pkg=$(map_package_name "$pkg" "$pkg_manager")
    
    # Check if package is installed
    is_package_installed "$mapped_pkg" "$pkg_manager" 2>/dev/null
    local pkg_installed=$?
    
    if [ $pkg_installed -eq 0 ]; then
      installed_count=$((installed_count + 1))
    else
      missing+=("$mapped_pkg")
    fi
  done
  
  echo "   ✅ $installed_count/${#REQUIRED_PACKAGES[@]} already installed"
  if [ ${#missing[@]} -gt 0 ]; then
    echo "   📦 Missing: ${missing[*]}"
  fi
  echo ""
  
  # Check gum
  if [[ ! -x "$GUM_BIN" ]]; then
    echo "📥 [3/4] Installing gum toolkit..."
    
    if [[ "$is_first_run" == true ]]; then
      mkdir -p "$(dirname "$GUM_BIN")"
      if curl -sSfL https://github.com/charmbracelet/gum/releases/download/v0.14.1/gum_0.14.1_Linux_x86_64.tar.gz -o /tmp/gum.tar.gz 2>/dev/null; then
        tar -xzf /tmp/gum.tar.gz -C /tmp 2>/dev/null
        mv /tmp/gum_0.14.1_Linux_x86_64/gum "$GUM_BIN"
        chmod +x "$GUM_BIN"
        rm -rf /tmp/gum.tar.gz /tmp/gum_0.14.1_Linux_x86_64
        echo "   ✅ gum installed"
      else
        echo "   ❌ Failed to download gum"
      fi
    else
      read -p "   Install gum now? (y/n): " install_gum
      if [[ "${install_gum,,}" == "y" ]]; then
        mkdir -p "$(dirname "$GUM_BIN")"
        curl -sSfL https://github.com/charmbracelet/gum/releases/download/v0.14.1/gum_0.14.1_Linux_x86_64.tar.gz -o /tmp/gum.tar.gz 2>/dev/null
        tar -xzf /tmp/gum.tar.gz -C /tmp 2>/dev/null
        mv /tmp/gum_0.14.1_Linux_x86_64/gum "$GUM_BIN"
        chmod +x "$GUM_BIN"
        rm -rf /tmp/gum.tar.gz /tmp/gum_0.14.1_Linux_x86_64
        echo "   ✅ gum installed"
      else
        echo "   ❌ Cannot continue without gum. Exiting."
        exit 1
      fi
    fi
    echo ""
  fi
  
  # Install missing packages
  if [ ${#missing[@]} -gt 0 ]; then
    echo "🔧 [4/4] Installing Packages..."
    echo "   📦 ${missing[*]}"
    echo ""
    
    if [[ "$is_first_run" == true ]]; then
      echo "   ⏳ Installing via $pkg_manager (this may take a few minutes)..."
      install_packages "$pkg_manager" "${missing[@]}"
      if [[ $? -eq 0 ]]; then
        echo "   ✅ All packages installed!"
      else
        echo "   ⚠️  Some packages failed - install manually later"
      fi
    else
      read -p "   Install missing packages now? (requires sudo) (y/n): " install_deps
      if [[ "${install_deps,,}" == "y" ]]; then
        install_packages "$pkg_manager" "${missing[@]}"
        [[ $? -eq 0 ]] && echo "   ✅ Installed" || echo "   ❌ Failed"
      else
        echo "   ⚠️  Skipped - some features may not work"
      fi
    fi
    echo ""
  fi
  
  # Re-enable errexit
  set -e
}

# Check if this is the first run and show welcome screen
check_first_run

# Run dependency check on startup
check_dependencies

# Initialize and detect libvirt images directory
init_libvirt_dir

# Initialize and detect ISO directory
init_iso_dir

# Show completion message for first run
show_setup_complete() {
  if [[ -f "$SETTINGS_FILE" ]] && grep -q "FIRST_RUN_DONE=true" "$SETTINGS_FILE"; then
    # Check if we need to mark setup as complete
    if ! grep -q "SETUP_COMPLETE=true" "$SETTINGS_FILE"; then
      echo ""
      echo "🎉 Setup Complete! VIRT SPINNER is ready."
      echo "   Config: $SETTINGS_FILE | VM Images: $DISK_DIR"
      echo ""
      echo "🚀 Launching in 2 seconds..."
      
      # Mark setup as complete
      echo "SETUP_COMPLETE=true" >> "$SETTINGS_FILE"
      
      sleep 2
      clear
    fi
  fi
}

show_setup_complete

run_with_spinner() {
  local title="$1"
  shift
  if gum spin --spinner dot --title "$title" -- "$@"; then
    return 0
  else
    gum style --foreground 1 "✗ $title failed."
    return 1
  fi
}

# Get system stats for display
get_system_stats() {
  # CPU usage
  local cpu_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}' 2>/dev/null || echo "0")
  
  # Memory
  local mem_info
  mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}' 2>/dev/null || echo "?/?")
  local mem_percent
  mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}' 2>/dev/null || echo "0")
  
  # Load average
  local load_avg
  load_avg=$(cat /proc/loadavg | awk '{print $1}' 2>/dev/null || echo "0.00")
  
  # Uptime
  local uptime_str
  uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
  
  # Disk info - get all mounted disks (excluding tmpfs, devtmpfs, etc)
  local disk_info=""
  while read -r line; do
    local fs size used avail percent mount
    fs=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    percent=$(echo "$line" | awk '{print $5}')
    mount=$(echo "$line" | awk '{print $6}')
    
    # Shorten mount point for display
    local mount_short="$mount"
    [[ "$mount" == "/" ]] && mount_short="root"
    [[ "$mount" == "/boot/efi" ]] && mount_short="efi"
    [[ "$mount" == "/home" ]] && mount_short="home"
    
    disk_info+="$mount_short: $used/$size ($percent) "
  done < <(df -h 2>/dev/null | grep -E '^/dev/' | head -4)
  
  echo "CPU:${cpu_usage}%|RAM:${mem_info}(${mem_percent}%)|Load:${load_avg}|Up:${uptime_str}|${disk_info}"
}

# Display system stats panel
display_stats_panel() {
  local stats
  stats=$(get_system_stats)
  
  local cpu ram load uptime_str disks
  cpu=$(echo "$stats" | cut -d'|' -f1)
  ram=$(echo "$stats" | cut -d'|' -f2)
  load=$(echo "$stats" | cut -d'|' -f3)
  uptime_str=$(echo "$stats" | cut -d'|' -f4)
  disks=$(echo "$stats" | cut -d'|' -f5-)
  
  # Color based on CPU usage
  local cpu_val=${cpu#CPU:}
  cpu_val=${cpu_val%\%}
  local cpu_color=2  # green
  [[ $cpu_val -gt 50 ]] && cpu_color=3  # yellow
  [[ $cpu_val -gt 80 ]] && cpu_color=1  # red
  
  # Color based on RAM usage
  local ram_percent
  ram_percent=$(echo "$ram" | grep -oP '\(\K[0-9]+' || echo "0")
  local ram_color=2
  [[ $ram_percent -gt 50 ]] && ram_color=3
  [[ $ram_percent -gt 80 ]] && ram_color=1
  
  gum style --border rounded --border-foreground 99 --padding "0 1" \
    "$(gum style --foreground $cpu_color "$cpu") $(gum style --foreground $ram_color "$ram") $(gum style --foreground 8 "$load")" \
    "$(gum style --foreground 8 "$uptime_str")" \
    "$(gum style --foreground 6 "$disks")"
}

# Live system monitor (like htop-lite)
live_system_monitor() {
  local monitor_running=true
  
  # Trap Ctrl+C to exit gracefully
  trap 'monitor_running=false' INT TERM
  
  clear
  gum style --bold --foreground 212 "═══ Live System Monitor ═══"
  gum style --foreground 8 "Press Ctrl+C or ESC or 'q' to exit (refresh every ${MONITOR_REFRESH}s)"
  echo
  
  while $monitor_running; do
    # Check for ESC or 'q' key press (non-blocking)
    if read -rsn1 -t 0.1 key 2>/dev/null; then
      # ESC key (27 in decimal, \033 or \e)
      if [[ "$key" == $'\e' ]] || [[ "$key" == "q" ]] || [[ "$key" == "Q" ]]; then
        monitor_running=false
        break
      fi
    fi
    
    # Move cursor to line 4
    tput cup 3 0 2>/dev/null || true
    
    # Clear from cursor to end of screen
    tput ed 2>/dev/null || true
    
    # CPU info
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}') || cpu_usage=0
    local cpu_bar
    cpu_bar=$(printf '%.0f' "$cpu_usage" 2>/dev/null) || cpu_bar=0
    
    gum style --bold "CPU Usage"
    echo -n "  ["
    local i
    for ((i=0; i<50; i++)); do
      if (( i < cpu_bar / 2 )); then
        if (( cpu_bar > 80 )); then
          echo -ne "\033[31m█\033[0m"
        elif (( cpu_bar > 50 )); then
          echo -ne "\033[33m█\033[0m"
        else
          echo -ne "\033[32m█\033[0m"
        fi
      else
        echo -n "░"
      fi
    done
    echo "] ${cpu_bar}%"
    echo
    
    # Memory info
    local mem_total mem_used mem_percent
    read -r mem_total mem_used mem_percent <<< $(free | awk '/^Mem:/ {printf "%.1f %.1f %.0f", $2/1024/1024, $3/1024/1024, $3/$2*100}') || true
    mem_total=${mem_total:-0}
    mem_used=${mem_used:-0}
    mem_percent=${mem_percent:-0}
    
    gum style --bold "Memory Usage"
    echo -n "  ["
    for ((i=0; i<50; i++)); do
      if (( i < mem_percent / 2 )); then
        if (( mem_percent > 80 )); then
          echo -ne "\033[31m█\033[0m"
        elif (( mem_percent > 50 )); then
          echo -ne "\033[33m█\033[0m"
        else
          echo -ne "\033[32m█\033[0m"
        fi
      else
        echo -n "░"
      fi
    done
    echo "] ${mem_percent}% (${mem_used}G / ${mem_total}G)"
    echo
    
    # Disk usage
    gum style --bold "Disk Usage"
    while read -r line; do
      local fs size used avail percent mount
      fs=$(echo "$line" | awk '{print $1}')
      size=$(echo "$line" | awk '{print $2}')
      used=$(echo "$line" | awk '{print $3}')
      percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
      mount=$(echo "$line" | awk '{print $6}')
      
      echo -n "  $mount ["
      for ((i=0; i<30; i++)); do
        if (( i < percent * 30 / 100 )); then
          if (( percent > 90 )); then
            echo -ne "\033[31m█\033[0m"
          elif (( percent > 70 )); then
            echo -ne "\033[33m█\033[0m"
          else
            echo -ne "\033[36m█\033[0m"
          fi
        else
          echo -n "░"
        fi
      done
      echo "] ${percent}% ($used / $size)"
    done < <(df -h 2>/dev/null | grep -E '^/dev/' | head -4)
    echo
    
    # Load average
    local load1 load5 load15
    read -r load1 load5 load15 _ _ < /proc/loadavg || true
    load1=${load1:-0}
    load5=${load5:-0}
    load15=${load15:-0}
    gum style --bold "Load Average"
    echo "  1min: $load1  5min: $load5  15min: $load15"
    echo
    
    # Uptime
    gum style --bold "System Uptime"
    echo "  $(uptime -p 2>/dev/null | sed 's/up //' || echo 'unknown')"
    echo
    
    # Running VMs
    gum style --bold "Running VMs"
    local running_vms
    running_vms=$(sudo virsh -c "$SYSTEM_URI" list --state-running --name 2>/dev/null | grep -v '^$' | wc -l) || running_vms=0
    local session_vms
    session_vms=$(virsh -c "$SESSION_URI" list --state-running --name 2>/dev/null | grep -v '^$' | wc -l) || session_vms=0
    running_vms=$((running_vms + session_vms))
    echo "  $running_vms VM(s) currently running"
    
    # Check if still running before sleep
    if $monitor_running; then
      sleep "$MONITOR_REFRESH" || true
    fi
  done
  
  # Reset trap
  trap - INT TERM
  
  echo
  gum style --foreground 2 "Exiting monitor..."
  sleep 0.5
}

# Save all settings to file
save_settings() {
  cat > "$SETTINGS_FILE" << EOF
MONITOR_REFRESH=$MONITOR_REFRESH
DISK_CACHE="$DISK_CACHE"
CPU_MODE="$CPU_MODE"
SNAPSHOT_AUTO_ENABLED=$SNAPSHOT_AUTO_ENABLED
SNAPSHOT_NAME_TEMPLATE="$SNAPSHOT_NAME_TEMPLATE"
SNAPSHOT_LIMIT=$SNAPSHOT_LIMIT
EOF
}

# Settings menu
settings_menu() {
  while true; do
    clear
    gum style --bold --foreground 212 "═══ Settings ═══"
    echo
    
    local auto_status="disabled"
    [[ "$SNAPSHOT_AUTO_ENABLED" == "true" ]] && auto_status="enabled"
    
    gum style --foreground 8 "Current configuration:"
    echo
    gum style --bold --foreground 51 "General:"
    echo "  Monitor refresh rate: ${MONITOR_REFRESH}s"
    echo "  Disk cache mode: $DISK_CACHE"
    echo "  CPU mode: $CPU_MODE"
    echo
    gum style --bold --foreground 51 "Snapshots:"
    echo "  Auto-snapshot: $auto_status"
    echo "  Name template: $SNAPSHOT_NAME_TEMPLATE"
    echo "  Max per VM: $SNAPSHOT_LIMIT (0=unlimited)"
    echo
    gum style --bold --foreground 51 "Paths:"
    echo "  ISO directory: $ISO_DIR"
    echo "  Disk directory: $DISK_DIR"
    echo
    
    local choice
    choice=$(gum choose --header="Select setting to change:" \
      "Monitor Refresh Rate (${MONITOR_REFRESH}s)" \
      "Disk Cache Mode ($DISK_CACHE)" \
      "CPU Mode ($CPU_MODE)" \
      "───────── Snapshots ─────────" \
      "Auto-Snapshot ($auto_status)" \
      "Snapshot Name Template" \
      "Snapshot Limit ($SNAPSHOT_LIMIT)" \
      "← Back to Main Menu" \
      || echo "← Back to Main Menu")
    
    case "$choice" in
      "Monitor Refresh Rate"*)
        local new_rate
        new_rate=$(gum input --placeholder "Enter refresh rate in seconds (1-10)" --value "$MONITOR_REFRESH")
        if [[ "$new_rate" =~ ^[0-9]+$ ]] && (( new_rate >= 1 && new_rate <= 10 )); then
          MONITOR_REFRESH="$new_rate"
          save_settings
          gum style --foreground 2 "✓ Refresh rate set to ${MONITOR_REFRESH}s"
          sleep 1
        else
          gum style --foreground 1 "Invalid value. Must be 1-10."
          sleep 1
        fi
        ;;
      "Disk Cache Mode"*)
        local new_cache
        new_cache=$(gum choose --header="Select disk cache mode:" \
          "writeback (faster, less safe)" \
          "writethrough (balanced)" \
          "none (safer, slower)" \
          || echo "$DISK_CACHE")
        new_cache=$(echo "$new_cache" | awk '{print $1}')
        if [[ -n "$new_cache" ]]; then
          DISK_CACHE="$new_cache"
          save_settings
          gum style --foreground 2 "✓ Disk cache set to $DISK_CACHE"
          sleep 1
        fi
        ;;
      "CPU Mode"*)
        local new_cpu
        new_cpu=$(gum choose --header="Select CPU mode:" \
          "host-passthrough (best performance)" \
          "host-model (better compatibility)" \
          || echo "$CPU_MODE")
        new_cpu=$(echo "$new_cpu" | awk '{print $1}')
        if [[ -n "$new_cpu" ]]; then
          CPU_MODE="$new_cpu"
          save_settings
          gum style --foreground 2 "✓ CPU mode set to $CPU_MODE"
          sleep 1
        fi
        ;;
      "───────── Snapshots ─────────")
        # Separator, do nothing
        continue
        ;;
      "Auto-Snapshot"*)
        if [[ "$SNAPSHOT_AUTO_ENABLED" == "true" ]]; then
          SNAPSHOT_AUTO_ENABLED=false
          gum style --foreground 3 "✓ Auto-snapshot disabled"
        else
          SNAPSHOT_AUTO_ENABLED=true
          gum style --foreground 2 "✓ Auto-snapshot enabled"
          gum style --foreground 8 "  Snapshots will be created before risky operations"
        fi
        save_settings
        sleep 1
        ;;
      "Snapshot Name Template"*)
        echo
        gum style --foreground 8 "Available placeholders:"
        echo "  {vm}   - VM name"
        echo "  {date} - Date (YYYYMMDD)"
        echo "  {time} - Time (HHMMSS)"
        echo "  {n}    - Sequential number"
        echo
        gum style --foreground 8 "Examples:"
        echo "  {vm}-{date}-{time}  → emb-w10-20251127-154500"
        echo "  {vm}-snap-{n}       → emb-w10-snap-1"
        echo "  backup-{vm}-{date}  → backup-emb-w10-20251127"
        echo
        local new_template
        new_template=$(gum input --placeholder "Enter template" --value "$SNAPSHOT_NAME_TEMPLATE")
        if [[ -n "$new_template" ]]; then
          SNAPSHOT_NAME_TEMPLATE="$new_template"
          save_settings
          gum style --foreground 2 "✓ Template set to: $SNAPSHOT_NAME_TEMPLATE"
          sleep 1
        fi
        ;;
      "Snapshot Limit"*)
        echo
        gum style --foreground 8 "Set maximum snapshots per VM (oldest auto-deleted when exceeded)"
        gum style --foreground 8 "Set to 0 for unlimited snapshots"
        local new_limit
        new_limit=$(gum input --placeholder "Enter limit (0-100)" --value "$SNAPSHOT_LIMIT")
        if [[ "$new_limit" =~ ^[0-9]+$ ]] && (( new_limit >= 0 && new_limit <= 100 )); then
          SNAPSHOT_LIMIT="$new_limit"
          save_settings
          if [[ "$new_limit" == "0" ]]; then
            gum style --foreground 2 "✓ Snapshot limit: unlimited"
          else
            gum style --foreground 2 "✓ Snapshot limit set to $SNAPSHOT_LIMIT per VM"
          fi
          sleep 1
        else
          gum style --foreground 1 "Invalid value. Must be 0-100."
          sleep 1
        fi
        ;;
      "← Back to Main Menu")
        return
        ;;
    esac
  done
}

prompt_orphan_cleanup() {
  local images_dir="/var/lib/libvirt/images"
  local -a all_images=()
  local -a used_images=()
  local -a orphaned_images=()

  # Get all disk images in the directory
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == *.qcow2 ]] && all_images+=("$line")
  done < <(sudo ls "$images_dir" 2>/dev/null || true)

  if [ ${#all_images[@]} -eq 0 ]; then
    gum style --foreground 2 "✓ No disk images found in $images_dir."
    return
  fi

  # Get all disk images currently used by VMs (both session and system)
  gum style --foreground 8 "Scanning VMs for disk usage..."
  
  # Session VMs
  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    while IFS= read -r disk; do
      [[ -z "$disk" || "$disk" == "-" ]] && continue
      local basename_disk
      basename_disk=$(basename "$disk" 2>/dev/null)
      used_images+=("$basename_disk")
    done < <(virsh -c "$SESSION_URI" domblklist "$vm" 2>/dev/null | awk 'NR>2 && $2 ~ /\.qcow2$/ {print $2}')
  done < <(virsh -c "$SESSION_URI" list --all --name 2>/dev/null | sed '/^$/d')
  
  # System VMs
  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    while IFS= read -r disk; do
      [[ -z "$disk" || "$disk" == "-" ]] && continue
      local basename_disk
      basename_disk=$(basename "$disk" 2>/dev/null)
      used_images+=("$basename_disk")
    done < <(sudo virsh -c "$SYSTEM_URI" domblklist "$vm" 2>/dev/null | awk 'NR>2 && $2 ~ /\.qcow2$/ {print $2}')
  done < <(sudo virsh -c "$SYSTEM_URI" list --all --name 2>/dev/null | sed '/^$/d')

  # Find orphaned images (in directory but not used by any VM)
  for img in "${all_images[@]}"; do
    local is_used=false
    for used in "${used_images[@]}"; do
      if [[ "$img" == "$used" ]]; then
        is_used=true
        break
      fi
    done
    if [[ "$is_used" == false ]]; then
      orphaned_images+=("$img")
    fi
  done

  # Display results
  echo
  gum style --bold "Disk Images in $images_dir:"
  for img in "${all_images[@]}"; do
    local status_icon="🟢"
    local status_text="in use"
    local is_orphan=false
    for orphan in "${orphaned_images[@]}"; do
      if [[ "$img" == "$orphan" ]]; then
        status_icon="🔴"
        status_text="ORPHANED"
        is_orphan=true
        break
      fi
    done
    if [[ "$is_orphan" == true ]]; then
      gum style --foreground 1 "  $status_icon $img ($status_text)"
    else
      gum style --foreground 2 "  $status_icon $img ($status_text)"
    fi
  done
  echo

  if [ ${#orphaned_images[@]} -eq 0 ]; then
    gum style --foreground 2 "✓ No orphaned disk images found. All images are in use."
    return
  fi

  gum style --foreground 3 --bold "⚠ Found ${#orphaned_images[@]} orphaned image(s):"
  for orphan in "${orphaned_images[@]}"; do
    local size
    size=$(sudo du -h "$images_dir/$orphan" 2>/dev/null | cut -f1)
    gum style --foreground 1 "  • $orphan ($size)"
  done
  echo

  gum style --foreground 1 --bold "⚠ WARNING: Deleting these files is PERMANENT!"
  gum style --foreground 1 "   You will NOT be able to recover them!"
  echo

  if ! gum confirm "Delete orphaned disk images?" --default=false; then
    gum style --foreground 2 "Leaving disk images untouched."
    return
  fi

  # Second confirmation
  if ! gum confirm "Are you ABSOLUTELY sure? This cannot be undone!" --default=false; then
    gum style --foreground 2 "Aborted. No files deleted."
    return
  fi

  # Delete orphaned images
  for orphan in "${orphaned_images[@]}"; do
    gum style --foreground 3 "Deleting $orphan..."
    if sudo rm -f "$images_dir/$orphan"; then
      gum style --foreground 2 "  ✓ Deleted $orphan"
    else
      gum style --foreground 1 "  ✗ Failed to delete $orphan"
    fi
  done
  
  echo
  gum style --foreground 2 "✓ Orphan cleanup complete."
}

#####################################################################
# Snapshot Functions
#####################################################################

# Generate snapshot name from template
generate_snapshot_name() {
  local vm="$1"
  local template="$SNAPSHOT_NAME_TEMPLATE"
  local date_str=$(date +%Y%m%d)
  local time_str=$(date +%H%M%S)
  
  # Get next sequential number
  local snap_count
  snap_count=$(sudo virsh snapshot-list "$vm" --name 2>/dev/null | wc -l) || snap_count=0
  local next_n=$((snap_count + 1))
  
  # Replace placeholders
  local name="$template"
  name="${name//\{vm\}/$vm}"
  name="${name//\{date\}/$date_str}"
  name="${name//\{time\}/$time_str}"
  name="${name//\{n\}/$next_n}"
  
  echo "$name"
}

# Enforce snapshot limit by deleting oldest
enforce_snapshot_limit() {
  local vm="$1"
  local conn_uri="$2"
  
  [[ "$SNAPSHOT_LIMIT" -eq 0 ]] && return 0  # Unlimited
  
  local snap_count
  snap_count=$(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | wc -l) || snap_count=0
  
  while (( snap_count >= SNAPSHOT_LIMIT )); do
    # Get oldest snapshot
    local oldest
    oldest=$(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | head -1)
    if [[ -n "$oldest" ]]; then
      gum style --foreground 3 "Snapshot limit reached. Deleting oldest: $oldest"
      sudo virsh -c "$conn_uri" snapshot-delete "$vm" "$oldest" 2>/dev/null || true
      snap_count=$((snap_count - 1))
    else
      break
    fi
  done
}

# Create a snapshot
create_snapshot() {
  local vm="$1"
  local conn_uri="$2"
  local snap_type="$3"  # live, disk-only, shutdown, force-shutdown
  local snap_name="$4"
  local snap_desc="${5:-}"
  
  # Enforce limit before creating
  enforce_snapshot_limit "$vm" "$conn_uri"
  
  local vm_state
  vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  
  case "$snap_type" in
    "live")
      if [[ "$vm_state" != "running" ]]; then
        gum style --foreground 1 "✗ VM must be running for live snapshot"
        return 1
      fi
      gum style --foreground 8 "Creating live snapshot (with memory state)..."
      if [[ -n "$snap_desc" ]]; then
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --description "$snap_desc" --atomic 2>&1
      else
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --atomic 2>&1
      fi
      ;;
    "disk-only")
      gum style --foreground 8 "Creating disk-only snapshot..."
      if [[ -n "$snap_desc" ]]; then
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --description "$snap_desc" --disk-only --atomic 2>&1
      else
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --disk-only --atomic 2>&1
      fi
      ;;
    "shutdown")
      if [[ "$vm_state" == "running" ]]; then
        gum style --foreground 8 "Gracefully shutting down VM..."
        sudo virsh -c "$conn_uri" shutdown "$vm" 2>/dev/null || true
        for i in {1..60}; do
          sleep 1
          vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
          [[ "$vm_state" == "shut off" ]] && break
        done
        if [[ "$vm_state" != "shut off" ]]; then
          gum style --foreground 1 "✗ VM did not shut down in time"
          return 1
        fi
      fi
      gum style --foreground 8 "Creating snapshot of shut off VM..."
      if [[ -n "$snap_desc" ]]; then
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --description "$snap_desc" --atomic 2>&1
      else
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --atomic 2>&1
      fi
      ;;
    "force-shutdown")
      if [[ "$vm_state" == "running" || "$vm_state" == "paused" ]]; then
        gum style --foreground 3 "Force stopping VM..."
        sudo virsh -c "$conn_uri" destroy "$vm" 2>/dev/null || true
        sleep 2
      fi
      gum style --foreground 8 "Creating snapshot..."
      if [[ -n "$snap_desc" ]]; then
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --description "$snap_desc" --atomic 2>&1
      else
        sudo virsh -c "$conn_uri" snapshot-create-as "$vm" "$snap_name" --atomic 2>&1
      fi
      ;;
  esac
}

# Get snapshot tree/list for a VM
get_snapshot_list() {
  local vm="$1"
  local conn_uri="$2"
  
  sudo virsh -c "$conn_uri" snapshot-list "$vm" --tree 2>/dev/null || \
  sudo virsh -c "$conn_uri" snapshot-list "$vm" 2>/dev/null || \
  echo "No snapshots"
}

# Get snapshot info with size
get_snapshot_info() {
  local vm="$1"
  local conn_uri="$2"
  local snap_name="$3"
  
  # Get basic snapshot info
  sudo virsh -c "$conn_uri" snapshot-info "$vm" "$snap_name" 2>/dev/null
  
  # Try to get snapshot size from XML
  echo
  gum style --bold "Snapshot Size:"
  local snap_xml
  snap_xml=$(sudo virsh -c "$conn_uri" snapshot-dumpxml "$vm" "$snap_name" 2>/dev/null)
  
  # Check if it's an internal snapshot (stored in qcow2)
  local snap_type
  snap_type=$(echo "$snap_xml" | grep -oP '<state>\K[^<]+' || echo "unknown")
  
  if [[ "$snap_type" == "disk-snapshot" ]]; then
    # External snapshot - find the overlay files
    local overlay_files
    overlay_files=$(echo "$snap_xml" | grep -oP "source file='\K[^']+")
    local total_size=0
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      if sudo test -f "$file"; then
        local fsize
        fsize=$(sudo du -h "$file" 2>/dev/null | cut -f1)
        echo "  Overlay: $(basename "$file") ($fsize)"
      fi
    done <<< "$overlay_files"
  else
    # Internal snapshot - size is within the qcow2 file
    # Get the disk path from VM
    local disk_path
    disk_path=$(sudo virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null | awk 'NR>2 && $2 ~ /\.qcow2$/ {print $2; exit}')
    if [[ -n "$disk_path" ]] && sudo test -f "$disk_path"; then
      # Use qemu-img to check snapshot info
      local snap_info
      snap_info=$(sudo qemu-img snapshot -l "$disk_path" 2>/dev/null | grep "$snap_name" || echo "")
      if [[ -n "$snap_info" ]]; then
        local snap_size
        snap_size=$(echo "$snap_info" | awk '{print $4}')
        echo "  Internal snapshot size: $snap_size"
      else
        echo "  (Internal snapshot - size included in qcow2 file)"
      fi
    fi
  fi
}

# Revert to snapshot
revert_snapshot() {
  local vm="$1"
  local conn_uri="$2"
  local snap_name="$3"
  local force_off="${4:-false}"
  
  local vm_state
  vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  
  if [[ "$vm_state" == "running" && "$force_off" == "true" ]]; then
    gum style --foreground 3 "Force stopping VM before revert..."
    sudo virsh -c "$conn_uri" destroy "$vm" 2>/dev/null || true
    sleep 2
  elif [[ "$vm_state" == "running" ]]; then
    gum style --foreground 8 "Gracefully shutting down VM..."
    sudo virsh -c "$conn_uri" shutdown "$vm" 2>/dev/null || true
    for i in {1..60}; do
      sleep 1
      vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
      [[ "$vm_state" == "shut off" ]] && break
    done
  fi
  
  gum style --foreground 8 "Reverting to snapshot: $snap_name..."
  sudo virsh -c "$conn_uri" snapshot-revert "$vm" "$snap_name" 2>&1
}

# Delete snapshot
delete_snapshot() {
  local vm="$1"
  local conn_uri="$2"
  local snap_name="$3"
  
  gum style --foreground 8 "Deleting snapshot: $snap_name..."
  sudo virsh -c "$conn_uri" snapshot-delete "$vm" "$snap_name" 2>&1
}

# Quick snapshot (for VM actions menu)
quick_snapshot() {
  local vm="$1"
  local conn_uri="$2"
  
  local snap_name
  snap_name=$(generate_snapshot_name "$vm")
  
  local vm_state
  vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  
  gum style --foreground 212 "📸 Quick Snapshot: $vm"
  echo
  gum style --foreground 8 "Snapshot name: $snap_name"
  gum style --foreground 8 "VM state: $vm_state"
  echo
  
  local snap_type="disk-only"
  if [[ "$vm_state" == "running" ]]; then
    if gum confirm "Create live snapshot (with memory state)?" --default=true; then
      snap_type="live"
    fi
  fi
  
  local description=""
  if gum confirm "Add description?" --default=false; then
    description=$(gum input --placeholder "Enter snapshot description")
  fi
  
  echo
  if create_snapshot "$vm" "$conn_uri" "$snap_type" "$snap_name" "$description"; then
    gum style --foreground 2 "✓ Snapshot created: $snap_name"
  else
    gum style --foreground 1 "✗ Failed to create snapshot"
  fi
}

# Snapshot Manager main function
snapshot_manager() {
  while true; do
    clear
    gum style --bold --foreground 212 "═══ 📸 Snapshot Manager ═══"
    echo
    
    # Build VM list with snapshot counts
    local vm_list=()
    local vm_uris=()
    
    # System VMs
    while IFS= read -r vm; do
      [[ -z "$vm" ]] && continue
      local snap_count
      snap_count=$(sudo virsh -c "$SYSTEM_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | wc -l) || snap_count=0
      vm_list+=("$vm [system] ($snap_count snapshots)")
      vm_uris+=("$SYSTEM_URI")
    done < <(sudo virsh -c "$SYSTEM_URI" list --all --name 2>/dev/null | sed '/^$/d')
    
    # Session VMs
    while IFS= read -r vm; do
      [[ -z "$vm" ]] && continue
      local snap_count
      snap_count=$(virsh -c "$SESSION_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | wc -l) || snap_count=0
      vm_list+=("$vm [session] ($snap_count snapshots)")
      vm_uris+=("$SESSION_URI")
    done < <(virsh -c "$SESSION_URI" list --all --name 2>/dev/null | sed '/^$/d')
    
    if [[ ${#vm_list[@]} -eq 0 ]]; then
      gum style --foreground 3 "No VMs found."
      read -p "Press Enter to continue..."
      return
    fi
    
    vm_list+=("← Back to Main Menu")
    
    local selection
    selection=$(gum choose --header="Select VM to manage snapshots:" "${vm_list[@]}" || echo "← Back to Main Menu")
    
    if [[ "$selection" == "← Back to Main Menu" ]]; then
      return
    fi
    
    # Parse selection
    local selected_vm
    selected_vm=$(echo "$selection" | awk '{print $1}')
    local selected_label
    selected_label=$(echo "$selection" | grep -oP '\[\K[^\]]+')
    local conn_uri="$SYSTEM_URI"
    [[ "$selected_label" == "session" ]] && conn_uri="$SESSION_URI"
    
    # VM Snapshot submenu
    manage_vm_snapshots "$selected_vm" "$conn_uri"
  done
}

# Manage snapshots for a specific VM
manage_vm_snapshots() {
  local vm="$1"
  local conn_uri="$2"
  
  while true; do
    clear
    gum style --bold --foreground 212 "═══ Snapshots: $vm ═══"
    echo
    
    local vm_state
    vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
    gum style --foreground 8 "VM State: $vm_state"
    echo
    
    # Show snapshot tree
    gum style --bold --foreground 51 "Snapshot Tree:"
    local tree_output
    tree_output=$(get_snapshot_list "$vm" "$conn_uri") || tree_output=""
    if [[ -z "$tree_output" || "$tree_output" == "No snapshots" || "$tree_output" =~ ^[[:space:]]*$ ]]; then
      gum style --foreground 3 "  No snapshots found"
    else
      echo "$tree_output" | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  $line"
      done
    fi
    echo
    
    # Check if snapshots exist for restore/delete options
    local snap_names
    snap_names=$(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$') || snap_names=""
    
    local action
    if [[ -n "$snap_names" ]]; then
      action=$(gum choose --header="Select action:" \
        "📸 Create Snapshot" \
        "⏪ Restore Snapshot" \
        "🗑️  Delete Snapshot" \
        "ℹ️  Snapshot Info" \
        "← Back to VM List" \
        || echo "← Back to VM List")
    else
      action=$(gum choose --header="Select action:" \
        "📸 Create Snapshot" \
        "← Back to VM List" \
        || echo "← Back to VM List")
    fi
    
    case "$action" in
      "📸 Create Snapshot")
        create_snapshot_menu "$vm" "$conn_uri"
        ;;
      "⏪ Restore Snapshot")
        restore_snapshot_menu "$vm" "$conn_uri"
        ;;
      "🗑️  Delete Snapshot")
        delete_snapshot_menu "$vm" "$conn_uri"
        ;;
      "ℹ️  Snapshot Info")
        snapshot_info_menu "$vm" "$conn_uri"
        ;;
      "← Back to VM List")
        return
        ;;
    esac
  done
}

# Create snapshot menu
create_snapshot_menu() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Create Snapshot: $vm ═══"
  echo
  
  local vm_state
  vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  gum style --foreground 8 "VM State: $vm_state"
  echo
  
  # Snapshot type selection
  local type_options=()
  if [[ "$vm_state" == "running" ]]; then
    type_options+=("Live Snapshot (with memory) - VM stays running")
  fi
  type_options+=("Disk-only Snapshot - faster, no memory state")
  if [[ "$vm_state" == "running" ]]; then
    type_options+=("Graceful Shutdown + Snapshot - cleanest state")
    type_options+=("Force Stop + Snapshot - immediate, may lose data")
  fi
  type_options+=("Cancel")
  
  local type_choice
  type_choice=$(gum choose --header="Select snapshot type:" "${type_options[@]}" || echo "Cancel")
  
  [[ "$type_choice" == "Cancel" ]] && return
  
  local snap_type
  case "$type_choice" in
    "Live Snapshot"*) snap_type="live" ;;
    "Disk-only"*) snap_type="disk-only" ;;
    "Graceful Shutdown"*) snap_type="shutdown" ;;
    "Force Stop"*) snap_type="force-shutdown" ;;
    *) return ;;
  esac
  
  # Snapshot name
  local default_name
  default_name=$(generate_snapshot_name "$vm")
  
  echo
  gum style --foreground 8 "Snapshot name (leave empty for default):"
  local snap_name
  snap_name=$(gum input --placeholder "$default_name" --value "")
  [[ -z "$snap_name" ]] && snap_name="$default_name"
  
  # Description
  local description=""
  echo
  if gum confirm "Add description/comment?" --default=false; then
    description=$(gum input --placeholder "Enter description")
  fi
  
  # Confirm
  echo
  gum style --foreground 212 "Summary:"
  echo "  VM: $vm"
  echo "  Type: $snap_type"
  echo "  Name: $snap_name"
  [[ -n "$description" ]] && echo "  Description: $description"
  echo
  
  if ! gum confirm "Create snapshot?" --default=true; then
    gum style --foreground 3 "Cancelled."
    read -p "Press Enter to continue..."
    return
  fi
  
  echo
  if create_snapshot "$vm" "$conn_uri" "$snap_type" "$snap_name" "$description"; then
    gum style --foreground 2 "✓ Snapshot created successfully: $snap_name"
  else
    gum style --foreground 1 "✗ Failed to create snapshot"
  fi
  
  read -p "Press Enter to continue..."
}

# Restore snapshot menu
restore_snapshot_menu() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Restore Snapshot: $vm ═══"
  echo
  
  # Get snapshots with details
  local snap_list=()
  while IFS= read -r snap_name; do
    [[ -z "$snap_name" ]] && continue
    local snap_time
    snap_time=$(sudo virsh -c "$conn_uri" snapshot-info "$vm" "$snap_name" 2>/dev/null | grep "Creation Time" | cut -d: -f2- | xargs)
    local snap_desc
    snap_desc=$(sudo virsh -c "$conn_uri" snapshot-dumpxml "$vm" "$snap_name" 2>/dev/null | grep -oP '<description>\K[^<]+' || echo "")
    
    local display="$snap_name"
    [[ -n "$snap_time" ]] && display="$display ($snap_time)"
    [[ -n "$snap_desc" ]] && display="$display - $snap_desc"
    snap_list+=("$display")
  done < <(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$')
  
  if [[ ${#snap_list[@]} -eq 0 ]]; then
    gum style --foreground 3 "No snapshots found."
    read -p "Press Enter to continue..."
    return
  fi
  
  snap_list+=("Cancel")
  
  local selection
  selection=$(gum choose --header="Select snapshot to restore:" "${snap_list[@]}" || echo "Cancel")
  
  [[ "$selection" == "Cancel" ]] && return
  
  local snap_name
  snap_name=$(echo "$selection" | awk '{print $1}')
  
  echo
  gum style --foreground 1 --bold "⚠ WARNING: Restoring will revert the VM to this snapshot state!"
  gum style --foreground 1 "   All changes since this snapshot will be LOST!"
  echo
  
  local vm_state
  vm_state=$(sudo virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  
  local restore_method="graceful"
  if [[ "$vm_state" == "running" ]]; then
    echo
    gum style --foreground 3 "VM is currently running."
    local method_choice
    method_choice=$(gum choose --header="How to stop VM before restore?" \
      "Graceful shutdown (safer)" \
      "Force stop (immediate)" \
      "Cancel" \
      || echo "Cancel")
    
    case "$method_choice" in
      "Graceful"*) restore_method="graceful" ;;
      "Force"*) restore_method="force" ;;
      *) return ;;
    esac
  fi
  
  if ! gum confirm "Restore to '$snap_name'?" --default=false; then
    gum style --foreground 3 "Cancelled."
    read -p "Press Enter to continue..."
    return
  fi
  
  echo
  local force_off="false"
  [[ "$restore_method" == "force" ]] && force_off="true"
  
  if revert_snapshot "$vm" "$conn_uri" "$snap_name" "$force_off"; then
    gum style --foreground 2 "✓ Restored to snapshot: $snap_name"
  else
    gum style --foreground 1 "✗ Failed to restore snapshot"
  fi
  
  read -p "Press Enter to continue..."
}

# Delete snapshot menu
delete_snapshot_menu() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Delete Snapshot: $vm ═══"
  echo
  
  # Get snapshots
  local snap_list=()
  while IFS= read -r snap_name; do
    [[ -z "$snap_name" ]] && continue
    local snap_time
    snap_time=$(sudo virsh -c "$conn_uri" snapshot-info "$vm" "$snap_name" 2>/dev/null | grep "Creation Time" | cut -d: -f2- | xargs)
    
    local display="$snap_name"
    [[ -n "$snap_time" ]] && display="$display ($snap_time)"
    snap_list+=("$display")
  done < <(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$')
  
  if [[ ${#snap_list[@]} -eq 0 ]]; then
    gum style --foreground 3 "No snapshots found."
    read -p "Press Enter to continue..."
    return
  fi
  
  snap_list+=("Cancel")
  
  local selection
  selection=$(gum choose --header="Select snapshot to delete:" "${snap_list[@]}" || echo "Cancel")
  
  [[ "$selection" == "Cancel" ]] && return
  
  local snap_name
  snap_name=$(echo "$selection" | awk '{print $1}')
  
  echo
  gum style --foreground 1 --bold "⚠ WARNING: This will permanently delete snapshot '$snap_name'!"
  echo
  
  if ! gum confirm "Delete snapshot '$snap_name'?" --default=false; then
    gum style --foreground 3 "Cancelled."
    read -p "Press Enter to continue..."
    return
  fi
  
  if ! gum confirm "Are you ABSOLUTELY sure?" --default=false; then
    gum style --foreground 3 "Cancelled."
    read -p "Press Enter to continue..."
    return
  fi
  
  echo
  if delete_snapshot "$vm" "$conn_uri" "$snap_name"; then
    gum style --foreground 2 "✓ Snapshot deleted: $snap_name"
  else
    gum style --foreground 1 "✗ Failed to delete snapshot"
  fi
  
  read -p "Press Enter to continue..."
}

# Snapshot info menu
snapshot_info_menu() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Snapshot Info: $vm ═══"
  echo
  
  # Get snapshots
  local snap_list=()
  while IFS= read -r snap_name; do
    [[ -z "$snap_name" ]] && continue
    snap_list+=("$snap_name")
  done < <(sudo virsh -c "$conn_uri" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$')
  
  if [[ ${#snap_list[@]} -eq 0 ]]; then
    gum style --foreground 3 "No snapshots found."
    read -p "Press Enter to continue..."
    return
  fi
  
  snap_list+=("Cancel")
  
  local selection
  selection=$(gum choose --header="Select snapshot to view:" "${snap_list[@]}" || echo "Cancel")
  
  [[ "$selection" == "Cancel" ]] && return
  
  echo
  gum style --bold --foreground 51 "Snapshot Details: $selection"
  echo
  get_snapshot_info "$vm" "$conn_uri" "$selection"
  
  echo
  read -p "Press Enter to continue..."
}

append_vms() {
  local uri="$1"
  local label="$2"
  local vm

  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    local key="${uri}|${vm}"
    if [[ -n "${VM_SEEN[$key]:-}" ]]; then
      continue
    fi
    VM_SEEN["$key"]=1
    local state
    state=$(virsh -c "$uri" domstate "$vm" 2>/dev/null || echo "unknown")
    VM_NAMES+=("$vm")
    VM_URIS+=("$uri")
    VM_LABELS+=("$label")
    VM_STATES+=("$state")
  done < <(virsh -c "$uri" list --all --name 2>/dev/null | sed '/^$/d' || true)
}

run_diagnostics() {
  gum style --bold --foreground 212 "═══ Diagnostics ═══"
  
  echo
  gum style --bold "Session Connection ($SESSION_URI):"
  virsh -c "$SESSION_URI" list --all || true

  echo
  gum style --bold "System Connection ($SYSTEM_URI):"
  sudo virsh -c "$SYSTEM_URI" list --all || true

  echo
  gum style --bold "/etc/libvirt/qemu contents:"
  sudo ls /etc/libvirt/qemu || true

  echo
  gum style --bold "Disk Images Storage ($DISK_DIR):"
  if sudo test -d "$DISK_DIR"; then
    local total_disk_size
    total_disk_size=$(sudo du -sh "$DISK_DIR" 2>/dev/null | cut -f1) || total_disk_size="unknown"
    gum style --foreground 8 "Total size: $total_disk_size"
    echo
    # List each qcow2 with size
    while IFS= read -r img; do
      [[ -z "$img" ]] && continue
      local img_size
      img_size=$(sudo du -h "$DISK_DIR/$img" 2>/dev/null | cut -f1) || img_size="?"
      local img_virtual
      img_virtual=$(sudo qemu-img info "$DISK_DIR/$img" 2>/dev/null | grep "virtual size" | awk -F'[()]' '{print $2}') || img_virtual=""
      if [[ -n "$img_virtual" ]]; then
        echo "  $img: $img_size (virtual: $img_virtual)"
      else
        echo "  $img: $img_size"
      fi
    done < <(sudo ls "$DISK_DIR" 2>/dev/null | grep -E '\.qcow2$')
  else
    gum style --foreground 3 "Directory not found"
  fi

  echo
  gum style --bold "Snapshot Summary:"
  local total_snapshots=0
  local vms_with_snapshots=0
  
  # System VMs
  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    local snap_count
    snap_count=$(sudo virsh -c "$SYSTEM_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | wc -l) || snap_count=0
    if [[ $snap_count -gt 0 ]]; then
      vms_with_snapshots=$((vms_with_snapshots + 1))
      total_snapshots=$((total_snapshots + snap_count))
      
      # Get snapshot details
      gum style --foreground 51 "  $vm [system]: $snap_count snapshot(s)"
      while IFS= read -r snap_name; do
        [[ -z "$snap_name" ]] && continue
        local snap_time
        snap_time=$(sudo virsh -c "$SYSTEM_URI" snapshot-info "$vm" "$snap_name" 2>/dev/null | grep "Creation Time" | cut -d: -f2- | xargs) || snap_time=""
        
        # Try to get snapshot size from qemu-img
        local disk_path
        disk_path=$(sudo virsh -c "$SYSTEM_URI" domblklist "$vm" 2>/dev/null | awk 'NR>2 && $2 ~ /\.qcow2$/ {print $2; exit}')
        local snap_size=""
        if [[ -n "$disk_path" ]] && sudo test -f "$disk_path"; then
          snap_size=$(sudo qemu-img snapshot -l "$disk_path" 2>/dev/null | grep "$snap_name" | awk '{print $4}') || snap_size=""
        fi
        
        if [[ -n "$snap_size" ]]; then
          echo "    • $snap_name ($snap_time) - $snap_size"
        else
          echo "    • $snap_name ($snap_time)"
        fi
      done < <(sudo virsh -c "$SYSTEM_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$')
    fi
  done < <(sudo virsh -c "$SYSTEM_URI" list --all --name 2>/dev/null | sed '/^$/d')
  
  # Session VMs
  while IFS= read -r vm; do
    [[ -z "$vm" ]] && continue
    local snap_count
    snap_count=$(virsh -c "$SESSION_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$' | wc -l) || snap_count=0
    if [[ $snap_count -gt 0 ]]; then
      vms_with_snapshots=$((vms_with_snapshots + 1))
      total_snapshots=$((total_snapshots + snap_count))
      
      gum style --foreground 51 "  $vm [session]: $snap_count snapshot(s)"
      while IFS= read -r snap_name; do
        [[ -z "$snap_name" ]] && continue
        local snap_time
        snap_time=$(virsh -c "$SESSION_URI" snapshot-info "$vm" "$snap_name" 2>/dev/null | grep "Creation Time" | cut -d: -f2- | xargs) || snap_time=""
        echo "    • $snap_name ($snap_time)"
      done < <(virsh -c "$SESSION_URI" snapshot-list "$vm" --name 2>/dev/null | grep -v '^$')
    fi
  done < <(virsh -c "$SESSION_URI" list --all --name 2>/dev/null | sed '/^$/d')
  
  if [[ $total_snapshots -eq 0 ]]; then
    gum style --foreground 8 "  No snapshots found on any VM"
  else
    echo
    gum style --foreground 2 "  Total: $total_snapshots snapshot(s) across $vms_with_snapshots VM(s)"
  fi

  echo
  gum style --bold "Orphaned Disk Check:"
  prompt_orphan_cleanup
}

show_vm_info() {
  vm_name="$1"
  conn_uri="$2"
  
  gum style --bold --foreground 212 "═══ VM Information: $vm_name ═══"
  echo
  
  # Parse dominfo for human-readable specs
  dominfo=$(virsh -c "$conn_uri" dominfo "$vm_name" 2>/dev/null || echo "")
  
  id_val=$(echo "$dominfo" | awk '/^Id:/ {print $2}')
  name_val=$(echo "$dominfo" | awk '/^Name:/ {print $2}')
  uuid_val=$(echo "$dominfo" | awk '/^UUID:/ {print $2}')
  state_val=$(echo "$dominfo" | awk '/^State:/ {print $2}')
  cpus_val=$(echo "$dominfo" | awk '/^CPU\(s\):/ {print $2}')
  max_mem_val=$(echo "$dominfo" | awk '/^Max memory:/ {print $3, $4}')
  used_mem_val=$(echo "$dominfo" | awk '/^Used memory:/ {print $3, $4}')
  
  # Get disk info from domstats
  domstats=$(virsh -c "$conn_uri" domstats "$vm_name" --block 2>/dev/null || echo "")
  
  disk_path_val=$(echo "$domstats" | awk '/block\.0\.path=/ {sub(/.*=/, ""); print}')
  disk_capacity_val=$(echo "$domstats" | awk '/block\.0\.capacity=/ {sub(/.*=/, ""); print}')
  disk_allocation_val=$(echo "$domstats" | awk '/block\.0\.allocation=/ {sub(/.*=/, ""); print}')
  
  # Convert bytes to GB
  if [[ -n "$disk_capacity_val" ]]; then
    disk_capacity_val=$(awk "BEGIN {printf \"%.1f GB\", $disk_capacity_val/1024/1024/1024}")
  fi
  if [[ -n "$disk_allocation_val" ]]; then
    disk_allocation_val=$(awk "BEGIN {printf \"%.1f GB\", $disk_allocation_val/1024/1024/1024}")
  fi
  
  # Display formatted info
  gum style --border rounded --padding "0 1" --margin "1 0" \
    "Name:       $name_val" \
    "State:      $state_val" \
    "vCPUs:      $cpus_val" \
    "Max Memory: $max_mem_val" \
    "Used Mem:   $used_mem_val" \
    "Disk Path:  ${disk_path_val:-N/A}" \
    "Disk Size:  ${disk_capacity_val:-N/A}" \
    "Allocated:  ${disk_allocation_val:-N/A}"
  
  echo
  gum style --italic --foreground 8 "Note: Uptime tracking requires guest agent; use 'virsh domtime' if qemu-guest-agent is installed."
}

clone_vm() {
  source_vm="$1"
  conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Clone VM: $source_vm ═══"
  echo
  
  # Check if VM is running
  vm_state=$(virsh -c "$conn_uri" domstate "$source_vm" 2>/dev/null || echo "unknown")
  
  if [[ "$vm_state" == "running" || "$vm_state" == "paused" ]]; then
    gum style --foreground 3 "⚠️  VM must be shut off to clone."
    if gum confirm "Gracefully shutdown $source_vm now?"; then
      gum spin --spinner dot --title "Shutting down $source_vm..." -- virsh -c "$conn_uri" shutdown "$source_vm"
      gum style --foreground 2 "Waiting for VM to shut down..."
      
      # Wait up to 60 seconds for shutdown
      for i in {1..60}; do
        sleep 1
        vm_state=$(virsh -c "$conn_uri" domstate "$source_vm" 2>/dev/null || echo "unknown")
        if [[ "$vm_state" == "shut off" ]]; then
          break
        fi
      done
      
      if [[ "$vm_state" != "shut off" ]]; then
        gum style --foreground 1 "✗ VM did not shut down in time. Clone aborted."
        read -p "Press Enter to continue..."
        return
      fi
    else
      gum style --foreground 1 "Clone aborted."
      read -p "Press Enter to continue..."
      return
    fi
  fi
  
  # Get new VM name
  new_vm_name=$(gum input --placeholder "Enter new VM name" --prompt "New VM name: ")
  if [[ -z "$new_vm_name" ]]; then
    gum style --foreground 1 "✗ No name provided. Clone aborted."
    read -p "Press Enter to continue..."
    return
  fi
  
  # Check if name already exists
  if virsh -c "$conn_uri" dominfo "$new_vm_name" &>/dev/null; then
    gum style --foreground 1 "✗ VM '$new_vm_name' already exists. Clone aborted."
    read -p "Press Enter to continue..."
    return
  fi
  
  # Get source disk info
  source_disk=$(virsh -c "$conn_uri" domblklist "$source_vm" | awk 'NR>2 && $2 ~ /\.qcow2$/ {print $2; exit}')
  
  if [[ -z "$source_disk" ]]; then
    gum style --foreground 1 "✗ Could not find source disk. Clone aborted."
    read -p "Press Enter to continue..."
    return
  fi
  
  source_disk_size_bytes=$(sudo qemu-img info "$source_disk" 2>/dev/null | awk '/virtual size:/ {print $5}' | tr -d '()')
  if [[ -z "$source_disk_size_bytes" ]]; then
    source_disk_size_bytes=$(sudo qemu-img info "$source_disk" 2>/dev/null | grep -oP 'virtual size:.*\(\K[0-9]+' || echo "0")
  fi
  source_disk_size_gb=$(awk "BEGIN {printf \"%.0f\", $source_disk_size_bytes/1024/1024/1024}")
  
  gum style --foreground 8 "Source disk: $source_disk ($source_disk_size_gb GB)"
  echo
  
  # Ask if user wants to customize clone options
  expand_disk=false
  expand_size=""
  add_extra_disk=false
  extra_disk_size=""
  
  if gum confirm "Customize clone? (disk size, extra disk, etc.)" --default=false; then
    echo
    # Ask about disk expansion
    if gum confirm "Expand primary disk size?" --default=false; then
      new_disk_size=$(gum input --placeholder "Enter new size in GB (current: ${source_disk_size_gb}GB)" --prompt "New disk size (GB): ")
      if [[ -n "$new_disk_size" ]] && [[ "$new_disk_size" =~ ^[0-9]+$ ]] && (( new_disk_size > source_disk_size_gb )); then
        expand_disk=true
        expand_size="${new_disk_size}G"
      else
        gum style --foreground 3 "⚠️  Invalid size or smaller than source. Keeping original size."
      fi
    fi
    
    # Ask about additional disk
    if gum confirm "Add an additional disk?" --default=false; then
      extra_disk_size=$(gum input --placeholder "Enter size in GB" --prompt "Extra disk size (GB): ")
      if [[ -n "$extra_disk_size" ]] && [[ "$extra_disk_size" =~ ^[0-9]+$ ]]; then
        add_extra_disk=true
      else
        gum style --foreground 3 "⚠️  Invalid size. Skipping extra disk."
      fi
    fi
  fi
  
  # Handle CD-ROM ISOs
  cdrom_devices=$(virsh -c "$conn_uri" domblklist "$source_vm" 2>/dev/null | awk 'NR>2 && $1 ~ /^sd[a-z]$/ && $2 ~ /\.iso$/ {print $1 ":" $2}')
  
  # Arrays to track ISO changes (avoid associative array issues)
  iso_change_devs=()
  iso_change_paths=()
  
  if [[ -n "$cdrom_devices" ]]; then
    gum style --foreground 212 "CD-ROM devices found in source VM:"
    echo "$cdrom_devices"
    echo
    
    if gum confirm "Replace CD-ROM ISO(s)?" --default=false; then
      while IFS=: read -r dev_name iso_path; do
        [[ -z "$dev_name" ]] && continue
        gum style --foreground 8 "Current: $dev_name -> $iso_path"
        
        # List available ISOs
        if [[ -d "$ISO_DIR" ]]; then
          iso_files=()
          while IFS= read -r iso_file; do
            iso_files+=("$(basename "$iso_file")")
          done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null)
          
          iso_files+=("Keep current" "Remove ISO")
          
          if [ ${#iso_files[@]} -gt 2 ]; then
            selected_iso=$(gum choose --header="Select ISO for $dev_name:" "${iso_files[@]}" || echo "Keep current")
            
            if [[ "$selected_iso" == "Keep current" ]]; then
              : # Do nothing, keep as is
            elif [[ "$selected_iso" == "Remove ISO" ]]; then
              iso_change_devs+=("$dev_name")
              iso_change_paths+=("")
            else
              iso_change_devs+=("$dev_name")
              iso_change_paths+=("$ISO_DIR/$selected_iso")
            fi
          else
            gum style --foreground 3 "No ISOs found in $ISO_DIR"
          fi
        else
          gum style --foreground 3 "ISO directory $ISO_DIR not found."
        fi
      done <<< "$cdrom_devices"
    fi
  fi
  
  # Perform clone
  echo
  gum style --bold --foreground 212 "Starting clone operation..."
  
  # Use sudo for system VMs
  clone_cmd="sudo virt-clone --connect $conn_uri --original $source_vm --name $new_vm_name --auto-clone"
  
  gum style --foreground 8 "(May require sudo for system VM disks)"
  echo
  
  if gum spin --spinner dot --title "Cloning $source_vm to $new_vm_name..." -- $clone_cmd; then
    gum style --foreground 2 "✓ VM cloned successfully."
    
    # Apply CPU mode optimization
    gum spin --spinner dot --title "Applying CPU optimization ($CPU_MODE)..." -- \
      sudo virt-xml --connect "$conn_uri" "$new_vm_name" --edit --cpu "$CPU_MODE"
    gum style --foreground 2 "✓ CPU mode set to $CPU_MODE."
    
    # Apply disk cache optimization
    new_disk_path="$DISK_DIR/${new_vm_name}.qcow2"
    if sudo test -f "$new_disk_path"; then
      gum spin --spinner dot --title "Setting disk cache mode to $DISK_CACHE..." -- \
        sudo virt-xml --connect "$conn_uri" "$new_vm_name" --edit --disk cache="$DISK_CACHE"
      gum style --foreground 2 "✓ Disk cache set to $DISK_CACHE."
    fi
    
    # Expand disk if requested
    if [[ "$expand_disk" == true ]]; then
      if sudo test -f "$new_disk_path"; then
        gum spin --spinner dot --title "Expanding disk to $expand_size..." -- \
          sudo qemu-img resize "$new_disk_path" "$expand_size"
        gum style --foreground 2 "✓ Disk expanded to $expand_size."
      fi
    fi
    
    # Add extra disk if requested
    if [[ "$add_extra_disk" == true ]]; then
      extra_disk_path="$DISK_DIR/${new_vm_name}-extra.qcow2"
      gum spin --spinner dot --title "Creating additional disk..." -- \
        sudo qemu-img create -f qcow2 "$extra_disk_path" "${extra_disk_size}G"
      
      sudo virsh -c "$conn_uri" attach-disk "$new_vm_name" "$extra_disk_path" vdb \
        --driver qemu --subdriver qcow2 --targetbus virtio --persistent \
        --cache "$DISK_CACHE"
      
      gum style --foreground 2 "✓ Additional disk attached (${extra_disk_size}GB) with cache=$DISK_CACHE."
    fi
    
    # Update CD-ROM ISOs if changed
    if [[ ${#iso_change_devs[@]} -gt 0 ]]; then
      for idx in "${!iso_change_devs[@]}"; do
        dev_name="${iso_change_devs[$idx]}"
        new_iso_path="${iso_change_paths[$idx]}"
        
        if [[ -z "$new_iso_path" ]]; then
          # Remove ISO
          sudo virsh -c "$conn_uri" change-media "$new_vm_name" "$dev_name" --eject --config 2>/dev/null || true
          gum style --foreground 2 "✓ Removed ISO from $dev_name"
        else
          # Update ISO
          sudo virsh -c "$conn_uri" change-media "$new_vm_name" "$dev_name" "$new_iso_path" --config 2>/dev/null || true
          gum style --foreground 2 "✓ Updated $dev_name to $(basename "$new_iso_path")"
        fi
      done
    fi
    
    echo
    gum style --bold --foreground 2 "✓ Clone completed: $new_vm_name"
    
  else
    gum style --foreground 1 "✗ Clone failed. Check error messages above."
  fi
  
  echo
  read -p "Press Enter to continue..."
}

export_vm() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Export Virtual Machine: $vm ═══"
  echo
  
  # Ensure VM is shut off
  local vm_state
  vm_state=$(virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
  if [[ "$vm_state" != "shut off" ]]; then
    gum style --foreground 3 "VM must be shut off before export."
    read -p "Gracefully shutdown $vm now? (y/n) [y]: " shutdown_confirm
    shutdown_confirm=${shutdown_confirm:-y}
    if [[ "${shutdown_confirm,,}" == "y" ]]; then
      echo "Shutting down $vm..."
      virsh -c "$conn_uri" shutdown "$vm" 2>/dev/null || true
      echo "Waiting for VM to shut down (up to 60 seconds)..."
      local i
      for i in {1..60}; do
        sleep 1
        vm_state=$(virsh -c "$conn_uri" domstate "$vm" 2>/dev/null) || vm_state="unknown"
        if [[ "$vm_state" == "shut off" ]]; then
          echo "VM is now shut off."
          break
        fi
        echo -n "."
      done
      echo
      if [[ "$vm_state" != "shut off" ]]; then
        gum style --foreground 1 "✗ VM did not shut down in time. Export aborted."
        read -p "Press Enter to continue..."
        return 0
      fi
    else
      gum style --foreground 1 "Export aborted."
      read -p "Press Enter to continue..."
      return 0
    fi
  fi
  
  # Collect disk info first
  local disk_targets=()
  local disk_sources=()
  local blklist_output
  blklist_output=$(virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null) || blklist_output=""
  
  while IFS= read -r line; do
    local target source
    target=$(echo "$line" | awk '{print $1}')
    source=$(echo "$line" | awk '{print $2}')
    [[ "$target" == "Target" || -z "$target" ]] && continue
    [[ "$source" == "-" || -z "$source" ]] && continue
    # Skip ISOs
    [[ "$source" == *.iso ]] && continue
    disk_targets+=("$target")
    disk_sources+=("$source")
  done <<< "$blklist_output"
  
  if [[ ${#disk_targets[@]} -eq 0 ]]; then
    gum style --foreground 1 "No exportable disks found (only ISOs attached or no disks)."
    read -p "Press Enter to continue..."
    return 0
  fi
  
  # Show what will be exported
  gum style --foreground 212 "VM '$vm' will be exported with the following disks:"
  gum style --foreground 8 "(ISOs are NOT exported)"
  echo
  local idx
  for idx in "${!disk_targets[@]}"; do
    gum style "  ${disk_targets[$idx]}: ${disk_sources[$idx]}"
  done
  echo
  
  read -p "Proceed with export? (y/n) [y]: " proceed_confirm
  proceed_confirm=${proceed_confirm:-y}
  if [[ "${proceed_confirm,,}" != "y" ]]; then
    gum style --foreground 3 "Export cancelled."
    read -p "Press Enter to continue..."
    return 0
  fi
  
  # Choose compression level
  echo
  gum style --foreground 8 "Select compression level:"
  echo "  1) fast (gzip -1) - fastest, larger file"
  echo "  2) balanced (gzip -6) - moderate speed and size"
  echo "  3) max (gzip -9) - slowest, smallest file"
  read -p "Compression [1]: " comp_choice
  comp_choice=${comp_choice:-1}
  
  local gzip_level
  case "$comp_choice" in
    1) gzip_level="-1" ;;
    2) gzip_level="-6" ;;
    3) gzip_level="-9" ;;
    *) gzip_level="-1" ;;
  esac
  
  # Export directory
  echo
  gum style --foreground 8 "Enter export directory (will be created if needed):"
  read -p "Export directory [$HOME/vm_exports]: " export_dir
  export_dir=${export_dir:-$HOME/vm_exports}
  if ! mkdir -p "$export_dir" 2>/dev/null; then
    gum style --foreground 1 "✗ Cannot create directory: $export_dir"
    read -p "Press Enter to continue..."
    return 0
  fi
  
  local timestamp
  timestamp=$(date +%Y-%m-%d_%H-%M-%S)
  local archive_path="$export_dir/${vm}_${timestamp}.tar.gz"
  # Create temp dir in export directory (not /tmp which may be tmpfs with limited space)
  local tmpdir="$export_dir/.export_tmp_${vm}_$$"
  rm -rf "$tmpdir" 2>/dev/null
  mkdir -p "$tmpdir/disks"
  
  echo
  gum style --foreground 8 "Step 1/3: Dumping VM definition..."
  if ! virsh -c "$conn_uri" dumpxml "$vm" > "$tmpdir/vm.xml" 2>/dev/null; then
    gum style --foreground 1 "✗ Failed to dump VM XML."
    rm -rf "$tmpdir"
    read -p "Press Enter to continue..."
    return 0
  fi
  gum style --foreground 2 "✓ VM definition saved."
  
  # Create metadata
  echo "VM_NAME=\"$vm\"" > "$tmpdir/metadata.sh"
  echo "EXPORTED_AT=\"$timestamp\"" >> "$tmpdir/metadata.sh"
  local manifest="$tmpdir/manifest.csv"
  : > "$manifest"
  
  echo
  gum style --foreground 8 "Step 2/3: Copying disk images..."
  gum style --foreground 3 "(May require sudo for system VM disks)"
  
  for idx in "${!disk_targets[@]}"; do
    local target="${disk_targets[$idx]}"
    local source_path="${disk_sources[$idx]}"
    local disk_basename="${vm}_${target}_$(basename "$source_path")"
    local dest_path="$tmpdir/disks/$disk_basename"
    
    local disk_size_human
    disk_size_human=$(sudo du -h "$source_path" 2>/dev/null | cut -f1) || disk_size_human="unknown"
    
    echo
    gum style --foreground 8 "Copying $target: $(basename "$source_path") ($disk_size_human)..."
    
    # Use pv for progress if available, with sudo for permission
    if command -v pv &>/dev/null; then
      local disk_size_bytes
      disk_size_bytes=$(sudo stat -c%s "$source_path" 2>/dev/null) || disk_size_bytes=0
      if [[ "$disk_size_bytes" -gt 0 ]]; then
        if ! sudo cat "$source_path" | pv -s "$disk_size_bytes" -N "Copying" > "$dest_path"; then
          gum style --foreground 1 "✗ Failed to copy $source_path"
          rm -rf "$tmpdir"
          read -p "Press Enter to continue..."
          return 0
        fi
      else
        if ! sudo cp "$source_path" "$dest_path"; then
          gum style --foreground 1 "✗ Failed to copy $source_path"
          rm -rf "$tmpdir"
          read -p "Press Enter to continue..."
          return 0
        fi
      fi
    else
      if ! sudo cp -v "$source_path" "$dest_path"; then
        gum style --foreground 1 "✗ Failed to copy $source_path"
        rm -rf "$tmpdir"
        read -p "Press Enter to continue..."
        return 0
      fi
    fi
    
    echo "$disk_basename|$source_path" >> "$manifest"
    gum style --foreground 2 "✓ Copied $target"
  done
  
  # Create restore script
  cat > "$tmpdir/restore.sh" <<"RESTORE_SCRIPT"
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/metadata.sh"
MANIFEST="$SCRIPT_DIR/manifest.csv"
XML_FILE="$SCRIPT_DIR/vm.xml"

read -p "Destination libvirt URI [qemu:///system]: " DEST_URI
DEST_URI=${DEST_URI:-qemu:///system}

declare -A PATH_MAP

while IFS='|' read -r disk_file original_path; do
  [[ -z "$disk_file" ]] && continue
  default_dir=$(dirname "$original_path")
  read -p "Destination directory for $disk_file [$default_dir]: " dest_dir
  dest_dir=${dest_dir:-$default_dir}
  mkdir -p "$dest_dir"
  echo "Copying $disk_file to $dest_dir ..."
  cp "$SCRIPT_DIR/disks/$disk_file" "$dest_dir/$disk_file"
  new_path="$dest_dir/$disk_file"
  PATH_MAP["$original_path"]="$new_path"
done < "$MANIFEST"

for original_path in "${!PATH_MAP[@]}"; do
  new_path="${PATH_MAP[$original_path]}"
  sed -i "s|$original_path|$new_path|g" "$XML_FILE"
done

read -p "New VM name [$VM_NAME]: " NEW_VM_NAME
NEW_VM_NAME=${NEW_VM_NAME:-$VM_NAME}
if [[ "$NEW_VM_NAME" != "$VM_NAME" ]]; then
  sed -i "s|<name>$VM_NAME</name>|<name>$NEW_VM_NAME</name>|" "$XML_FILE"
fi

virsh -c "$DEST_URI" define "$XML_FILE"
echo "VM '$NEW_VM_NAME' defined on $DEST_URI."
echo "Start it with: virsh -c $DEST_URI start $NEW_VM_NAME"
RESTORE_SCRIPT
  chmod +x "$tmpdir/restore.sh"
  
  cat > "$tmpdir/README.txt" <<EOF
This archive was generated by spinner.sh on $(date).

Contents:
  - vm.xml          : Original libvirt domain XML
  - disks/          : Disk images (qcow2 only, no ISOs)
  - manifest.csv    : Mapping of disk filenames to their original paths
  - metadata.sh     : Metadata used during restore
  - restore.sh      : Helper script to copy disks and define the VM on a new host

Restore steps on the destination host:
  1. Extract the archive: tar -xzf $(basename "$archive_path")
  2. Run ./restore.sh and follow the prompts
  3. Start the VM with: virsh -c qemu:///system start <vm_name>
EOF
  
  echo
  gum style --foreground 8 "Step 3/3: Creating compressed archive..."
  gum style --foreground 8 "Archive: $archive_path"
  echo
  
  # Calculate total size for progress
  local total_size
  total_size=$(du -sb "$tmpdir" 2>/dev/null | cut -f1) || total_size=0
  
  # Use pv if available for progress, otherwise plain tar
  local tar_result=0
  if command -v pv &>/dev/null && [[ "$total_size" -gt 0 ]]; then
    tar -cf - -C "$tmpdir" . 2>/dev/null | pv -s "$total_size" -N "Compressing" | gzip "$gzip_level" > "$archive_path" || tar_result=$?
  else
    echo "(Install 'pv' for progress bar: sudo apt install pv)"
    tar -cvf - -C "$tmpdir" . 2>/dev/null | gzip "$gzip_level" > "$archive_path" || tar_result=$?
  fi
  
  if [[ $tar_result -ne 0 ]] || [[ ! -f "$archive_path" ]]; then
    gum style --foreground 1 "✗ Failed to create archive."
    rm -rf "$tmpdir" "$archive_path" 2>/dev/null
    read -p "Press Enter to continue..."
    return 0
  fi
  
  local archive_size
  archive_size=$(du -h "$archive_path" 2>/dev/null | cut -f1) || archive_size="unknown"
  
  # Cleanup temp dir
  rm -rf "$tmpdir"
  
  echo
  gum style --foreground 2 "════════════════════════════════════════"
  gum style --foreground 2 "✓ Export complete!"
  gum style --foreground 2 "  Archive: $archive_path"
  gum style --foreground 2 "  Size: $archive_size"
  gum style --foreground 2 "════════════════════════════════════════"
  echo
  read -p "Press Enter to continue..."
  return 0
}

modify_cdrom() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Modify CDROM: $vm ═══"
  echo
  
  # Get current CDROM devices
  gum style --foreground 8 "Current CDROM devices:"
  local cdrom_info
  cdrom_info=$(virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null | awk '$2 ~ /\.iso$/ || $2 == "-" {print $1, $2}')
  
  if [[ -z "$cdrom_info" ]]; then
    gum style --foreground 3 "No CDROM devices found on this VM."
    echo
    if gum confirm "Add a new CDROM device?"; then
      gum style --foreground 8 "Select ISO to attach:"
      local iso_files=()
      while IFS= read -r iso_file; do
        iso_files+=("$(basename "$iso_file")")
      done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | sort)
      
      if [ ${#iso_files[@]} -eq 0 ]; then
        gum style --foreground 1 "No ISOs found in $ISO_DIR"
        read -p "Press Enter to continue..."
        return
      fi
      
      iso_files+=("Cancel")
      local selected_iso
      selected_iso=$(gum choose --header="Select ISO:" "${iso_files[@]}" || echo "Cancel")
      
      if [[ "$selected_iso" != "Cancel" ]]; then
        local iso_path="$ISO_DIR/$selected_iso"
        if virsh -c "$conn_uri" attach-disk "$vm" "$iso_path" sda --type cdrom --mode readonly --config; then
          gum style --foreground 2 "✓ CDROM attached: $selected_iso"
        else
          gum style --foreground 1 "✗ Failed to attach CDROM."
        fi
      fi
    fi
    read -p "Press Enter to continue..."
    return
  fi
  
  echo "$cdrom_info" | while read -r target source; do
    if [[ "$source" == "-" ]]; then
      gum style "  $target: (empty - no ISO mounted)"
    else
      gum style "  $target: $(basename "$source")"
    fi
  done
  echo
  
  # Select device to modify
  local devices=()
  while read -r target source; do
    [[ -z "$target" ]] && continue
    devices+=("$target")
  done <<< "$cdrom_info"
  
  devices+=("Cancel")
  
  local selected_device
  selected_device=$(gum choose --header="Select CDROM device to modify:" "${devices[@]}" || echo "Cancel")
  
  if [[ "$selected_device" == "Cancel" ]]; then
    return
  fi
  
  # Get current ISO for this device
  local current_iso
  current_iso=$(echo "$cdrom_info" | awk -v dev="$selected_device" '$1==dev {print $2}')
  
  echo
  if [[ "$current_iso" == "-" ]]; then
    gum style --foreground 8 "$selected_device is currently empty."
  else
    gum style --foreground 8 "$selected_device currently has: $(basename "$current_iso")"
  fi
  
  # Action menu
  local cdrom_action
  cdrom_action=$(gum choose --header="What do you want to do?" \
    "Mount new ISO" \
    "Eject/Unmount" \
    "Cancel" \
    || echo "Cancel")
  
  case "$cdrom_action" in
    "Mount new ISO")
      local iso_files=()
      while IFS= read -r iso_file; do
        iso_files+=("$(basename "$iso_file")")
      done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | sort)
      
      if [ ${#iso_files[@]} -eq 0 ]; then
        gum style --foreground 1 "No ISOs found in $ISO_DIR"
        read -p "Press Enter to continue..."
        return
      fi
      
      iso_files+=("Cancel")
      local selected_iso
      selected_iso=$(gum choose --header="Select ISO to mount:" "${iso_files[@]}" || echo "Cancel")
      
      if [[ "$selected_iso" != "Cancel" ]]; then
        local iso_path="$ISO_DIR/$selected_iso"
        if virsh -c "$conn_uri" change-media "$vm" "$selected_device" "$iso_path" --config; then
          gum style --foreground 2 "✓ Mounted $selected_iso on $selected_device"
        else
          gum style --foreground 1 "✗ Failed to mount ISO."
        fi
      fi
      ;;
    "Eject/Unmount")
      if [[ "$current_iso" == "-" ]]; then
        gum style --foreground 3 "Device is already empty."
      else
        if gum confirm "Eject ISO from $selected_device?"; then
          if virsh -c "$conn_uri" change-media "$vm" "$selected_device" --eject --config; then
            gum style --foreground 2 "✓ Ejected ISO from $selected_device"
          else
            gum style --foreground 1 "✗ Failed to eject ISO."
          fi
        fi
      fi
      ;;
    *)
      ;;
  esac
  
  read -p "Press Enter to continue..."
}

modify_storage() {
  local vm="$1"
  local conn_uri="$2"
  
  clear
  gum style --bold --foreground 212 "═══ Modify Storage: $vm ═══"
  echo
  
  # Get current storage devices (non-ISO)
  gum style --foreground 8 "Current storage devices:"
  local storage_info
  storage_info=$(virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null | awk 'NR>2 && $2 !~ /\.iso$/ && $2 != "-" {print $1, $2}')
  
  if [[ -z "$storage_info" ]]; then
    gum style --foreground 3 "No storage devices found."
  else
    while read -r target source; do
      [[ -z "$target" ]] && continue
      local disk_size=""
      if [[ -f "$source" ]]; then
        disk_size=$(qemu-img info "$source" 2>/dev/null | awk '/virtual size:/ {print $3, $4}')
      fi
      gum style "  $target: $(basename "$source") ${disk_size:+($disk_size)}"
    done <<< "$storage_info"
  fi
  echo
  
  # Action menu
  local storage_action
  storage_action=$(gum choose --header="Storage actions:" \
    "Add new disk (create qcow2)" \
    "Attach existing disk file" \
    "Detach a disk" \
    "Cancel" \
    || echo "Cancel")
  
  case "$storage_action" in
    "Add new disk (create qcow2)")
      gum style --foreground 8 "Create a new qcow2 disk and attach it."
      
      # Get next available device
      local used_devices
      used_devices=$(virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null | awk 'NR>2 {print $1}')
      local next_dev="vdb"
      for dev in vdb vdc vdd vde vdf; do
        if ! echo "$used_devices" | grep -q "^$dev$"; then
          next_dev="$dev"
          break
        fi
      done
      
      read -p "Disk size in GB [20]: " new_disk_size
      new_disk_size=${new_disk_size:-20}
      new_disk_size=$(echo "$new_disk_size" | tr -cd '0-9')
      
      if [[ -z "$new_disk_size" ]]; then
        gum style --foreground 1 "Invalid size."
        read -p "Press Enter to continue..."
        return
      fi
      
      local new_disk_path="$DISK_DIR/${vm}-${next_dev}.qcow2"
      
      if [[ -f "$new_disk_path" ]]; then
        gum style --foreground 1 "Disk $new_disk_path already exists."
        read -p "Press Enter to continue..."
        return
      fi
      
      gum style --foreground 8 "Creating ${new_disk_size}GB disk at $new_disk_path..."
      if qemu-img create -f qcow2 "$new_disk_path" "${new_disk_size}G"; then
        if virsh -c "$conn_uri" attach-disk "$vm" "$new_disk_path" "$next_dev" \
            --driver qemu --subdriver qcow2 --targetbus virtio --persistent --cache "$DISK_CACHE"; then
          gum style --foreground 2 "✓ Created and attached ${new_disk_size}GB disk as $next_dev"
        else
          gum style --foreground 1 "✗ Disk created but failed to attach."
        fi
      else
        gum style --foreground 1 "✗ Failed to create disk."
      fi
      ;;
      
    "Attach existing disk file")
      gum style --foreground 8 "Enter path to existing qcow2/raw disk:"
      read -p "Disk path: " existing_disk
      
      if [[ ! -f "$existing_disk" ]]; then
        gum style --foreground 1 "File not found: $existing_disk"
        read -p "Press Enter to continue..."
        return
      fi
      
      # Get next available device
      local used_devices
      used_devices=$(virsh -c "$conn_uri" domblklist "$vm" 2>/dev/null | awk 'NR>2 {print $1}')
      local next_dev="vdb"
      for dev in vdb vdc vdd vde vdf; do
        if ! echo "$used_devices" | grep -q "^$dev$"; then
          next_dev="$dev"
          break
        fi
      done
      
      local subdriver="qcow2"
      if [[ "$existing_disk" == *.raw ]] || [[ "$existing_disk" == *.img ]]; then
        subdriver="raw"
      fi
      
      if virsh -c "$conn_uri" attach-disk "$vm" "$existing_disk" "$next_dev" \
          --driver qemu --subdriver "$subdriver" --targetbus virtio --persistent --cache "$DISK_CACHE"; then
        gum style --foreground 2 "✓ Attached $existing_disk as $next_dev"
      else
        gum style --foreground 1 "✗ Failed to attach disk."
      fi
      ;;
      
    "Detach a disk")
      if [[ -z "$storage_info" ]]; then
        gum style --foreground 3 "No disks to detach."
        read -p "Press Enter to continue..."
        return
      fi
      
      local disk_devices=()
      while read -r target source; do
        [[ -z "$target" ]] && continue
        disk_devices+=("$target - $(basename "$source")")
      done <<< "$storage_info"
      disk_devices+=("Cancel")
      
      local selected_disk
      selected_disk=$(gum choose --header="Select disk to detach:" "${disk_devices[@]}" || echo "Cancel")
      
      if [[ "$selected_disk" == "Cancel" ]]; then
        return
      fi
      
      local detach_target
      detach_target=$(echo "$selected_disk" | awk '{print $1}')
      
      gum style --foreground 1 "⚠ Warning: Detaching a disk may cause data loss if the VM is using it!"
      if gum confirm --default=false "Detach $detach_target?"; then
        if virsh -c "$conn_uri" detach-disk "$vm" "$detach_target" --persistent --config; then
          gum style --foreground 2 "✓ Detached $detach_target"
          gum style --foreground 3 "Note: The disk file was NOT deleted. Remove it manually if needed."
        else
          gum style --foreground 1 "✗ Failed to detach disk."
        fi
      fi
      ;;
      
    *)
      ;;
  esac
  
  read -p "Press Enter to continue..."
}

create_new_vm() {
  clear
  gum style --bold --foreground 212 "═══ Create New Virtual Machine ═══"
  echo
  
  # VM Name
  vm_name=$(gum input --placeholder "Enter VM name" --prompt "VM Name: ")
  if [[ -z "$vm_name" ]]; then
    gum style --foreground 1 "✗ No name provided. Aborting."
    read -p "Press Enter to continue..."
    return
  fi
  
  # Check if name already exists
  if virsh -c "$SYSTEM_URI" dominfo "$vm_name" &>/dev/null; then
    gum style --foreground 1 "✗ VM '$vm_name' already exists. Aborting."
    read -p "Press Enter to continue..."
    return
  fi
  
  # OS Variant
  gum style --foreground 8 "Common OS variants: win11, win10, debian12, ubuntu24.04, rhel9, generic"
  os_variant=$(gum input --placeholder "e.g., win11, debian12, generic" --prompt "OS Variant: " --value "generic")
  
  # Memory (MB)
  memory=$(gum input --placeholder "Memory in MB (e.g., 4096)" --prompt "Memory (MB): " --value "4096")
  if ! [[ "$memory" =~ ^[0-9]+$ ]]; then
    gum style --foreground 1 "✗ Invalid memory value. Aborting."
    read -p "Press Enter to continue..."
    return
  fi
  
  # vCPUs
  vcpus=$(gum input --placeholder "Number of vCPUs (e.g., 4)" --prompt "vCPUs: " --value "4")
  if ! [[ "$vcpus" =~ ^[0-9]+$ ]]; then
    gum style --foreground 1 "✗ Invalid vCPU value. Aborting."
    read -p "Press Enter to continue..."
    return
  fi
  
  # CPU Mode
  cpu_mode=$(gum choose --header="CPU Mode:" \
    "host-passthrough (best performance)" \
    "host-model (good compatibility)" \
    "default")
  cpu_mode=${cpu_mode%% *}
  
  # Primary Disk
  disk_size=$(gum input --placeholder "Disk size in GB (e.g., 100)" --prompt "Primary Disk Size (GB): " --value "100")
  if ! [[ "$disk_size" =~ ^[0-9]+$ ]]; then
    gum style --foreground 1 "✗ Invalid disk size. Aborting."
    read -p "Press Enter to continue..."
    return
  fi
  
  # Disk Cache
  disk_cache=$(gum choose --header="Disk Cache Mode:" \
    "writeback (fastest)" \
    "writethrough (balanced)" \
    "none (safest)")
  disk_cache=${disk_cache%% *}
  
  # Second Disk
  add_second_disk=false
  if gum confirm "Add a second disk?"; then
    second_disk_size=$(gum input --placeholder "Second disk size in GB" --prompt "Second Disk Size (GB): ")
    if [[ -n "$second_disk_size" ]] && [[ "$second_disk_size" =~ ^[0-9]+$ ]]; then
      add_second_disk=true
      second_disk_cache=$(gum choose --header="Second Disk Cache Mode:" \
        "writeback (fastest)" \
        "writethrough (balanced)" \
        "none (safest)")
      second_disk_cache=${second_disk_cache%% *}
    fi
  fi
  
  # First ISO (Boot)
  first_iso=""
  
  # Check if ISO directory exists
  if [[ ! -d "$ISO_DIR" ]]; then
    gum style --foreground 3 "⚠️  ISO directory not found: $ISO_DIR"
    echo ""
    
    local iso_choice
    iso_choice=$(gum choose --header="What would you like to do?" \
      "Browse for ISO file manually" \
      "Create ISO directory ($ISO_DIR)" \
      "No ISO (PXE/Network boot)")
    
    case "$iso_choice" in
      "Browse for ISO file manually")
        gum style --foreground 6 "Enter full path to ISO file:"
        read -e -p "> " first_iso
        if [[ -f "$first_iso" ]]; then
          gum style --foreground 2 "✓ ISO file found: $first_iso"
        else
          gum style --foreground 1 "✗ File not found, continuing without ISO"
          first_iso=""
        fi
        ;;
      "Create ISO directory ($ISO_DIR)")
        mkdir -p "$ISO_DIR"
        gum style --foreground 2 "✓ Created directory: $ISO_DIR"
        gum style --foreground 8 "Please copy your ISO files there and run the script again."
        first_iso=""
        ;;
      "No ISO (PXE/Network boot)")
        first_iso=""
        ;;
    esac
  else
    # Directory exists, scan for ISOs
    iso_files=()
    while IFS= read -r iso_file; do
      iso_files+=("$(basename "$iso_file")")
    done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | sort)
    
    iso_files+=("Browse for ISO elsewhere")
    iso_files+=("No ISO (PXE/Network boot)")
    
    if [ ${#iso_files[@]} -gt 2 ]; then
      selected_iso=$(gum choose --header="Select Boot ISO (1st CD-ROM):" "${iso_files[@]}")
      
      case "$selected_iso" in
        "Browse for ISO elsewhere")
          gum style --foreground 6 "Enter full path to ISO file:"
          read -e -p "> " first_iso
          if [[ ! -f "$first_iso" ]]; then
            gum style --foreground 1 "✗ File not found, continuing without ISO"
            first_iso=""
          fi
          ;;
        "No ISO (PXE/Network boot)")
          first_iso=""
          ;;
        *)
          first_iso="$ISO_DIR/$selected_iso"
          ;;
      esac
    else
      gum style --foreground 3 "No ISOs found in $ISO_DIR"
      
      if gum confirm "Browse for ISO file manually?"; then
        gum style --foreground 6 "Enter full path to ISO file:"
        read -e -p "> " first_iso
        if [[ ! -f "$first_iso" ]]; then
          gum style --foreground 1 "✗ File not found, continuing without ISO"
          first_iso=""
        fi
      fi
    fi
  fi
  
  # Second ISO (only ask if first ISO was selected or user wants one)
  second_iso=""
  if [[ -n "$first_iso" ]] || gum confirm "Add an ISO (e.g., drivers, second CD)?"; then
    if [[ -d "$ISO_DIR" ]]; then
      iso_files2=()
      while IFS= read -r iso_file; do
        iso_files2+=("$(basename "$iso_file")")
      done < <(find "$ISO_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | sort)
      
      iso_files2+=("Browse for ISO elsewhere")
      iso_files2+=("Skip")
      
      if [ ${#iso_files2[@]} -gt 2 ]; then
        selected_iso2=$(gum choose --header="Select Second ISO (optional):" "${iso_files2[@]}")
        
        case "$selected_iso2" in
          "Browse for ISO elsewhere")
            gum style --foreground 6 "Enter full path to ISO file:"
            read -e -p "> " second_iso
            if [[ ! -f "$second_iso" ]]; then
              gum style --foreground 1 "✗ File not found, skipping second ISO"
              second_iso=""
            fi
            ;;
          "Skip")
            second_iso=""
            ;;
          *)
            second_iso="$ISO_DIR/$selected_iso2"
            ;;
        esac
      fi
    else
      # ISO_DIR doesn't exist, offer manual browse
      if gum confirm "Browse for second ISO file manually?"; then
        gum style --foreground 6 "Enter full path to ISO file:"
        read -e -p "> " second_iso
        if [[ ! -f "$second_iso" ]]; then
          gum style --foreground 1 "✗ File not found, skipping second ISO"
          second_iso=""
        fi
      fi
    fi
  fi
  
  # Check ISO accessibility and offer to fix if needed
  check_and_fix_iso_access() {
    local iso_path="$1"
    local iso_name=$(basename "$iso_path")
    local iso_dir=$(dirname "$iso_path")
    
    # Check if ISO is in user's home directory (common permission issue)
    if [[ "$iso_path" == "$HOME"* ]]; then
      gum style --foreground 3 "⚠️  ISO is in your home directory: $iso_path"
      gum style --foreground 3 "   QEMU/libvirt may not have permission to access it."
      echo ""
      
      local fix_choice
      fix_choice=$(gum choose --header="How would you like to proceed?" \
        "Fix permissions (add qemu user access)" \
        "Create symlink in $DISK_DIR" \
        "Copy ISO to $DISK_DIR (slow, uses space)" \
        "Use original path anyway (may fail)" \
        "Cancel VM creation")
      
      case "$fix_choice" in
        "Fix permissions (add qemu user access)")
          gum style --foreground 6 "Adding qemu user permissions with ACL..."
          
          # Add execute permission on parent directories so qemu can traverse
          local current_dir="$iso_dir"
          while [[ "$current_dir" != "/" && "$current_dir" == "$HOME"* ]]; do
            sudo setfacl -m u:qemu:x "$current_dir" 2>/dev/null || {
              gum style --foreground 1 "✗ Failed to set ACL (is acl package installed?)"
              gum style --foreground 8 "Try: sudo dnf install acl"
              return 1
            }
            current_dir=$(dirname "$current_dir")
          done
          
          # Add read permission on the ISO file
          sudo setfacl -m u:qemu:r "$iso_path"
          
          gum style --foreground 2 "✓ Permissions fixed (qemu user can now access the file)"
          echo "$iso_path"
          return 0
          ;;
          
        "Create symlink in $DISK_DIR")
          gum style --foreground 6 "Creating symlink..."
          
          if [[ ! -d "$DISK_DIR" ]]; then
            sudo mkdir -p "$DISK_DIR"
          fi
          
          local link_path="$DISK_DIR/$iso_name"
          if sudo ln -sf "$iso_path" "$link_path" 2>/dev/null; then
            # Still need to fix permissions on the original file
            sudo setfacl -m u:qemu:r "$iso_path" 2>/dev/null || true
            
            local current_dir="$iso_dir"
            while [[ "$current_dir" != "/" && "$current_dir" == "$HOME"* ]]; do
              sudo setfacl -m u:qemu:x "$current_dir" 2>/dev/null || true
              current_dir=$(dirname "$current_dir")
            done
            
            gum style --foreground 2 "✓ Symlink created: $link_path → $iso_path"
            echo "$link_path"
            return 0
          else
            gum style --foreground 1 "✗ Failed to create symlink"
            return 1
          fi
          ;;
          
        "Copy ISO to $DISK_DIR (slow, uses space)")
          gum style --foreground 6 "Copying $iso_name to $DISK_DIR..."
          gum style --foreground 8 "(This may take a while for large ISOs)"
          
          if [[ ! -d "$DISK_DIR" ]]; then
            sudo mkdir -p "$DISK_DIR"
          fi
          
          # Copy with progress using pv if available
          local new_path="$DISK_DIR/$iso_name"
          if command -v pv &>/dev/null; then
            sudo pv "$iso_path" | sudo tee "$new_path" > /dev/null
          else
            sudo cp -v "$iso_path" "$new_path"
          fi
          
          if [[ $? -eq 0 ]]; then
            sudo chmod 644 "$new_path"
            sudo chown qemu:qemu "$new_path" 2>/dev/null || true
            gum style --foreground 2 "✓ ISO copied successfully"
            echo "$new_path"
            return 0
          else
            gum style --foreground 1 "✗ Failed to copy ISO"
            return 1
          fi
          ;;
          
        "Use original path anyway (may fail)")
          gum style --foreground 8 "Proceeding with original path..."
          gum style --foreground 8 "If it fails, you can fix permissions manually:"
          gum style --foreground 8 "  sudo setfacl -m u:qemu:rx $(dirname "$iso_path")"
          gum style --foreground 8 "  sudo setfacl -m u:qemu:r $iso_path"
          echo "$iso_path"
          return 0
          ;;
          
        "Cancel VM creation")
          gum style --foreground 1 "VM creation cancelled"
          return 2
          ;;
      esac
    else
      # ISO is in a safe location (not in home directory)
      echo "$iso_path"
      return 0
    fi
  }
  
  # Check and fix ISO access for first ISO
  if [[ -n "$first_iso" ]]; then
    first_iso=$(check_and_fix_iso_access "$first_iso")
    local iso_check_result=$?
    if [[ $iso_check_result -eq 2 ]]; then
      read -p "Press Enter to continue..."
      return
    elif [[ $iso_check_result -eq 1 ]]; then
      gum style --foreground 3 "Continuing without first ISO..."
      first_iso=""
    fi
  fi
  
  # Check and fix ISO access for second ISO
  if [[ -n "$second_iso" ]]; then
    second_iso=$(check_and_fix_iso_access "$second_iso")
    local iso_check_result=$?
    if [[ $iso_check_result -eq 2 ]]; then
      read -p "Press Enter to continue..."
      return
    elif [[ $iso_check_result -eq 1 ]]; then
      gum style --foreground 3 "Continuing without second ISO..."
      second_iso=""
    fi
  fi
  
  # Graphics
  graphics_type=$(gum choose --header="Graphics Type:" \
    "vnc (VNC server)" \
    "spice (SPICE)" \
    "none (headless)")
  graphics_type=${graphics_type%% *}
  
  vnc_password=""
  vnc_listen="127.0.0.1"
  spice_password=""
  
  if [[ "$graphics_type" == "vnc" ]]; then
    if gum confirm "Set VNC password?"; then
      while true; do
        vnc_password=$(gum input --placeholder "VNC password (max 8 chars)" --password --prompt "VNC Password: ")
        if [[ -z "$vnc_password" ]]; then
          gum style --foreground 3 "Password cannot be empty. Try again or press Ctrl+C to skip."
          continue
        elif [[ ${#vnc_password} -gt 8 ]]; then
          gum style --foreground 3 "⚠️  VNC password max length is 8 characters. Truncating to: ${vnc_password:0:8}"
          vnc_password="${vnc_password:0:8}"
    sleep 2
          break
        else
          break
        fi
      done
    fi
    if gum confirm "Listen on all interfaces (0.0.0.0)?"; then
      vnc_listen="0.0.0.0"
    fi
  elif [[ "$graphics_type" == "spice" ]]; then
    if gum confirm "Set SPICE password?"; then
      spice_password=$(gum input --placeholder "SPICE password" --password --prompt "SPICE Password: ")
      if [[ -z "$spice_password" ]]; then
        gum style --foreground 3 "⚠️  Empty password, SPICE will run without password."
        spice_password=""
      fi
    fi
  fi
  
  # Autoconsole
  autoconsole="--noautoconsole"
  if gum confirm "Open console after creation?"; then
    autoconsole=""
  fi
  
  # Network
  network=$(gum choose --header="Network:" \
    "default (NAT)" \
    "bridge (Bridged)" \
    "none")
  
  network_mode="nat"
  network_summary="default (NAT)"
  
  case "$network" in
    "default"*)
      network_mode="nat"
      network_summary="Host NAT (network=default)"
      network_opt="--network network=default"
      ;;
    "bridge"*)
      bridge_name=$(gum input --placeholder "Bridge name (e.g., br0)" --prompt "Bridge: " --value "br0")
      network_mode="bridge"
      network_summary="Bridge: $bridge_name"
      network_opt="--network bridge=$bridge_name"
      ;;
    "none")
      network_mode="none"
      network_summary="No network"
      network_opt="--network none"
      ;;
  esac
  
  # Build virt-install command
  echo
  gum style --bold --foreground 212 "Building VM..."
  
  virt_cmd="virt-install --connect $SYSTEM_URI --name $vm_name --memory $memory --vcpu $vcpus"
  
  # CPU mode
  if [[ "$cpu_mode" != "default" ]]; then
    virt_cmd="$virt_cmd --cpu $cpu_mode"
  fi
  
  # Boot ISO
  if [[ -n "$first_iso" ]]; then
    virt_cmd="$virt_cmd --cdrom \"$first_iso\""
  else
    virt_cmd="$virt_cmd --pxe"
  fi
  
  # OS variant
  virt_cmd="$virt_cmd --os-variant $os_variant"
  
  # Primary disk
  virt_cmd="$virt_cmd --disk size=$disk_size,cache=$disk_cache,bus=virtio"
  
  # Second disk
  if [[ "$add_second_disk" == true ]]; then
    second_disk_path="$DISK_DIR/${vm_name}-disk2.qcow2"
    virt_cmd="$virt_cmd --disk path=$second_disk_path,size=$second_disk_size,cache=$second_disk_cache,bus=virtio"
  fi
  
  # Second ISO
  if [[ -n "$second_iso" ]]; then
    virt_cmd="$virt_cmd --disk path=\"$second_iso\",device=cdrom"
  fi
  
  # Graphics
  case "$graphics_type" in
    "vnc")
      if [[ -n "$vnc_password" ]]; then
        virt_cmd="$virt_cmd --graphics vnc,listen=$vnc_listen,password=$vnc_password"
      else
        virt_cmd="$virt_cmd --graphics vnc,listen=$vnc_listen"
      fi
      ;;
    "spice")
      if [[ -n "$spice_password" ]]; then
        virt_cmd="$virt_cmd --graphics spice,password=$spice_password"
      else
        virt_cmd="$virt_cmd --graphics spice"
      fi
      ;;
    "none")
      virt_cmd="$virt_cmd --graphics none"
      ;;
  esac
  
  # Network
  virt_cmd="$virt_cmd $network_opt"
  
  # Autoconsole
  virt_cmd="$virt_cmd $autoconsole"
  
  # Show summary
  echo
  graphics_display="$graphics_type"
  if [[ "$graphics_type" == "vnc" && -n "$vnc_password" ]]; then
    graphics_display="$graphics_type (password set, listen=$vnc_listen)"
  elif [[ "$graphics_type" == "vnc" ]]; then
    graphics_display="$graphics_type (no password, listen=$vnc_listen)"
  elif [[ "$graphics_type" == "spice" && -n "$spice_password" ]]; then
    graphics_display="$graphics_type (password set)"
  fi
  
  gum style --border rounded --padding "0 1" --margin "1 0" \
    "VM Name:        $vm_name" \
    "OS Variant:    $os_variant" \
    "Memory:        ${memory}MB" \
    "vCPUs:         $vcpus" \
    "CPU Mode:      $cpu_mode" \
    "Disk 1:        ${disk_size}GB (cache=$disk_cache)" \
    "$([ "$add_second_disk" == true ] && echo "Disk 2:        ${second_disk_size}GB (cache=$second_disk_cache)" || echo "")" \
    "Boot ISO:      ${first_iso:-PXE}" \
    "$([ -n "$second_iso" ] && echo "Second ISO:    $(basename "$second_iso")" || echo "")" \
    "Graphics:      $graphics_display" \
    "Network:       $network_summary"
  
  echo
  if ! gum confirm "Create VM with these settings?"; then
    gum style --foreground 3 "VM creation cancelled."
    read -p "Press Enter to continue..."
    return
  fi
  
  # Execute virt-install
  echo
  gum style --bold --foreground 212 "Creating VM..."
  echo
  
  if eval "$virt_cmd"; then
    gum style --foreground 2 "✓ VM '$vm_name' created successfully!"
    
    # Gather display info
    host_ip=$(hostname -I | awk '{print $1}')
    vnc_display=$(virsh -c "$SYSTEM_URI" vncdisplay "$vm_name" 2>/dev/null | tr -d '\r')
    display_info="Graphics: none"
    if [[ -n "$vnc_display" ]]; then
      vnc_num=${vnc_display#:}
      vnc_port=$((5900 + vnc_num))
      display_info="VNC: connect to ${host_ip}${vnc_display} (tcp port $vnc_port)"
    else
      spice_display=$(virsh -c "$SYSTEM_URI" domdisplay "$vm_name" 2>/dev/null | tr -d '\r')
      if [[ -n "$spice_display" ]]; then
        display_info="Display: $spice_display"
      fi
    fi
    
    network_info=""
    if [[ "$network_mode" == "bridge" ]]; then
      mac_addr=$(virsh -c "$SYSTEM_URI" domiflist "$vm_name" 2>/dev/null | awk 'NR>2 && $1 != "" {print $5; exit}')
      guest_ip=""
      if [[ -n "$mac_addr" ]]; then
        for attempt in {1..15}; do
          guest_ip=$(ip neigh show | awk -v mac="$mac_addr" 'tolower($5)==tolower(mac){print $1; exit}')
          if [[ -n "$guest_ip" ]]; then
            break
          fi
          sleep 2
        done
      fi
      if [[ -n "$guest_ip" ]]; then
        network_info="Bridge IP detected: $guest_ip"
      else
        network_info="Bridge mode: IP not yet assigned. After guest boots, run 'virsh domifaddr $vm_name' or 'ip neigh' to find it."
      fi
    elif [[ "$network_mode" == "nat" ]]; then
      network_info="NAT mode: access services via host $host_ip; use the VNC info above."
    else
      network_info="No network configured for this VM."
    fi
    
    gum style --border rounded --padding "0 1" --margin "1 0" \
      "$display_info" \
      "$network_info"
    
    # Refresh VM list
    VM_NAMES=()
    VM_URIS=()
    VM_LABELS=()
    VM_STATES=()
    VM_SEEN=()
    append_vms "$SESSION_URI" "session"
    append_vms "$SYSTEM_URI" "system"
  else
    gum style --foreground 1 "✗ VM creation failed. Check error messages above."
  fi
  
  echo
  read -p "Press Enter to continue..."
}

# Gather VMs from both connections
gum spin --spinner dot --title "Scanning libvirt connections..." -- sleep 0.5
append_vms "$SESSION_URI" "session"
append_vms "$SYSTEM_URI" "system"

# Main loop
while true; do
  clear
  # Header with gum style
  if [[ ${VM_NAMES+x} ]]; then
    vm_count=${#VM_NAMES[@]}
  else
    vm_count=0
  fi
  
  # Get system stats for side panel
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}' 2>/dev/null || echo "0")
  mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}' 2>/dev/null || echo "?/?")
  mem_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}' 2>/dev/null || echo "0")
  load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}' 2>/dev/null || echo "0.00")
  uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
  
  # Get disk info
  disk_info=""
  while read -r line; do
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    percent=$(echo "$line" | awk '{print $5}')
    mount=$(echo "$line" | awk '{print $6}')
    [[ "$mount" == "/" ]] && mount="root"
    [[ "$mount" == "/boot/efi" ]] && mount="efi"
    [[ "$mount" == "/home" ]] && mount="home"
    disk_info+="$mount: $used/$size ($percent)  "
  done < <(df -h 2>/dev/null | grep -E '^/dev/' | head -3)
  
  # Color based on CPU usage
  cpu_color="2"  # green
  [[ $cpu_usage -gt 50 ]] && cpu_color="3"  # yellow
  [[ $cpu_usage -gt 80 ]] && cpu_color="1"  # red
  
  # Color based on RAM usage
  ram_color="2"
  [[ $mem_percent -gt 50 ]] && ram_color="3"
  [[ $mem_percent -gt 80 ]] && ram_color="1"

  # Display header using gum join for side-by-side layout
  echo
  
  # Left side: App title with ASCII art
  spinner_logo=$(cat << 'LOGO'
█▀ █▀█ █ █▄░█ █▄░█ █▀▀ █▀█
▄█ █▀▀ █ █░▀█ █░▀█ ██▄ █▀▄
LOGO
)
  left_panel=$(gum style --border double --border-foreground 212 --padding "1 2" --width 42 \
    "$(gum style --bold --foreground 212 'VIRT')" \
    "$(gum style --bold --foreground 99 "$spinner_logo")" \
    "$(gum style --foreground 8 "v$VERSION")" \
    "" \
    "$(gum style --foreground 212 'Libvirt VM Manager')" \
    "$(gum style --foreground 8 "Found $vm_count VM(s)")")
  
  # Right side: Host stats
  right_panel=$(gum style --border rounded --border-foreground 51 --padding "0 2" --width 45 \
    "$(gum style --bold --foreground 51 'Host Stats')" \
    "$(gum style --foreground $cpu_color "CPU: ${cpu_usage}%") $(gum style --foreground $ram_color "RAM: ${mem_info} (${mem_percent}%)")" \
    "$(gum style --foreground 8 "Load: ${load_avg}")" \
    "$(gum style --foreground 8 "Up: ${uptime_str}")" \
    "" \
    "$(gum style --bold --foreground 51 'Disks')" \
    "$(gum style --foreground 6 "$disk_info")")
  
  # Join panels side by side
  gum join --horizontal "$left_panel" "  " "$right_panel"
  
  gum style --foreground 8 "by $AUTHOR_NAME ($AUTHOR_EMAIL)"
  gum style --foreground 8 --italic "a project made with help of Cursor.ai"
  echo
  
  # Build fzf input with state indicators and special options
  fzf_lines=()
  fzf_lines+=("➕ Create New VM")
  fzf_lines+=("📸 Snapshot Manager")
  fzf_lines+=("📊 Live System Monitor")
  fzf_lines+=("⚙️  Settings")
  fzf_lines+=("🔧 Run Diagnostics")
  fzf_lines+=("❌ Exit")
  fzf_lines+=("---")
  
  for i in "${!VM_NAMES[@]}"; do
    state_icon="●"
    state_color=""
    case "${VM_STATES[$i]}" in
      running) state_icon="🟢" ;;
      "shut off") state_icon="⚫" ;;
      paused) state_icon="🟡" ;;
      *) state_icon="❓" ;;
    esac
    fzf_lines+=("$state_icon ${VM_NAMES[$i]} [${VM_LABELS[$i]}] (${VM_STATES[$i]})")
  done
  
  # Use fzf for VM selection with preview
  selection=$(printf '%s\n' "${fzf_lines[@]}" | \
    fzf --height=50% \
        --border=rounded \
        --prompt="Select VM or Action > " \
        --header="↑↓: navigate | Enter: select | Esc: exit" \
        --preview-window=right:50% \
        --preview='echo "Selection: {}" | sed "s/^[^ ]* //"' \
        --bind 'esc:abort' \
        || echo "")
  
  if [[ -z "$selection" ]]; then
    gum style --foreground 2 "Exiting VM Manager."
    exit 0
  fi
  
  # Handle special menu options
  if [[ "$selection" == "➕ Create New VM" ]]; then
    create_new_vm
    # Refresh VM list
    VM_NAMES=()
    VM_URIS=()
    VM_LABELS=()
    VM_STATES=()
    VM_SEEN=()
    append_vms "$SESSION_URI" "session"
    append_vms "$SYSTEM_URI" "system"
    continue
  elif [[ "$selection" == "📸 Snapshot Manager" ]]; then
    snapshot_manager
    continue
  elif [[ "$selection" == "📊 Live System Monitor" ]]; then
    live_system_monitor
    continue
  elif [[ "$selection" == "⚙️  Settings" ]]; then
    settings_menu
    continue
  elif [[ "$selection" == "🔧 Run Diagnostics" ]]; then
    clear
    run_diagnostics
    echo
    read -p "Press Enter to continue..."
    continue
  elif [[ "$selection" == "❌ Exit" ]]; then
    gum style --foreground 2 "Exiting VM Manager."
    exit 0
  elif [[ "$selection" == "---" ]]; then
    continue
  fi
  
  # Extract VM name from selection
  selected_vm=$(echo "$selection" | sed 's/^[^ ]* //' | awk '{print $1}')
  
  # Find index
  vm_idx=-1
  for i in "${!VM_NAMES[@]}"; do
    if [[ "${VM_NAMES[$i]}" == "$selected_vm" ]]; then
      vm_idx=$i
      break
    fi
  done
  
  if [[ $vm_idx -eq -1 ]]; then
    gum style --foreground 1 "Error: VM not found."
    sleep 2
    continue
  fi
  
  vm="${VM_NAMES[$vm_idx]}"
  conn="${VM_URIS[$vm_idx]}"
  label="${VM_LABELS[$vm_idx]}"
  state="${VM_STATES[$vm_idx]}"
  
  clear
  gum style --bold --foreground 212 "Selected: $vm [$label]"
  gum style "Current state: $state"
  echo
  
  # If not running, offer to start
  if [[ "$state" != "running" ]]; then
    if gum confirm "VM is not running. Start it?"; then
      if run_with_spinner "Starting $vm..." virsh -c "$conn" start "$vm"; then
        gum style --foreground 2 "✓ VM started successfully."
        sleep 1
        # Refresh state
        VM_STATES[$vm_idx]=$(virsh -c "$conn" domstate "$vm" 2>/dev/null || echo "unknown")
        continue
      else
        read -p "Press Enter to continue..."
      fi
    fi
  fi
  
  # Action menu
  while true; do
    # Refresh state for dynamic menu
    current_state=$(virsh -c "$conn" domstate "$vm" 2>/dev/null || echo "unknown")
    
    # Build dynamic menu based on state
    menu_items=("Show VM Info")
    
    if [[ "$current_state" == "running" ]]; then
      menu_items+=("Pause VM")
      menu_items+=("Restart")
    elif [[ "$current_state" == "paused" ]]; then
      menu_items+=("Resume VM")
    fi
    
    menu_items+=("Graceful Shutdown")
    menu_items+=("Force Stop")
    menu_items+=("Delete VM")
    menu_items+=("Clone VM")
    menu_items+=("Export VM")
    menu_items+=("📸 Quick Snapshot")
    menu_items+=("Modify RAM")
    menu_items+=("Modify CDROM")
    menu_items+=("Modify Storage")
    menu_items+=("Run Diagnostics")
    menu_items+=("← Back to VM List")
    
    action=$(gum choose --header="Actions for $vm (State: $current_state):" \
      --height=15 \
      "${menu_items[@]}" \
      || echo "← Back to VM List")
    
    case "$action" in
      "Show VM Info")
        clear
        show_vm_info "$vm" "$conn"
        gum style --foreground 8 ""
        read -p "Press Enter to continue..."
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "Pause VM")
        if gum confirm "Pause $vm?"; then
          if run_with_spinner "Pausing $vm..." virsh -c "$conn" suspend "$vm"; then
            gum style --foreground 3 "✓ VM paused."
            sleep 1
            VM_STATES[$vm_idx]="paused"
          else
            read -p "Press Enter to continue..."
          fi
        fi
        ;;
      "Resume VM")
        if gum confirm "Resume $vm?"; then
          if run_with_spinner "Resuming $vm..." virsh -c "$conn" resume "$vm"; then
            gum style --foreground 2 "✓ VM resumed."
            sleep 1
            VM_STATES[$vm_idx]="running"
          else
            read -p "Press Enter to continue..."
          fi
        fi
        ;;
      "Restart")
        if gum confirm "Restart $vm?"; then
          if run_with_spinner "Rebooting $vm..." virsh -c "$conn" reboot "$vm"; then
            gum style --foreground 2 "✓ Reboot command sent."
            sleep 1
          else
            read -p "Press Enter to continue..."
          fi
        fi
        ;;
      "Graceful Shutdown")
        if gum confirm "Gracefully shutdown $vm?"; then
          if run_with_spinner "Shutting down $vm..." virsh -c "$conn" shutdown "$vm"; then
            gum style --foreground 2 "✓ Shutdown command sent."
            sleep 1
            VM_STATES[$vm_idx]="shut off"
            break
          else
            read -p "Press Enter to continue..."
          fi
        fi
        ;;
      "Force Stop")
        if gum confirm --default=false "Force stop $vm? (This may cause data loss)"; then
          if run_with_spinner "Force stopping $vm..." virsh -c "$conn" destroy "$vm"; then
            gum style --foreground 1 "✓ VM forcefully stopped."
            sleep 1
            VM_STATES[$vm_idx]="shut off"
            break
          else
            read -p "Press Enter to continue..."
          fi
        fi
        ;;
      "Delete VM")
        gum style --foreground 1 --bold "⚠ This will permanently delete '$vm' and its storage (where managed by libvirt)."
        gum style --foreground 3 "The VM must be shut off before deletion."
        echo
        if ! gum confirm "First confirmation: Delete VM '$vm'?"; then
          continue
        fi
        if ! gum confirm --default=false "Second confirmation: Are you absolutely sure?"; then
          continue
        fi
        # Ensure VM is shut off
        del_state=$(sudo virsh -c "$conn" domstate "$vm" 2>/dev/null || echo "unknown")
        if [[ "$del_state" != "shut off" ]]; then
          if gum confirm "VM is '$del_state'. Attempt graceful shutdown before delete?"; then
            gum spin --spinner dot --title "Shutting down $vm..." -- sudo virsh -c "$conn" shutdown "$vm" || true
            gum style --foreground 2 "Waiting for VM to shut down..."
            for i in {1..60}; do
              sleep 1
              del_state=$(sudo virsh -c "$conn" domstate "$vm" 2>/dev/null || echo "unknown")
              if [[ "$del_state" == "shut off" ]]; then
                break
              fi
            done
          fi
        fi
        if [[ "$del_state" != "shut off" ]]; then
          gum style --foreground 1 "✗ VM is still '$del_state'. Delete aborted."
          read -p "Press Enter to continue..."
          continue
        fi
        echo
        # Capture attached disks for potential cleanup (only managed qcow2 under DISK_DIR)
        delete_paths=()
        while read -r target source; do
          [[ "$target" == "Target" ]] && continue
          [[ -z "$target" || -z "$source" || "$source" == "-" ]] && continue
          if [[ "$source" == $DISK_DIR/* ]] && [[ "$source" != *.iso ]]; then
            delete_paths+=("$source")
          fi
        done < <(sudo virsh -c "$conn" domblklist "$vm" 2>/dev/null | awk 'NR>2 {print $1" "$2}')
        gum style --foreground 8 "Attached disks:"
        sudo virsh -c "$conn" domblklist "$vm" 2>/dev/null || true
        echo
        if gum confirm --default=false "Final action: undefine '$vm' and remove managed storage under $DISK_DIR?"; then
          if gum spin --spinner dot --title "Deleting $vm..." -- sudo virsh -c "$conn" undefine "$vm" --nvram 2>/dev/null; then
            # Remove managed disks we captured
            if [[ ${#delete_paths[@]} -gt 0 ]]; then
              for disk_path in "${delete_paths[@]}"; do
                if sudo test -f "$disk_path"; then
                  gum spin --spinner dot --title "Removing disk $(basename "$disk_path")..." -- sudo rm -f "$disk_path" || true
                  gum style --foreground 2 "✓ Removed $disk_path"
                fi
              done
            fi
            gum style --foreground 2 "✓ VM '$vm' deleted."
            read -p "Press Enter to continue..."
            # Refresh VM list
            VM_NAMES=()
            VM_URIS=()
            VM_LABELS=()
            VM_STATES=()
            VM_SEEN=()
            append_vms "$SESSION_URI" "session"
            append_vms "$SYSTEM_URI" "system"
            break
          else
            gum style --foreground 1 "✗ Failed to delete VM. Check errors above."
            read -p "Press Enter to continue..."
          fi
        else
          gum style --foreground 3 "Delete cancelled."
          read -p "Press Enter to continue..."
        fi
        ;;
      "Clone VM")
        clone_vm "$vm" "$conn"
        # Refresh VM list after clone
        VM_NAMES=()
        VM_URIS=()
        VM_LABELS=()
        VM_STATES=()
        VM_SEEN=()
        append_vms "$SESSION_URI" "session"
        append_vms "$SYSTEM_URI" "system"
        break
        ;;
      "Modify RAM")
        clear
        gum style --bold --foreground 212 "Adjust Memory for $vm"
        gum style --foreground 3 "⚠ Requires VM to be shut off. Changing memory on a running VM may corrupt it."
        gum style --foreground 3 "⚠ Ensure the guest OS supports the new value."
        echo
        if ! gum confirm "Continue to change memory for '$vm'?"; then
          continue
        fi
        current_mem=""
        if mem_output=$(virsh -c "$conn" dommemstat "$vm" 2>/dev/null); then
          current_mem=$(echo "$mem_output" | awk '/actual/ {print $2}')
        fi
        current_mem_mb=""
        if [[ -n "$current_mem" ]]; then
          current_mem_mb=$((current_mem / 1024))
        fi
        gum style --foreground 8 "Enter the new memory size in MB (e.g., 4096 for 4GB):"
        read -p "New memory (MB) [current: ${current_mem_mb:-unknown}]: " new_mem
        # Strip any non-digits
        new_mem=$(echo "$new_mem" | tr -cd '0-9')
        if [[ -z "$new_mem" ]]; then
          gum style --foreground 1 "✗ No valid number entered. Cancelling."
          read -p "Press Enter to continue..."
          continue
        fi
        gum style --foreground 3 "This will set both maximum and current memory to ${new_mem}MB."
        if ! gum confirm --default=false "Final confirmation: apply ${new_mem}MB to '$vm'?"; then
          continue
        fi
        gum spin --spinner dot --title "Setting max memory..." -- virsh -c "$conn" setmaxmem "$vm" "${new_mem}M" --config
        result1=$?
        gum spin --spinner dot --title "Setting current memory..." -- virsh -c "$conn" setmem "$vm" "${new_mem}M" --config
        result2=$?
        if [[ $result1 -eq 0 && $result2 -eq 0 ]]; then
          gum style --foreground 2 "✓ Memory updated to ${new_mem}MB. Reboot the VM for changes to take effect."
        else
          gum style --foreground 1 "✗ Failed to update memory. Check if VM is shut off."
        fi
        read -p "Press Enter to continue..."
        ;;
      "Modify CDROM")
        modify_cdrom "$vm" "$conn"
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "Modify Storage")
        modify_storage "$vm" "$conn"
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "Export VM")
        export_vm "$vm" "$conn"
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "📸 Quick Snapshot")
        quick_snapshot "$vm" "$conn"
        read -p "Press Enter to continue..."
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "Run Diagnostics")
        clear
        run_diagnostics
        echo
        read -p "Press Enter to continue..."
        clear
        gum style --bold --foreground 212 "Selected: $vm [$label]"
        echo
        ;;
      "← Back to VM List"|*)
        break
        ;;
    esac
  done
done
