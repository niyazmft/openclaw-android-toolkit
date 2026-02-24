#!/bin/bash

# ==============================================================================
# 🦞 OPENCLAW ANDROID TOOLKIT (Termux)
# Version: 1.2.4
# Purpose: Clean installation, patching, and uninstallation of OpenClaw.
# ==============================================================================

set -e

# --- 1. COLORS & GLOBALS ---
VERSION="1.2.4"
ARCH_TYPE=$(uname -m)
GREEN=$(printf '\033[0;32m')
BLUE=$(printf '\033[0;34m')
YELLOW=$(printf '\033[1;33m')
RED=$(printf '\033[0;31m')
NC=$(printf '\033[0m')
CLEAR_LINE=$(printf '\033[K')

LOG_FILE="$HOME/openclaw_install.log"
OPENCLAW_ROOT="/data/data/com.termux/files/usr/lib/node_modules/openclaw"
SERVICE_DIR="/data/data/com.termux/files/usr/var/service/openclaw"
TERMUX_BIN="/data/data/com.termux/files/usr/bin"

# Force correct npm path for the current session
export npm_execpath="$TERMUX_BIN/npm"

# --- 2. HELPER FUNCTIONS ---

status_msg() { echo -ne "\r${CLEAR_LINE}${BLUE}==>${NC} $1... "; }
error_msg() { echo -e "\r${CLEAR_LINE}${RED}Error:${NC} $1"; }
success_msg() { echo -e "${GREEN}Done.${NC}"; }

