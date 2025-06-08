# Linux User Management

Interactive bash scripts for managing Linux users.

## Features

- List users with status
- Add new users 
- Reset passwords
- View user details
- Delete users
- Lock/unlock accounts

## Scripts

- **usr-mgmt.sh** - Standalone version (no dependencies)
- **usr-mgmt-gum.sh** - Enhanced version (requires [gum](https://github.com/charmbracelet/gum))

## Usage

### Clone repo
```bash
git clone https://github.com/S4M8/mw-user-management.git
```

### Make script executable
```bash
chmod +x usr-mgmt*.sh
```

### Run standalone version
```bash
sudo bash ./usr-mgmt.sh
```

### Run tui version ([install gum](https://github.com/charmbracelet/gum?tab=readme-ov-file#installation) first)
```bash
sudo bash ./usr-mgmt-gum.sh
```
