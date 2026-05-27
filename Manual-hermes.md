# ⚕️ Hermes & Lali Manual

This document contains the setup details, start commands, and update procedures for your integrated Hermes Agent environment.

## 🚀 Quick Start Commands

### 1. Hermes Workspace (Web UI)
To launch the visual workspace:
```bash
cd ~/Hermes/hermes-workspace && pnpm dev
```
- **URL**: [http://localhost:3000](http://localhost:3000)
- **Note**: The backend gateway service starts automatically on boot.

### 2. Hermes Terminal Mode
To chat directly in the terminal:
- **Classic**: `hermes`
- **Modern TUI**: `hermes --tui`

### 3. Hermes Dashboard
If the workspace reports missing APIs (Sessions, Config, etc.):
```bash
hermes dashboard --no-open
```

---

## 🛠️ Update Procedures

### Update Hermes Agent
```bash
hermes update
sudo hermes gateway restart --system
```

### Update Hermes Workspace
```bash
cd ~/Hermes/hermes-workspace
git pull
pnpm install
```

---

## 🧠 Strategic Mandates (Lali Persona)

### Task Hierarchy
1. **Chat & General Inquiries**: Handled by **Nvidia Nemotron 120B**.
2. **Coding & Documentation**: **BYPASS** to Gemini CLI via terminal tool.
3. **Fallback**: If Gemini CLI cannot perform the task, use the default LLM.

### Gemini CLI Usage
- **Command**: `gemini --prompt "task description"`
- **Why**: High-context coding, multi-file refactoring, and project-wide analysis.

---

## ⚙️ Backend Configuration
- **API URL**: `http://127.0.0.1:8642`
- **API Token**: `hermes-key-123`
- **Config File**: `~/.hermes/config.yaml`
- **Env Secrets**: `~/.hermes/.env`

---
*Created on: Tuesday, April 21, 2026*
