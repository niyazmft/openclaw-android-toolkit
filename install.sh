#!/bin/bash

# ==============================================================================
# 🦞 OPENCLAW ANDROID TOOLKIT (Termux)
# Version: 1.3.0
# Purpose: Clean installation, patching, and uninstallation of OpenClaw & Gemini.
# ==============================================================================

set -e

# --- 1. COLORS & GLOBALS ---
VERSION="1.3.0"
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

# --- 3. OPENCLAW INSTALLATION ---

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
    
    # Registry & Environment Initialization
    CONFIG_PATH="$HOME/.openclaw/openclaw.json"
    status_msg "Initializing environment"
    # Ensure workspace structure exists to prevent tool errors
    mkdir -p "$HOME/.openclaw/workspace/memory"
    mkdir -p "$HOME/.openclaw/workspace/skills"
    
    openclaw doctor >> "$LOG_FILE" 2>&1 || true
    if [ -f "$CONFIG_PATH" ]; then
        tmp_cfg=$(mktemp)
        jq '.plugins.entries.telegram.enabled = true | 
            .plugins.entries.whatsapp.enabled = true | 
            .plugins.entries.slack.enabled = true |
            .env.PATH = "/data/data/com.termux/files/usr/bin:/bin"' "$CONFIG_PATH" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_PATH"
    fi
    success_msg
    
    execute "openclaw plugins install telegram whatsapp slack || true" "Pre-installing channel plugins"
    apply_patches "silent"
    execute "openclaw plugins list" "Warming up plugin engine"
    
    echo -e "\n${GREEN}✅ OpenClaw successfully installed and patched!${NC}"
    echo -e "\n${YELLOW}⚠️  NEXT STEPS:${NC}"
    echo -e "1. Run ${GREEN}openclaw onboard${NC} to configure your API keys."
    echo -e "2. Use ${BLUE}Option 3${NC} in this script to configure background service."
    echo -e "\n${RED}🛑 DO NOT USE 'openclaw update'${NC}"
    echo -e "   This will break patches. Use Option 1 of this script to update."
}

apply_patches() {
    local silent=$1
    [[ "$silent" != "silent" ]] && echo -e "\n${BLUE}🩹 Applying Android compatibility patches:${NC}"

    # 1. Koffi Patch
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

    # 3. NPM & Node Path Fix (Aggressive)
    msg="Fixing hardcoded system paths"
    [[ "$silent" == "silent" ]] && msg="Finalizing environment paths"
    execute "find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/usr/bin/npm|$TERMUX_BIN/npm|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/bin/npm|$TERMUX_BIN/npm|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/usr/bin/node|$TERMUX_BIN/node|g' {} + 2>/dev/null && find '$OPENCLAW_ROOT' '$HOME/.openclaw' -type f -name '*.js' -exec sed -i 's|/bin/node|$TERMUX_BIN/node|g' {} + 2>/dev/null || true" "$msg"
}

# --- 4. GEMINI CLI INSTALLATION ---

install_gemini_cli() {
    echo -e "\n${BLUE}✨ Setting up Gemini CLI...${NC}"
    execute "pkg update -y" "Updating packages"
    execute "pkg install -y python make clang pkg-config" "Installing build tools"
    
    status_msg "Setting NDK environment"
    export npm_config_android_ndk_path=$PREFIX
    export ANDROID_NDK_HOME=$PREFIX
    export ANDROID_NDK_ROOT=$PREFIX
    success_msg

    execute "npm i -g @google/gemini-cli" "Installing @google/gemini-cli"
    
    if command -v gemini >/dev/null 2>&1 || command -v gemini-cli >/dev/null 2>&1; then
        echo -e "${GREEN}\nGemini CLI successfully installed!${NC}"
        echo -e "You can now run: ${BLUE}gemini --help${NC}"
    else
        error_msg "Installation finished but 'gemini' command not found in PATH."
    fi
}

# --- 5. SERVICE MANAGEMENT ---

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

# --- 6. UNINSTALLATION LOGIC ---

uninstall_menu() {
    echo -e "\n${RED}⚠️  UNINSTALLATION MENU${NC}"
    echo "1) Remove OpenClaw only"
    echo "2) Remove Gemini CLI only"
    echo "3) Full Clean (Everything)"
    echo "4) Cancel"
    read -p "Select option [1-4]: " UN_CHOICE

    case $UN_CHOICE in
        1) soft_cleanup_openclaw; echo -e "${GREEN}\nOpenClaw removed.${NC}" ;;
        2) uninstall_gemini; echo -e "${GREEN}\nGemini CLI removed.${NC}" ;;
        3) full_cleanup; echo -e "${GREEN}\nEverything cleaned.${NC}" ;;
        *) echo -e "${BLUE}Uninstallation cancelled.${NC}\n" ;;
    esac
}

soft_cleanup_openclaw() {
    echo -e "${YELLOW}Cleaning up OpenClaw...${NC}"
    remove_service_files
    if [ -f "$TERMUX_BIN/npm" ]; then
        execute "\"$TERMUX_BIN/npm\" uninstall -g openclaw" "Uninstalling OpenClaw"
    else
        execute "npm uninstall -g openclaw" "Uninstalling OpenClaw"
    fi
    rm -rf "$HOME/.openclaw"
}

uninstall_gemini() {
    execute "npm uninstall -g @google/gemini-cli" "Uninstalling Gemini CLI"
}

full_cleanup() {
    soft_cleanup_openclaw
    uninstall_gemini
    execute "pkg uninstall -y build-essential libvips openssh git jq python3 pkg-config tmux binutils termux-services ffmpeg golang nodejs-22 tur-repo clang make python" "Uninstalling system packages"
}

# --- 7. MAIN MENU ---

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       🦞 OPENCLAW ANDROID TOOLKIT v$VERSION        ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "1) ${GREEN}Install/Repair${NC} OpenClaw"
echo -e "2) ${YELLOW}Install/Repair${NC} Gemini CLI"
echo -e "3) ${BLUE}Manage${NC} Background Service"
echo -e "4) ${RED}Uninstall${NC} Software"
echo -e "5) Exit"
echo -e "${BLUE}====================================================${NC}"
read -p "What would you like to do? [1-5]: " MAIN_CHOICE

check_termux

case $MAIN_CHOICE in
    1) install_openclaw ;;
    2) install_gemini_cli ;;
    3) manage_service ;;
    4) uninstall_menu ;;
    *) exit 0 ;;
esac
