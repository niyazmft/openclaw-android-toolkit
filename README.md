# 🦞 OpenClaw Android (Termux) Toolkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/niyazmft/openclaw-android-toolkit)
[![Platform](https://img.shields.io/badge/Platform-Android%20(Termux)-green.svg)](https://termux.dev/)

A high-performance, automated toolkit for running [OpenClaw](https://github.com/the-claw-team/openclaw) and [Gemini CLI](https://github.com/google/gemini-cli) natively on non-rooted Android devices. This toolkit bypasses kernel restrictions (`renameat2`), patches hardcoded system paths, and optimizes AI execution for mobile environments.

---

## 📱 Compatibility

- **OS**: Android 9.0 and above.
- **Architecture**: Tested on `armv8l` (32-bit) and `aarch64` (64-bit) CPUs.
- **Environment**: Termux (Native, no proot required).

---

## 🚀 Quick Start

### 1. Environment Setup
Install **Termux** from [F-Droid](https://f-droid.org/en/packages/com.termux/). Do **not** use the Play Store version as it is obsolete.

### 2. Run the Toolkit
Execute the following command to start the interactive toolkit:
```bash
curl -sSL https://raw.githubusercontent.com/niyazmft/openclaw-android-toolkit/main/install.sh | bash
```
> 💡 **Note:** Select **Option 1** for OpenClaw or **Option 2** for Gemini CLI.

### 3. Onboard (For OpenClaw)
Initialize your account and API providers:
```bash
openclaw onboard
```
*Select **Manual Mode** and choose an external provider (OpenRouter, OpenAI, etc.).*

---

## ✨ Key Features

- 🛠 **Zero-Config Patching**: Automatically fixes the `koffi` native bridge and `renameat2` kernel crashes.
- 📂 **Path Awareness**: Aggressively redirects `/bin/npm`, `/bin/node`, and `/tmp` to Termux-compatible directories.
- 🔌 **Plugin Ready**: Auto-initializes and patches Telegram, WhatsApp, and Slack plugins during setup.
- 🧩 **Gemini CLI Support**: Dedicated installer for `@google/gemini-cli` with NDK environment optimizations.
- 🔋 **Battery Efficient**: Optimized for external API usage to prevent mobile CPU throttling.
- 🧼 **Clean Management**: Includes a modular uninstaller with specific cleanup options for each tool.

---

## 📊 Management Commands

| Action | Command |
| :--- | :--- |
| **Check Health** | `sv status openclaw` |
| **View Live Logs** | `tail -f ~/.openclaw/logs/current` |
| **Stop Service** | `sv down openclaw` |
| **Restart Gateway** | `sv restart openclaw` |
| **Force Kill (Stray)** | `pkill -9 -f openclaw` |
| **Fix Environment** | `openclaw doctor` |
| **Find Access Token** | `grep "token" ~/.openclaw/openclaw.json` |

---

## 🔄 Maintenance

### 🛡 Safe Updates
**⚠️ WARNING:** Never use the built-in `openclaw update` command. It will overwrite the Android patches and break the application.

To update safely:
1. Run the `install.sh` script.
2. Choose **Option 1 (Install/Repair)**. 
The toolkit will fetch the latest version and re-apply all necessary patches automatically.

### 🔋 Battery Optimization
To prevent Android from killing the background process, run:
```bash
termux-wake-lock
```

---

## 🛠 Troubleshooting

- **Telegram Plugin Not Available**: This toolkit attempts to pre-fix this. If it persists, finish onboarding and run: `openclaw channels add --channel telegram`.
- **Homebrew Recommendations**: **Ignore them.** Homebrew is not supported on Android. Use `pkg install <package>` for any missing dependencies.
- **Node.js Errors**: Run the toolkit's **Install/Repair** option to reset environment locks and paths.

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.
