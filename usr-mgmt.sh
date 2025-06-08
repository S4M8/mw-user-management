#!/bin/bash

# Self-Contained User Management Script
# No external dependencies required
# Usage: sudo ./user_mgmt.sh

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}${BOLD}Error: This script must be run as root (use sudo)${NC}"
        exit 1
    fi
}

# Display header
show_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "=================================================="
    echo "           USER MANAGEMENT TOOL"
    echo "=================================================="
    echo -e "${NC}"
}

# List all regular users
list_users() {
    echo -e "${CYAN}${BOLD}Regular Users (UID >= 1000):${NC}"
    echo ""
    printf "%-15s %-6s %-20s %s\n" "USERNAME" "UID" "FULL NAME" "STATUS"
    echo "-----------------------------------------------"
    
    awk -F: '$3 >= 1000 && $3 != 65534 {print $1, $3, $5}' /etc/passwd | while read -r username uid fullname; do
        # Check account status
        status="Active"
        if passwd -S "$username" 2>/dev/null | grep -q " L "; then
            status="Locked"
        elif passwd -S "$username" 2>/dev/null | grep -q " NP "; then
            status="No Password"
        fi
        printf "%-15s %-6s %-20s %s\n" "$username" "$uid" "${fullname:-N/A}" "$status"
    done
    echo ""
}

# Add new user function
add_user() {
    echo -e "${YELLOW}${BOLD}ADD NEW USER${NC}"
    echo ""
    
    # Get username
    echo -n "Enter username: "
    read -r username
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username cannot be empty${NC}"
        return 1
    fi
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo -e "${RED}Error: User '$username' already exists${NC}"
        return 1
    fi
    
    # Get full name
    echo -n "Enter full name (optional): "
    read -r fullname
    
    # Password options
    echo ""
    echo "Password options:"
    echo "1) Generate random password"
    echo "2) Set custom password"
    echo "3) No password (locked account)"
    echo -n "Choose option (1-3): "
    read -r pwd_choice
    
    password=""
    case "$pwd_choice" in
        1)
            password=$(openssl rand -base64 12 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
            ;;
        2)
            echo -n "Enter password: "
            read -r -s password
            echo ""
            if [ -z "$password" ]; then
                echo -e "${RED}Error: Password cannot be empty${NC}"
                return 1
            fi
            ;;
        3)
            password=""
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac
    
    # Home directory
    echo -n "Create home directory? (y/N): "
    read -r create_home
    
    # Shell selection
    echo ""
    echo "Shell options:"
    echo "1) /bin/bash"
    echo "2) /bin/sh"
    echo "3) /bin/zsh"
    echo "4) /usr/bin/fish"
    echo -n "Choose shell (1-4): "
    read -r shell_choice
    
    case "$shell_choice" in
        1) shell="/bin/bash" ;;
        2) shell="/bin/sh" ;;
        3) shell="/bin/zsh" ;;
        4) shell="/usr/bin/fish" ;;
        *) shell="/bin/bash" ;;
    esac
    
    # Confirmation
    echo ""
    echo -e "${YELLOW}User Details:${NC}"
    echo "Username: $username"
    echo "Full Name: ${fullname:-Not specified}"
    echo "Password: ${password:-None (locked)}"
    echo "Home Directory: ${create_home:-No}"
    echo "Shell: $shell"
    echo ""
    echo -n "Create this user? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}User creation cancelled${NC}"
        return 1
    fi
    
    # Create user
    cmd="useradd -s $shell"
    if [[ "$create_home" =~ ^[Yy]$ ]]; then
        cmd="$cmd -m"
    fi
    if [ -n "$fullname" ]; then
        cmd="$cmd -c \"$fullname\""
    fi
    cmd="$cmd $username"
    
    if eval "$cmd"; then
        echo -e "${GREEN}✓ User '$username' created successfully${NC}"
        
        # Set password
        if [ -n "$password" ]; then
            echo "$username:$password" | chpasswd
            if [ "$pwd_choice" = "1" ]; then
                echo -e "${YELLOW}Generated password: $password${NC}"
                echo -e "${YELLOW}Save this password securely!${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Failed to create user${NC}"
        return 1
    fi
}

