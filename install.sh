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

# --- 5. N8N INSTALLATION ---

install_n8n() {
    echo -e "\n${BLUE}📱 Setting up n8n Android Infrastructure...${NC}"
    execute "pkg update -y" "Updating packages"
    execute "pkg install -y nodejs-22 python3 autossh tmux cronie" "Installing dependencies"
    
    # Fix Node links if needed
    if [ -d "/data/data/com.termux/files/usr/opt/nodejs-22/bin" ]; then
        execute "ln -sf '$TERMUX_BIN/node' $TERMUX_BIN/node && ln -sf '$TERMUX_BIN/npm' $TERMUX_BIN/npm" "Verifying Node.js links"
    fi

    execute "npm install -g n8n" "Installing n8n globally"

    # Memory Detection & User Choice
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    RECOMMENDED_MEM=512
    [ "$TOTAL_RAM" -gt 3000 ] && RECOMMENDED_MEM=1024
    
    echo -e "\n${YELLOW}🧠 MEMORY ALLOCATION:${NC}"
    echo -e "Detected Total RAM: ${BLUE}${TOTAL_RAM}MB${NC}"
    echo -e "Recommended for your device: ${GREEN}${RECOMMENDED_MEM}MB${NC}"

    while true; do
        read -p "Enter RAM limit for n8n in MB [Default $RECOMMENDED_MEM]: " USER_MEM
        USER_MEM=${USER_MEM:-$RECOMMENDED_MEM}
        [[ "$USER_MEM" =~ ^[0-9]+$ ]] && break
        error_msg "Invalid input. Please enter a numeric value (e.g., 512)."
    done
    MEM_LIMIT=$USER_MEM

    # Create directory structure
    status_msg "Creating directories"
    mkdir -p "$HOME/n8n_server/config" "$HOME/n8n_server/scripts" "$HOME/n8n_server/python" "$HOME/.termux/boot"
    success_msg

    # Create Config (n8n.env)
    status_msg "Creating n8n configuration"
    cat <<EOF > "$HOME/n8n_server/config/n8n.env"
N8N_RUNNERS_MODE=internal
N8N_RUNNERS_AUTH_TOKEN="$(openssl rand -hex 32)"
N8N_RUNNERS_BROKER_LISTEN_ADDRESS=127.0.0.1
N8N_PYTHON_BINARY=$PREFIX/bin/python3
N8N_NATIVE_PYTHON_RUNNER=false
N8N_BLOCK_COMMAND_EXECUTION=false
N8N_NODES_INCLUDE='["n8n-nodes-base.executeCommand","n8n-nodes-base.manualTrigger"]'
NODE_OPTIONS="--max-old-space-size=$MEM_LIMIT"
N8N_PROTOCOL=http
N8N_HOST=localhost
EOF
    success_msg

    # Create Monitor Script
    status_msg "Creating monitoring script"
    cat <<'EOF' > "$HOME/n8n_server/scripts/n8n-monitor.sh"
#!/bin/bash
N8N_SESSION="n8n_server"
TUNNEL_SESSION="n8n_tunnel"
ENV_FILE=~/n8n_server/config/n8n.env
LOG_FILE=~/n8n_monitor.log

N8N_START="set -a; source $ENV_FILE; set +a; n8n start"

if ! pgrep -f "n8n start" > /dev/null; then
    echo "[$(date)] 🚀 n8n not found. Restarting..." >> "$LOG_FILE"
    tmux kill-session -t "$N8N_SESSION" 2>/dev/null
    tmux new-session -d -s "$N8N_SESSION" "$N8N_START"
fi

# Tunnel monitoring is handled if configured
if [ -f ~/n8n_server/config/tunnel.conf ]; then
    source ~/n8n_server/config/tunnel.conf
    if ! pgrep -f "autossh.*-R 5678:localhost:5678" > /dev/null; then
        echo "[$(date)] 🌐 Tunnel not found. Re-establishing..." >> "$LOG_FILE"
        tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null
        tmux new-session -d -s "$TUNNEL_SESSION" "$TUNNEL_CMD"
    fi
fi
EOF
    chmod +x "$HOME/n8n_server/scripts/n8n-monitor.sh"
    success_msg

    # Create Python Bridge
    status_msg "Creating Python bridge"
    cat <<'EOF' > "$HOME/n8n_server/python/n8n_python.py"
import sys
import json

def process(data):
    # --- YOUR LOGIC HERE ---
    if isinstance(data, list):
        for item in data:
            item['status'] = 'processed_on_termux'
    else:
        data['status'] = 'processed_on_termux'
    # -----------------------
    return data

if __name__ == '__main__':
    try:
        input_data = json.loads(sys.argv[1])
        print(json.dumps(process(input_data)))
    except Exception as e:
        print(json.dumps({'error': str(e)}))
EOF
    success_msg

    # Create Boot Script
    status_msg "Setting up auto-boot"
    cat <<EOF > "$HOME/.termux/boot/start-n8n-on-boot"
#!/bin/bash
termux-wake-lock
$HOME/n8n_server/scripts/n8n-monitor.sh
EOF
    chmod +x "$HOME/.termux/boot/start-n8n-on-boot"
    success_msg

    # Setup Cron
    status_msg "Configuring watchdog (Cron)"
    (crontab -l 2>/dev/null | grep -v "n8n-monitor.sh"; echo "*/5 * * * * $HOME/n8n_server/scripts/n8n-monitor.sh") | crontab -
    success_msg

    echo -e "\n${GREEN}✅ n8n successfully installed and automated!${NC}"
    echo -e "Use ${BLUE}Option 4${NC} to configure the GCP Tunnel Bridge."
}

