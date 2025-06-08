#!/bin/bash

# User Management Script with Gum
# Requires: gum (charmbracelet/gum)
# Usage: sudo ./user_mgmt.sh

set -e

# Color and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        gum style --foreground 196 --bold "Error: This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if gum is installed
check_gum() {
    if ! command -v gum &> /dev/null; then
        echo -e "${RED}Error: gum is not installed${NC}"
        echo "Install it with: go install github.com/charmbracelet/gum@latest"
        echo "Or visit: https://github.com/charmbracelet/gum"
        exit 1
    fi
}

# Display header
show_header() {
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        'User Management Tool' 'Powered by Gum'
}

# List all users (excluding system users)
list_users() {
    gum style --foreground 45 --bold "Current Users (UID >= 1000):"
    echo ""
    
    # Get users with UID >= 1000 (regular users)
    local users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1 ":" $3 ":" $5}' /etc/passwd)
    
    if [ -z "$users" ]; then
        gum style --foreground 196 "No regular users found"
        return
    fi
    
    # Create formatted table
    echo "Username | UID | Full Name"
    echo "---------|-----|----------"
    
    while IFS=':' read -r username uid fullname; do
        # Get last login info
        last_login=$(last -1 "$username" 2>/dev/null | head -1 | awk '{print $4, $5, $6}' || echo "Never")
        if [ "$last_login" = "Never" ] || [ -z "$last_login" ]; then
            last_login="Never"
        fi
        
        printf "%-12s | %-4s | %s\n" "$username" "$uid" "$fullname"
    done <<< "$users"
    
    echo ""
}

# Add new user
add_user() {
    gum style --foreground 45 --bold "Add New User"
    echo ""
    
    # Get username
    local username
    username=$(gum input --placeholder "Enter username" --prompt "Username: ")
    
    if [ -z "$username" ]; then
        gum style --foreground 196 "Username cannot be empty"
        return 1
    fi
    
    # Check if user already exists
    if id "$username" &>/dev/null; then
        gum style --foreground 196 "User '$username' already exists"
        return 1
    fi
    
    # Get full name
    local fullname
    fullname=$(gum input --placeholder "Enter full name (optional)" --prompt "Full Name: ")
    
    # Get password option
    local pwd_option
    pwd_option=$(gum choose --header "Password option:" "Generate random password" "Set custom password" "No password (locked account)")
    
    local password=""
    case "$pwd_option" in
        "Generate random password")
            password=$(openssl rand -base64 12)
            ;;
        "Set custom password")
            password=$(gum input --password --placeholder "Enter password" --prompt "Password: ")
            if [ -z "$password" ]; then
                gum style --foreground 196 "Password cannot be empty"
                return 1
            fi
            ;;
        "No password (locked account)")
            password=""
            ;;
    esac
    
    # Create home directory option
    local create_home
    create_home=$(gum choose --header "Create home directory?" "Yes" "No")
    
    # Select shell
    local shell
    shell=$(gum choose --header "Select shell:" "/bin/bash" "/bin/sh" "/bin/zsh" "/usr/bin/fish")
    
    # Confirm creation
    gum style --foreground 45 "User Details:"
    echo "Username: $username"
    echo "Full Name: ${fullname:-"Not specified"}"
    echo "Password: ${password:-"None (locked)"}"
    echo "Home Directory: ${create_home}"
    echo "Shell: $shell"
    echo ""
    
    local confirm
    confirm=$(gum choose --header "Create this user?" "Yes" "No")
    
    if [ "$confirm" != "Yes" ]; then
        gum style --foreground 196 "User creation cancelled"
        return 1
    fi
    
    # Build useradd command
    local cmd="useradd"
    
    if [ "$create_home" = "Yes" ]; then
        cmd="$cmd -m"
    fi
    
    if [ -n "$fullname" ]; then
        cmd="$cmd -c \"$fullname\""
    fi
    
    cmd="$cmd -s $shell $username"
    
    # Execute user creation
    if eval "$cmd"; then
        gum style --foreground 46 "✓ User '$username' created successfully"
        
        # Set password if provided
        if [ -n "$password" ]; then
            echo "$username:$password" | chpasswd
            if [ "$pwd_option" = "Generate random password" ]; then
                gum style --foreground 226 "Generated password: $password"
                gum style --foreground 226 "Please save this password securely!"
            fi
        fi
        
        # Show new user info
        echo ""
        gum style --foreground 45 "New user information:"
        id "$username"
    else
        gum style --foreground 196 "✗ Failed to create user '$username'"
        return 1
    fi
}

