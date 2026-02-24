# 🦞 OpenClaw Android: Installation & Patching Workspace

This workspace is dedicated to maintaining the `install.sh` script and associated documentation for running OpenClaw and Gemini CLI on Android (Termux).

## 🎯 Project Goal
Provide a "one-click" reliable installation process for OpenClaw and Gemini CLI on non-rooted Android devices, bypassing kernel restrictions and path limitations. Tested on `armv8l` and `aarch64` architectures (Android 9+).

## 🛠 Core Components
- `install.sh`: The main automation script (v1.3.0).
- `README.md`: Combined documentation for quick start, management, and technical overview.
- `.gitignore`: Standard exclusion list for Android/Termux development.

## 📜 Key Workflows

### 1. Installation Workflow
The script (`install.sh`) provides an interactive menu:
- **Install/Repair OpenClaw**: Updates packages, installs Node.js/Go/FFmpeg, applies kernel/path patches, and auto-initializes the plugin registry.
- **Install/Repair Gemini CLI**: Dedicated setup for `@google/gemini-cli` with automated NDK environment configuration.
- **Manage Background Service**: Dedicated sub-menu to enable/setup or disable/remove the `termux-services` configuration independently.
- **Uninstall**: Modular menu to remove OpenClaw, Gemini CLI, or perform a full environment wipe.

### 2. Maintenance & Updating
- **Update Policy**: Built-in update commands are forbidden as they break Android-specific patches.
- **Safe Update**: Re-running the `install.sh` "Install/Repair" options is the only supported upgrade path.
- **Path Enforcement**: Explicitly injects the Termux binary path into `openclaw.json` to ensure Skill installation (via NPM) works correctly.

### 3. Patching Logic
- **Koffi Kernel Patch**: Replaces `renameat2` with `rename` to prevent crashes on Android kernels.
- **Aggressive Path Redirection**: Patches compiled JS files to use `$HOME/.openclaw/tmp` instead of `/tmp/openclaw` and redirects `/bin/npm` / `/bin/node` to Termux paths.

## 📂 File Map
- `install.sh`: Automated bash installer.
- `README.md`: Unified documentation for users and developers.
- `GEMINI.md`: Internal context for AI-assisted development.
- `.gitignore`: Git configuration.