# Execute a command with a loading spinner
execute() {
    local cmd="$1"
    local msg="$2"
    local frames='|/-\'
    
    # Start spinner in background
    (
        while true; do
            for (( i=0; i<${#frames}; i++ )); do
                printf "\r${CLEAR_LINE}${BLUE}==>${NC} %s [%s] " "$msg" "${frames:$i:1}"
                sleep 0.2
            done
        done
    ) &
    local spinner_pid=$!
    
    # Run command and capture exit code
    local exit_code=0
    eval "$cmd" >> "$LOG_FILE" 2>&1 || exit_code=$?
    
    # Stop spinner
    kill $spinner_pid 2>/dev/null || true
    wait $spinner_pid 2>/dev/null || true
    
    # Clean the line and show final status
    if [ $exit_code -eq 0 ]; then
        printf "\r${CLEAR_LINE}${BLUE}==>${NC} %s %s\n" "$msg" "${GREEN}Done.${NC}"
    else
        printf "\r${CLEAR_LINE}${BLUE}==>${NC} %s %s\n" "$msg" "${RED}Failed!${NC}"
        echo -e "\n${RED}Error details found in $LOG_FILE:${NC}"
        tail -n 10 "$LOG_FILE"
        exit 1
    fi
}

check_termux() {
    if ! command -v termux-setup-storage >/dev/null 2>&1; then
        error_msg "This script must be run inside Termux on Android."
        exit 1
    fi
}

# --- 3. INSTALLATION LOGIC ---

install_openclaw() {
    rm -f "$LOG_FILE"
    echo -e "${YELLOW}Verbose logs are being written to $LOG_FILE${NC}\n"

    # System Integrity
    rm -f /data/data/com.termux/files/usr/var/run/crond.pid

    execute "pkg update -y && pkg upgrade -y" "Updating system"
    execute "pkg install -y tur-repo build-essential libvips openssh git jq python3 pkg-config tmux binutils termux-services ffmpeg golang" "Installing dependencies"
    execute "pkg install -y nodejs-22" "Installing Node.js 22"

    # Fix isolated Node paths
    if [ -d "/data/data/com.termux/files/usr/opt/nodejs-22/bin" ]; then
        execute "ln -sf '$TERMUX_BIN/node' $TERMUX_BIN/node && ln -sf '$TERMUX_BIN/npm' $TERMUX_BIN/npm" "Verifying Node.js links"
    fi

    execute "NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm install -g openclaw@latest --unsafe-perm --ignore-scripts --silent" "Installing OpenClaw (Safe Mode)"

    apply_patches
    
    # Registry Initialization
    CONFIG_PATH="$HOME/.openclaw/openclaw.json"
    execute "openclaw doctor >> '$LOG_FILE' 2>&1 || true && if [ -f '$CONFIG_PATH' ]; then tmp_cfg=\$(mktemp); jq '.plugins.entries.telegram.enabled = true | .plugins.entries.whatsapp.enabled = true | .plugins.entries.slack.enabled = true' '$CONFIG_PATH' > \"\$tmp_cfg\" && mv \"\$tmp_cfg\" '$CONFIG_PATH'; fi" "Initializing registry"
    
    # Proactive Plugin Installation (Try to fix the 'not available' bug early)
    # We do this after core patching so the installer uses the correct npm paths
    execute "openclaw plugins install telegram whatsapp slack || true" "Pre-installing channel plugins"
    
    # Second Patch Pass (Ensure newly installed plugins are also patched)
    apply_patches "silent"
    
    execute "openclaw plugins list" "Warming up plugin engine"
    
    echo -e "\n${GREEN}✅ OpenClaw successfully installed and patched!${NC}"
    echo -e "\n${YELLOW}⚠️  NEXT STEPS:${NC}"
    echo -e "1. Run ${GREEN}openclaw onboard${NC} to configure your API keys."
    echo -e "2. Run this script again and choose ${BLUE}Option 2${NC} if you want background service."
    echo -e "\n${RED}🛑 DO NOT USE 'openclaw update'${NC}"
    echo -e "   This will break patches. Use Option 1 of this script to update."
}

apply_patches() {
    local silent=$1
    [[ "$silent" != "silent" ]] && echo -e "\n${BLUE}🩹 Applying Android compatibility patches:${NC}"

    # 1. Koffi Patch (Only on system root)
    KOFFI_SRC="$OPENCLAW_ROOT/node_modules/koffi/lib/native/base/base.cc"
    if [ -f "$KOFFI_SRC" ] && [[ "$silent" != "silent" ]]; then
        execute "sed -i 's/renameat2(AT_FDCWD, src_filename, AT_FDCWD, dest_filename, RENAME_NOREPLACE)/rename(src_filename, dest_filename)/g' '$KOFFI_SRC'" "Patching Koffi native library"
        execute "cd $OPENCLAW_ROOT/node_modules/koffi && JOBS=1 MAKEFLAGS='-j1' node src/cnoke/cnoke.js -p . -d src/koffi --prebuild" "Rebuilding Koffi"
        
        K_TRIPLET="android_armsf"
        [[ "$ARCH_TYPE" == "aarch64" ]] && K_TRIPLET="android_arm64"
        execute "mkdir -p '$K_TRIPLET' && cp 'build/koffi/$K_TRIPLET/koffi.node' '$K_TRIPLET/'" "Mapping Koffi binary"
    fi

    # 2. Path Redirection (Core + Home)
    local msg="Redirecting temporary paths"
    [[ "$silent" == "silent" ]] && msg="Patching plugin paths"
    execute "mkdir -p '$HOME/.openclaw/tmp' && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/tmp/openclaw|$HOME/.openclaw/tmp|g' {} + 2>/dev/null || true" "$msg"

    # 3. NPM & Node Path Fix (Core + Home - Aggressive)
    msg="Fixing hardcoded system paths"
    [[ "$silent" == "silent" ]] && msg="Finalizing environment paths"
    execute "find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/usr/bin/npm|$TERMUX_BIN/npm|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/bin/npm|$TERMUX_BIN/npm|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/usr/bin/node|$TERMUX_BIN/node|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/bin/node|$TERMUX_BIN/node|g' {} + 2>/dev/null || true" "$msg"
}

# --- 4. SERVICE MANAGEMENT ---

manage_service() {
    echo -e "\n${BLUE}⚙️  BACKGROUND SERVICE MANAGEMENT${NC}"
    echo "1) Enable/Setup Service"
    echo "2) Disable/Remove Service"
    echo "3) Back"
    read -p "Select option [1-3]: " SVC_CHOICE

    case $SVC_CHOICE in
        1) setup_service_files ;;
        2) remove_service_files ;;
        *) return ;;
    esac
}