# Reset user password
reset_password() {
    gum style --foreground 45 --bold "Reset User Password"
    echo ""
    
    # Get list of regular users
    local users
    users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    
    if [ -z "$users" ]; then
        gum style --foreground 196 "No regular users found"
        return 1
    fi
    
    # Convert to array for gum choose
    local user_array=()
    while IFS= read -r line; do
        user_array+=("$line")
    done <<< "$users"
    
    # Select user
    local selected_user
    selected_user=$(gum choose --header "Select user to reset password:" "${user_array[@]}")
    
    if [ -z "$selected_user" ]; then
        gum style --foreground 196 "No user selected"
        return 1
    fi
    
    # Password reset options
    local reset_option
    reset_option=$(gum choose --header "Password reset option:" "Generate random password" "Set custom password" "Lock account" "Unlock account")
    
    case "$reset_option" in
        "Generate random password")
            local new_password
            new_password=$(openssl rand -base64 12)
            echo "$selected_user:$new_password" | chpasswd
            
            # Force password change on next login
            local force_change
            force_change=$(gum choose --header "Force password change on next login?" "Yes" "No")
            if [ "$force_change" = "Yes" ]; then
                passwd -e "$selected_user"
            fi
            
            gum style --foreground 46 "✓ Password reset for user '$selected_user'"
            gum style --foreground 226 "New password: $new_password"
            gum style --foreground 226 "Please save this password securely!"
            ;;
            
        "Set custom password")
            local custom_password
            custom_password=$(gum input --password --placeholder "Enter new password" --prompt "New Password: ")
            
            if [ -z "$custom_password" ]; then
                gum style --foreground 196 "Password cannot be empty"
                return 1
            fi
            
            echo "$selected_user:$custom_password" | chpasswd
            
            # Force password change on next login
            local force_change
            force_change=$(gum choose --header "Force password change on next login?" "Yes" "No")
            if [ "$force_change" = "Yes" ]; then
                passwd -e "$selected_user"
            fi
            
            gum style --foreground 46 "✓ Password reset for user '$selected_user'"
            ;;
            
        "Lock account")
            passwd -l "$selected_user"
            gum style --foreground 46 "✓ Account '$selected_user' locked"
            ;;
            
        "Unlock account")
            passwd -u "$selected_user"
            gum style --foreground 46 "✓ Account '$selected_user' unlocked"
            ;;
    esac
}

# Delete user
delete_user() {
    gum style --foreground 45 --bold "Delete User"
    echo ""
    
    # Get list of regular users
    local users
    users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    
    if [ -z "$users" ]; then
        gum style --foreground 196 "No regular users found"
        return 1
    fi
    
    # Convert to array for gum choose
    local user_array=()
    while IFS= read -r line; do
        user_array+=("$line")
    done <<< "$users"
    
    # Select user
    local selected_user
    selected_user=$(gum choose --header "Select user to delete:" "${user_array[@]}")
    
    if [ -z "$selected_user" ]; then
        gum style --foreground 196 "No user selected"
        return 1
    fi
    
    # Show user info
    gum style --foreground 45 "User to delete:"
    id "$selected_user"
    echo ""
    
    # Confirm deletion
    gum style --foreground 196 --bold "⚠ WARNING: This action cannot be undone!"
    
    local remove_home
    remove_home=$(gum choose --header "Remove home directory and mail spool?" "Yes" "No")
    
    local confirm
    confirm=$(gum choose --header "Are you sure you want to delete user '$selected_user'?" "Yes" "No")
    
    if [ "$confirm" != "Yes" ]; then
        gum style --foreground 196 "User deletion cancelled"
        return 1
    fi
    
    # Delete user
    local cmd="userdel"
    if [ "$remove_home" = "Yes" ]; then
        cmd="$cmd -r"
    fi
    cmd="$cmd $selected_user"
    
    if eval "$cmd"; then
        gum style --foreground 46 "✓ User '$selected_user' deleted successfully"
    else
        gum style --foreground 196 "✗ Failed to delete user '$selected_user'"
        return 1
    fi
}

# Show user details
show_user_details() {
    gum style --foreground 45 --bold "User Details"
    echo ""
    
    # Get list of regular users
    local users
    users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    
    if [ -z "$users" ]; then
        gum style --foreground 196 "No regular users found"
        return 1
    fi
    
    # Convert to array for gum choose
    local user_array=()
    while IFS= read -r line; do
        user_array+=("$line")
    done <<< "$users"
    
    # Select user
    local selected_user
    selected_user=$(gum choose --header "Select user to view details:" "${user_array[@]}")
    
    if [ -z "$selected_user" ]; then
        gum style --foreground 196 "No user selected"
        return 1
    fi
    
    gum style --foreground 45 --bold "Details for user: $selected_user"
    echo ""
    
    # Basic info
    echo "=== Basic Information ==="
    id "$selected_user"
    echo ""
    
    # Account status
    echo "=== Account Status ==="
    passwd -S "$selected_user" 2>/dev/null || echo "Could not get password status"
    echo ""
    
    # Groups
    echo "=== Group Memberships ==="
    groups "$selected_user"
    echo ""
    
    # Last login
    echo "=== Login History (last 5) ==="
    last -5 "$selected_user" 2>/dev/null || echo "No login history found"
    echo ""
    
    # Home directory
    echo "=== Home Directory ==="
    local home_dir
    home_dir=$(eval echo "~$selected_user")
    if [ -d "$home_dir" ]; then
        ls -la "$home_dir" | head -10
    else
        echo "Home directory does not exist"
    fi
}

# Main menu
main_menu() {
    while true; do
        clear
        show_header
        
        local choice
        choice=$(gum choose --header "Select an option:" \
            "List Users" \
            "Add User" \
            "Reset Password" \
            "User Details" \
            "Delete User" \
            "Refresh" \
            "Exit")
        
        case "$choice" in
            "List Users")
                clear
                show_header
                list_users
                gum input --placeholder "Press Enter to continue..."
                ;;
            "Add User")
                clear
                show_header
                add_user
                gum input --placeholder "Press Enter to continue..."
                ;;
            "Reset Password")
                clear
                show_header
                reset_password
                gum input --placeholder "Press Enter to continue..."
                ;;
            "User Details")
                clear
                show_header
                show_user_details
                gum input --placeholder "Press Enter to continue..."
                ;;
            "Delete User")
                clear
                show_header
                delete_user
                gum input --placeholder "Press Enter to continue..."
                ;;
            "Refresh")
                continue
                ;;
            "Exit")
                gum style --foreground 46 "Goodbye!"
                exit 0
                ;;
        esac
    done
}

# Main execution
main() {
    check_gum
    check_root
    main_menu
}

# Run the script
main "$@"
