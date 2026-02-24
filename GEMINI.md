# 🦞 OpenClaw Android: Installation & Patching Workspace

This workspace is dedicated to maintaining the `install.sh` script and associated documentation for running OpenClaw on Android (Termux).

## 🎯 Project Goal
Provide a "one-click" reliable installation process for OpenClaw on non-rooted Android devices, bypassing kernel restrictions and path limitations. Tested on `armv8l` and `aarch64` architectures (Android 9+).

## 🛠 Core Components
- `install.sh`: The main automation script (v1.2.5).
- `README.md`: Combined documentation for quick start, management, and technical overview.
- `.gitignore`: Standard exclusion list for Android/Termux development.

## 📜 Key Workflows

### 1. Installation Workflow
The script (`install.sh`) provides an interactive menu:
- **Install/Repair**: Updates packages, installs Node.js/Go/FFmpeg, applies kernel/path patches, and auto-initializes the plugin registry.
- **Manage Background Service**: Dedicated sub-menu to enable/setup or disable/remove the `termux-services` configuration independently.
- **Uninstall**:
    - **Soft**: Removes OpenClaw and its service config but leaves the development environment intact.
    - **Full**: Wipes OpenClaw and all installed dependencies for a clean Termux state.

### 2. Maintenance & Updating
- **Update Policy**: Built-in `openclaw update` is forbidden as it breaks Android-specific patches.
- **Safe Update**: Re-running the `install.sh` "Install/Repair" option is the only supported upgrade path.
- **Path Enforcement**: Explicitly injects the Termux binary path into `openclaw.json` to ensure Skill installation (via NPM) works correctly.
- **System Integrity**: Automatically clears stale `crond.pid` locks to ensure background process stability.

### 3. Patching Logic
- **Koffi Kernel Patch**: Replaces `renameat2` with `rename` to prevent crashes on Android kernels.
- **Aggressive Path Redirection**: Patches compiled JS files to use `$HOME/.openclaw/tmp` instead of `/tmp/openclaw` and redirects `/bin/npm` / `/bin/node` to Termux paths across all core and user modules.

## 📂 File Map
- `install.sh`: Automated bash installer.
- `README.md`: Unified documentation for users and developers.
- `GEMINI.md`: Internal context for AI-assisted development.
- `.gitignore`: Git configuration.
