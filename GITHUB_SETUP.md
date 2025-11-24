# GitHub Setup Guide

This guide will help you upload the Branch Miner to GitHub and use it in ComputerCraft.

## Step 1: Upload to GitHub

### Option A: GitHub Web Interface (Easiest)

1. **Create repository:**
   - Go to https://github.com
   - Click **+** → **New repository**
   - Name: `computercraft-branch-miner`
   - Description: `Advanced branch mining system for ComputerCraft`
   - Make it **Public**
   - Click **Create repository**

2. **Upload files:**
   - Click **Add file** → **Upload files**
   - Drag all files from `branch-miner/` folder:
     - `config.lua`
     - `protocol.lua`
     - `state.lua`
     - `utils.lua`
     - `coordinator.lua`
     - `miner.lua`
     - `control.lua`
     - `installer.lua`
     - `bootstrap.lua`
     - `README.md`
     - `QUICKSTART.md`
     - `.gitignore`
   - Commit message: `Initial commit - Branch Miner v1.0`
   - Click **Commit changes**

### Option B: Git Command Line

```bash
cd "C:\Users\Onlin\OneDrive\Documents\CCraft\branch-miner"

git init
git add .
git commit -m "Initial commit - Branch Miner v1.0"

# Replace YOUR-USERNAME with your GitHub username
git remote add origin https://github.com/YOUR-USERNAME/computercraft-branch-miner.git
git branch -M main
git push -u origin main
```

## Step 2: Update URLs

After uploading, update these files with your GitHub username:

### installer.lua (line 11)
```lua
local GITHUB_BASE = "https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/"
```

### bootstrap.lua (line 4)
```lua
local GITHUB_URL = "https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/installer.lua"
```

**Don't forget to commit these changes!**

## Step 3: Upload Bootstrap to Pastebin

1. Copy the contents of `bootstrap.lua`
2. Go to https://pastebin.com
3. Paste the content
4. Click **Create New Paste**
5. Note the code (e.g., `aBcD1234`)

## Step 4: Use in ComputerCraft

Now you have **three ways** to install:

### Method 1: One-Command Install (Easiest)
```lua
pastebin run aBcD1234
```
This downloads and runs the bootstrap, which downloads everything else!

### Method 2: Manual Installer Download
```lua
-- Download installer
pastebin get aBcD1234 bootstrap.lua
bootstrap.lua

-- Or download installer directly
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/installer.lua installer.lua
installer.lua
```

### Method 3: Download Specific Files
```lua
-- Download just what you need for a turtle
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/config.lua config.lua
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/protocol.lua protocol.lua
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/state.lua state.lua
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/utils.lua utils.lua
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/coordinator.lua coordinator.lua
wget https://raw.githubusercontent.com/YOUR-USERNAME/computercraft-branch-miner/main/miner.lua miner.lua
```

## Full Workflow Example

### You (on your computer):
1. Create GitHub repo: `computercraft-branch-miner`
2. Upload all files from `branch-miner/` folder
3. Update `installer.lua` line 11 with your username
4. Update `bootstrap.lua` line 4 with your username
5. Commit the changes
6. Upload `bootstrap.lua` to Pastebin → Get code `aBcD1234`

### In-game (on turtle):
```lua
pastebin run aBcD1234
```

The bootstrap downloads the installer, which then downloads all the other files!

## Troubleshooting

**"Download failed"**
- Check repository is Public
- Verify GitHub username in URLs
- Make sure files are in repository root, not a subfolder

**"HTTP is not enabled"**
- Edit `mods/computercraft-common.toml`
- Set `enabled = true` under `[http]`

**"pastebin not found"**
- ComputerCraft might have pastebin disabled
- Use `wget` method instead

## Sharing Your Project

Once set up, anyone can install with:
```lua
pastebin run aBcD1234
```

Add this to your GitHub README for easy sharing!

## Repository Structure

```
computercraft-branch-miner/
├── config.lua          - Configuration
├── protocol.lua        - Network protocol
├── state.lua           - State management
├── utils.lua           - Utilities
├── coordinator.lua     - Work coordination
├── miner.lua          - Turtle program
├── control.lua        - Pocket computer controller
├── installer.lua      - Installation wizard
├── bootstrap.lua      - One-command installer
├── README.md          - Full documentation
├── QUICKSTART.md      - Quick start guide
├── GITHUB_SETUP.md    - This file
└── .gitignore         - Git ignore rules
```

## Next Steps

1. Test the installation in-game
2. Update README.md with your pastebin code
3. Add screenshots/videos to GitHub
4. Share with the ComputerCraft community!