setup_service_files() {
    if [ ! -f "$TERMUX_BIN/openclaw" ]; then
        error_msg "OpenClaw is not installed. Please run Option 1 first."
        return
    fi

    execute "mkdir -p '$SERVICE_DIR/log' && echo -ne '#!/bin/bash\nexport PATH=\$PATH\nexport npm_execpath=$TERMUX_BIN/npm\nexport NODE_PATH=$TERMUX_BIN/node\nexec openclaw gateway run 2>&1' > '$SERVICE_DIR/run' && echo -ne '#!/bin/bash\nexec svlogd -tt $HOME/.openclaw/logs' > '$SERVICE_DIR/log/run' && chmod +x '$SERVICE_DIR/run' '$SERVICE_DIR/log/run' && mkdir -p '$HOME/.openclaw/logs'" "Creating service files"
    
    echo -e "${GREEN}\nService configured successfully!${NC}"
    echo -e "Manage with: ${GREEN}sv up openclaw${NC} | ${RED}sv down openclaw${NC}"
}

remove_service_files() {
    execute "sv down /data/data/com.termux/files/usr/var/service/openclaw 2>/dev/null || true" "Stopping service"
    execute "rm -rf '$SERVICE_DIR'" "Removing configuration"
    echo -e "${GREEN}Background service configuration removed.${NC}"
}

# --- 5. UNINSTALLATION LOGIC ---

uninstall_openclaw() {
    echo -e "\n${RED}⚠️  UNINSTALLATION MENU${NC}"
    echo "1) Remove OpenClaw only (Keep Node.js/Go/FFmpeg)"
    echo "2) Full Clean (Remove OpenClaw AND all installed packages)"
    echo "3) Cancel"
    read -p "Select option [1-3]: " UN_CHOICE

    case $UN_CHOICE in
        1) soft_cleanup; echo -e "${GREEN}\nOpenClaw removed. Dependencies were kept.${NC}" ;;
        2) full_cleanup; echo -e "${GREEN}\nTermux environment cleaned.${NC}" ;;
        *) echo -e "${BLUE}Uninstallation cancelled.${NC}\n" ;;
    esac
}

soft_cleanup() {
    echo -e "${YELLOW}Cleaning up OpenClaw...${NC}"
    remove_service_files

    if [ -f "$TERMUX_BIN/npm" ]; then
        execute "\"$TERMUX_BIN/npm\" uninstall -g openclaw" "Uninstalling OpenClaw"
    else
        execute "npm uninstall -g openclaw" "Uninstalling OpenClaw"
    fi

    execute "rm -rf '$HOME/.openclaw'" "Cleaning local data"
}

full_cleanup() {
    soft_cleanup
    execute "pkg uninstall -y build-essential libvips openssh git jq python3 pkg-config tmux binutils termux-services ffmpeg golang nodejs-22 tur-repo" "Uninstalling system packages"
}

# --- 6. MAIN MENU ---

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       🦞 OPENCLAW ANDROID TOOLKIT v$VERSION        ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "1) ${GREEN}Install/Repair${NC} OpenClaw"
echo -e "2) ${BLUE}Manage${NC} Background Service"
echo -e "3) ${RED}Uninstall${NC} OpenClaw"
echo -e "4) Exit"
echo -e "${BLUE}====================================================${NC}"
read -p "What would you like to do? [1-4]: " MAIN_CHOICE

check_termux

case $MAIN_CHOICE in
    1) install_openclaw ;;
    2) manage_service ;;
    3) uninstall_openclaw ;;
    *) exit 0 ;;
esac