# Reset password function
reset_password() {
    echo -e "${YELLOW}${BOLD}RESET USER PASSWORD${NC}"
    echo ""
    
    # Show users and get selection
    echo "Available users:"
    users=($(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd))
    
    if [ ${#users[@]} -eq 0 ]; then
        echo -e "${RED}No regular users found${NC}"
        return 1
    fi
    
    for i in "${!users[@]}"; do
        echo "$((i+1))) ${users[i]}"
    done
    
    echo -n "Select user (1-${#users[@]}): "
    read -r user_choice
    
    if [[ ! "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#users[@]} ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    selected_user="${users[$((user_choice-1))]}"
    
    # Password reset options
    echo ""
    echo "Password reset options for '$selected_user':"
    echo "1) Generate random password"
    echo "2) Set custom password"
    echo "3) Lock account"
    echo "4) Unlock account"
    echo -n "Choose option (1-4): "
    read -r reset_choice
    
    case "$reset_choice" in
        1)
            new_password=$(openssl rand -base64 12 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
            echo "$selected_user:$new_password" | chpasswd
            echo -e "${GREEN}✓ Password reset for '$selected_user'${NC}"
            echo -e "${YELLOW}New password: $new_password${NC}"
            
            echo -n "Force password change on next login? (y/N): "
            read -r force_change
            if [[ "$force_change" =~ ^[Yy]$ ]]; then
                passwd -e "$selected_user" 2>/dev/null || chage -d 0 "$selected_user"
            fi
            ;;
        2)
            echo -n "Enter new password: "
            read -r -s new_password
            echo ""
            if [ -z "$new_password" ]; then
                echo -e "${RED}Password cannot be empty${NC}"
                return 1
            fi
            echo "$selected_user:$new_password" | chpasswd
            echo -e "${GREEN}✓ Password reset for '$selected_user'${NC}"
            
            echo -n "Force password change on next login? (y/N): "
            read -r force_change
            if [[ "$force_change" =~ ^[Yy]$ ]]; then
                passwd -e "$selected_user" 2>/dev/null || chage -d 0 "$selected_user"
            fi
            ;;
        3)
            passwd -l "$selected_user"
            echo -e "${GREEN}✓ Account '$selected_user' locked${NC}"
            ;;
        4)
            passwd -u "$selected_user"
            echo -e "${GREEN}✓ Account '$selected_user' unlocked${NC}"
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac
}

# Delete user function
delete_user() {
    echo -e "${YELLOW}${BOLD}DELETE USER${NC}"
    echo ""
    
    # Show users and get selection
    echo "Available users:"
    users=($(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd))
    
    if [ ${#users[@]} -eq 0 ]; then
        echo -e "${RED}No regular users found${NC}"
        return 1
    fi
    
    for i in "${!users[@]}"; do
        echo "$((i+1))) ${users[i]}"
    done
    
    echo -n "Select user to delete (1-${#users[@]}): "
    read -r user_choice
    
    if [[ ! "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#users[@]} ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    selected_user="${users[$((user_choice-1))]}"
    
    # Show user info
    echo ""
    echo -e "${BLUE}User to delete:${NC}"
    id "$selected_user"
    
    echo ""
    echo -e "${RED}${BOLD}⚠ WARNING: This action cannot be undone!${NC}"
    echo -n "Remove home directory too? (y/N): "
    read -r remove_home
    
    echo -n "Are you sure you want to delete '$selected_user'? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}User deletion cancelled${NC}"
        return 1
    fi
    
    # Delete user
    cmd="userdel"
    if [[ "$remove_home" =~ ^[Yy]$ ]]; then
        cmd="$cmd -r"
    fi
    cmd="$cmd $selected_user"
    
    if eval "$cmd"; then
        echo -e "${GREEN}✓ User '$selected_user' deleted successfully${NC}"
    else
        echo -e "${RED}✗ Failed to delete user${NC}"
        return 1
    fi
}

# Show user details
show_user_details() {
    echo -e "${YELLOW}${BOLD}USER DETAILS${NC}"
    echo ""
    
    # Show users and get selection
    echo "Available users:"
    users=($(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd))
    
    if [ ${#users[@]} -eq 0 ]; then
        echo -e "${RED}No regular users found${NC}"
        return 1
    fi
    
    for i in "${!users[@]}"; do
        echo "$((i+1))) ${users[i]}"
    done
    
    echo -n "Select user (1-${#users[@]}): "
    read -r user_choice
    
    if [[ ! "$user_choice" =~ ^[0-9]+$ ]] || [ "$user_choice" -lt 1 ] || [ "$user_choice" -gt ${#users[@]} ]; then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    selected_user="${users[$((user_choice-1))]}"
    
    echo ""
    echo -e "${CYAN}${BOLD}=== Details for: $selected_user ===${NC}"
    
    echo ""
    echo -e "${YELLOW}Basic Information:${NC}"
    id "$selected_user"
    
    echo ""
    echo -e "${YELLOW}Account Status:${NC}"
    passwd -S "$selected_user" 2>/dev/null || echo "Could not get password status"
    
    echo ""
    echo -e "${YELLOW}Group Memberships:${NC}"
    groups "$selected_user"
    
    echo ""
    echo -e "${YELLOW}Recent Login History:${NC}"
    last -5 "$selected_user" 2>/dev/null | head -5 || echo "No login history"
    
    echo ""
    echo -e "${YELLOW}Home Directory:${NC}"
    home_dir=$(eval echo "~$selected_user")
    if [ -d "$home_dir" ]; then
        echo "Directory: $home_dir"
        echo "Size: $(du -sh "$home_dir" 2>/dev/null | cut -f1 || echo "Unknown")"
    else
        echo "Home directory does not exist"
    fi
}

# Main program loop
main() {
    check_root
    
    while true; do
        show_header
        list_users
        
        echo -e "${CYAN}${BOLD}Available Actions:${NC}"
        echo "1) Add User"
        echo "2) Reset Password" 
        echo "3) Show User Details"
        echo "4) Delete User"
        echo "5) Refresh List"
        echo "6) Exit"
        echo ""
        echo -n "Choose action (1-6): "
        read -r choice
        
        echo ""
        case "$choice" in
            1)
                add_user
                ;;
            2)
                reset_password
                ;;
            3)
                show_user_details
                ;;
            4)
                delete_user
                ;;
            5)
                continue
                ;;
            6)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-6.${NC}"
                ;;
        esac
        
        if [ "$choice" != "5" ]; then
            echo ""
            echo -n "Press Enter to continue..."
            read -r
        fi
    done
}

# Run the script
main "$@"