# --- 6. GCP BRIDGE SETUP ---

setup_n8n_gcp() {
    echo -e "\n${BLUE}🌐 GCP BRIDGE (SSH TUNNEL) CONFIGURATION${NC}"
    echo -e "This will expose your n8n instance to the internet via a GCP VM.\n"
    
    while true; do
        read -p "Enter GCP VM Public IP: " GCP_IP
        [[ "$GCP_IP" =~ ^[0-9.]+$ ]] && break
        error_msg "Invalid IP address format."
    done

    while true; do
        read -p "Enter GCP SSH Username: " GCP_USER
        [[ "$GCP_USER" =~ ^[a-z0-9_-]+$ ]] && break
        error_msg "Invalid username format (use lowercase, numbers, underscores, or dashes)."
    done

    while true; do
        read -p "Enter your Public Domain (e.g., n8n.example.com): " GCP_DOMAIN
        [[ "$GCP_DOMAIN" =~ ^[a-z0-9.-]+$ ]] && break
        error_msg "Invalid domain format."
    done

    # Update n8n.env
    sed -i "s/N8N_PROTOCOL=http/N8N_PROTOCOL=https/g" "$HOME/n8n_server/config/n8n.env"
    sed -i "s|N8N_HOST=.*|N8N_HOST=$GCP_DOMAIN|g" "$HOME/n8n_server/config/n8n.env"

    # Create Tunnel Config
    cat <<EOF > "$HOME/n8n_server/config/tunnel.conf"
TUNNEL_CMD="autossh -M 0 -N -o \"StrictHostKeyChecking=no\" -R 5678:localhost:5678 $GCP_USER@$GCP_IP"
EOF

    echo -e "\n${YELLOW}🔑 SSH KEY SETUP:${NC}"
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        status_msg "Generating SSH key"
        ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
        success_msg
    fi

    echo -e "\n1. Copy this key to your GCP VM's ${BLUE}~/.ssh/authorized_keys${NC}:"
    cat "$HOME/.ssh/id_rsa.pub"
    echo -e "\n2. Once done, run the monitor to start the tunnel:"
    echo -e "   ${GREEN}~/n8n_server/scripts/n8n-monitor.sh${NC}"
}

# --- 7. SERVICE MANAGEMENT ---

manage_service() {
    echo -e "\n${BLUE}⚙️  BACKGROUND SERVICE MANAGEMENT${NC}"
    echo "1) OpenClaw: Enable/Setup Service"
    echo "2) OpenClaw: Disable/Remove Service"
    echo "3) n8n: Restart/Revive All"
    echo "4) Back"
    read -p "Select option [1-4]: " SVC_CHOICE

    case $SVC_CHOICE in
        1) setup_service_files ;;
        2) remove_service_files ;;
        3) "$HOME/n8n_server/scripts/n8n-monitor.sh"; echo -e "${GREEN}n8n and Tunnel restart triggered.${NC}" ;;
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

# --- 8. UNINSTALLATION LOGIC ---

uninstall_menu() {
    echo -e "\n${RED}⚠️  UNINSTALLATION MENU${NC}"
    echo "1) Remove OpenClaw only"
    echo "2) Remove Gemini CLI only"
    echo "3) Remove n8n only"
    echo "4) Full Clean (Everything)"
    echo "5) Cancel"
    read -p "Select option [1-5]: " UN_CHOICE

    case $UN_CHOICE in
        1) soft_cleanup_openclaw; echo -e "${GREEN}\nOpenClaw removed.${NC}" ;;
        2) uninstall_gemini; echo -e "${GREEN}\nGemini CLI removed.${NC}" ;;
        3) uninstall_n8n; echo -e "${GREEN}\nn8n removed.${NC}" ;;
        4) full_cleanup; echo -e "${GREEN}\nEverything cleaned.${NC}" ;;
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

uninstall_n8n() {
    echo -e "${YELLOW}Cleaning up n8n...${NC}"
    crontab -l 2>/dev/null | grep -v "n8n-monitor.sh" | crontab -
    execute "npm uninstall -g n8n" "Uninstalling n8n"
    rm -rf "$HOME/n8n_server" "$HOME/.n8n"
}

full_cleanup() {
    soft_cleanup_openclaw
    uninstall_gemini
    uninstall_n8n
    execute "pkg uninstall -y build-essential libvips openssh git jq python3 pkg-config tmux binutils termux-services ffmpeg golang nodejs-22 tur-repo clang make python autossh cronie" "Uninstalling system packages"
}

# --- 9. MAIN MENU ---

clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       🦞 OPENCLAW ANDROID TOOLKIT v$VERSION        ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "1) ${GREEN}Install/Repair${NC} OpenClaw"
echo -e "2) ${YELLOW}Install/Repair${NC} Gemini CLI"
echo -e "3) ${BLUE}Install/Repair${NC} n8n Server"
echo -e "4) ${YELLOW}Configure${NC} GCP Bridge (for n8n)"
echo -e "5) ${BLUE}Manage${NC} Background Services"
echo -e "6) ${RED}Uninstall${NC} Software"
echo -e "7) Exit"
echo -e "${BLUE}====================================================${NC}"
read -p "What would you like to do? [1-7]: " MAIN_CHOICE

check_termux

case $MAIN_CHOICE in
    1) install_openclaw ;;
    2) install_gemini_cli ;;
    3) install_n8n ;;
    4) setup_n8n_gcp ;;
    5) manage_service ;;
    6) uninstall_menu ;;
    *) exit 0 ;;
esac
