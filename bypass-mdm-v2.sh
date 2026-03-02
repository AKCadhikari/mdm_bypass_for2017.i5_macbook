#!/bin/bash

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
BLU='\033[1;34m'
YEL='\033[1;33m'
PUR='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Warning function
warn() {
    echo -e "${YEL}WARNING: $1${NC}"
}

# Success function
success() {
    echo -e "${GRN}✓ $1${NC}"
}

# Info function
info() {
    echo -e "${BLU}ℹ $1${NC}"
}

# Validation function for username
validate_username() {
    local username="$1"

    # Check if username is empty
    if [ -z "$username" ]; then
        echo "Username cannot be empty"
        return 1
    fi

    # Check length (1-31 characters for macOS)
    if [ ${#username} -gt 31 ]; then
        echo "Username too long (max 31 characters)"
        return 1
    fi

    # Check for valid characters (alphanumeric, underscore, hyphen)
    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Username can only contain letters, numbers, underscore, and hyphen"
        return 1
    fi

    # Check if starts with letter or underscore
    if ! [[ "$username" =~ ^[a-zA-Z_] ]]; then
        echo "Username must start with a letter or underscore"
        return 1
    fi

    return 0
}

# Validation function for password
validate_password() {
    local password="$1"

    # Check if password is empty
    if [ -z "$password" ]; then
        echo "Password cannot be empty"
        return 1
    fi

    # Check minimum length
    if [ ${#password} -lt 4 ]; then
        echo "Password too short (minimum 4 characters recommended)"
        return 1
    fi

    return 0
}

# Check if user already exists
check_user_exists() {
    local dscl_path="$1"
    local username="$2"

    if dscl -f "$dscl_path" localhost -read "/Local/Default/Users/$username" 2>/dev/null; then
        return 0 # User exists
    else
        return 1 # User doesn't exist
    fi
}

# Find available UID
find_available_uid() {
    local dscl_path="$1"
    local uid=501

    # Check UIDs from 501-599
    while [ $uid -lt 600 ]; do
        if ! dscl -f "$dscl_path" localhost -search /Local/Default/Users UniqueID $uid 2>/dev/null | grep -q "UniqueID"; then
            echo $uid
            return 0
        fi
        uid=$((uid + 1))
    done

    echo "501" # Default fallback
    return 1
}

# Function to detect system volume for Intel 2017 Macs
detect_volume() {
    local system_vol=""

    info "Detecting system volume for Intel 2017 Mac..."

    # Common volume names for Intel Macs
    common_names=("Macintosh HD" "macOS" "OS X" "MacOS")

    # First try: Look for any volume with /System directory
    for vol in /Volumes/*; do
        if [ -d "$vol" ] && [ -d "$vol/System" ]; then
            system_vol=$(basename "$vol")
            info "Found volume with /System directory: $system_vol"
            break
        fi
    done

    # Second try: Check common names
    if [ -z "$system_vol" ]; then
        for name in "${common_names[@]}"; do
            if [ -d "/Volumes/$name" ]; then
                system_vol="$name"
                info "Found volume with name: $system_vol"
                break
            fi
        done
    fi

    # Third try: List all volumes and let user choose
    if [ -z "$system_vol" ]; then
        warn "Could not auto-detect volume"
        echo ""
        echo -e "${YEL}Available volumes:${NC}"
        ls -1 /Volumes/
        echo ""
        read -p "Enter your macOS volume name from above: " system_vol

        if [ ! -d "/Volumes/$system_vol" ]; then
            error_exit "Volume '/Volumes/$system_vol' does not exist"
        fi
    fi

    # Validate findings
    if [ -z "$system_vol" ]; then
        error_exit "Could not detect system volume. Please ensure you're running this in Recovery mode with a macOS installation present."
    fi

    echo "$system_vol"
}

# Detect volume at startup
system_volume=$(detect_volume)

# Display header
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     MDM Bypass for Intel 2017 i5 Mac         ║${NC}"
echo -e "${CYAN}║         Adapted from Assaf Dori              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
success "Detected Volume: $system_volume"
echo ""

# Prompt user for choice
PS3='Please enter your choice: '
options=("Bypass MDM from Recovery" "Reboot & Exit")
select opt in "${options[@]}"; do
    case $opt in
    "Bypass MDM from Recovery")
        echo ""
        echo -e "${YEL}═══════════════════════════════════════${NC}"
        echo -e "${YEL}  Starting MDM Bypass Process${NC}"
        echo -e "${YEL}═══════════════════════════════════════${NC}"
        echo ""

        # Mount volume as read-write
        info "Mounting volume as read-write..."
        mount -uw "/Volumes/$system_volume" 2>/dev/null

        # Set paths for Intel Mac (single volume structure)
        system_path="/Volumes/$system_volume"

        if [ ! -d "$system_path" ]; then
            error_exit "System volume path does not exist: $system_path"
        fi

        # dscl path for Intel Mac
        dscl_path="$system_path/var/db/dslocal/nodes/Default"
        if [ ! -d "$dscl_path" ]; then
            error_exit "Directory Services path does not exist: $dscl_path"
        fi

        success "All system paths validated"
        echo ""

        # Create Temporary User
        echo -e "${CYAN}Creating Temporary Admin User${NC}"
        echo -e "${NC}Press Enter to use defaults (recommended)${NC}"

        # Get and validate real name
        read -p "Enter Temporary Fullname (Default is 'Apple'): " realName
        realName="${realName:=Apple}"

        # Get and validate username
        while true; do
            read -p "Enter Temporary Username (Default is 'Apple'): " username
            username="${username:=Apple}"

            if validation_msg=$(validate_username "$username"); then
                break
            else
                warn "$validation_msg"
                echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
            fi
        done

        # Check if user already exists
        if check_user_exists "$dscl_path" "$username"; then
            warn "User '$username' already exists in the system"
            read -p "Do you want to use a different username? (y/n): " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                while true; do
                    read -p "Enter a different username: " username
                    if [ -z "$username" ]; then
                        warn "Username cannot be empty"
                        continue
                    fi
                    if validation_msg=$(validate_username "$username"); then
                        if ! check_user_exists "$dscl_path" "$username"; then
                            break
                        else
                            warn "User '$username' also exists. Try another name."
                        fi
                    else
                        warn "$validation_msg"
                    fi
                done
            else
                warn "Continuing with existing user '$username' (may cause conflicts)"
            fi
        fi

        # Get and validate password
        while true; do
            read -p "Enter Temporary Password (Default is '1234'): " passw
            passw="${passw:=1234}"

            if validation_msg=$(validate_password "$passw"); then
                break
            else
                warn "$validation_msg"
                echo -e "${YEL}Please try again or press Ctrl+C to exit${NC}"
            fi
        done

        echo ""

        # Find available UID
        info "Checking for available UID..."
        available_uid=$(find_available_uid "$dscl_path")
        if [ $? -eq 0 ] && [ "$available_uid" != "501" ]; then
            info "UID 501 is in use, using UID $available_uid instead"
        else
            available_uid="501"
        fi
        success "Using UID: $available_uid"
        echo ""

        # Create User with error handling
        info "Creating user account: $username"

        if ! dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" 2>/dev/null; then
            error_exit "Failed to create user account"
        fi

        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/bash" || warn "Failed to set user shell"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName" || warn "Failed to set real name"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$available_uid" || warn "Failed to set UID"
        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20" || warn "Failed to set GID"

        user_home="$system_path/Users/$username"
        if [ ! -d "$user_home" ]; then
            if mkdir -p "$user_home" 2>/dev/null; then
                success "Created user home directory"
            else
                error_exit "Failed to create user home directory: $user_home"
            fi
        else
            warn "User home directory already exists: $user_home"
        fi

        dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username" || warn "Failed to set home directory"

        # Set ownership
        chown -R $available_uid:20 "$user_home" 2>/dev/null || warn "Failed to set home directory ownership"

        if ! dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw" 2>/dev/null; then
            error_exit "Failed to set user password"
        fi

        if ! dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership "$username" 2>/dev/null; then
            error_exit "Failed to add user to admin group"
        fi

        success "User account created successfully"
        echo ""

        # Block MDM domains
        info "Blocking MDM enrollment domains..."

        hosts_file="$system_path/etc/hosts"
        if [ ! -f "$hosts_file" ]; then
            warn "Hosts file does not exist, creating it"
            touch "$hosts_file" || error_exit "Failed to create hosts file"
        fi

        # Create backup
        cp "$hosts_file" "$hosts_file.backup" 2>/dev/null
        info "Hosts file backed up"

        # Check if entries already exist to avoid duplicates
        grep -q "deviceenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 deviceenrollment.apple.com" >>"$hosts_file"
        grep -q "mdmenrollment.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 mdmenrollment.apple.com" >>"$hosts_file"
        grep -q "iprofiles.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 iprofiles.apple.com" >>"$hosts_file"
        grep -q "gdmf.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 gdmf.apple.com" >>"$hosts_file"
        grep -q "acmdm.apple.com" "$hosts_file" 2>/dev/null || echo "0.0.0.0 acmdm.apple.com" >>"$hosts_file"

        success "MDM domains blocked in hosts file"
        echo ""

        # Remove configuration profiles
        info "Removing MDM configuration files..."

        # Remove existing MDM configurations
        rm -rf "$system_path/var/db/ConfigurationProfiles/"* 2>/dev/null
        rm -rf "$system_path/Library/ConfigurationProfiles/"* 2>/dev/null

        # Create config directory if it doesn't exist
        config_path="$system_path/var/db/ConfigurationProfiles"
        if [ ! -d "$config_path" ]; then
            if mkdir -p "$config_path" 2>/dev/null; then
                success "Created configuration directory"
            fi
        fi

        # Mark setup as done
        touch "$system_path/var/db/.AppleSetupDone" 2>/dev/null && success "Marked setup as complete" || warn "Could not mark setup as complete"

        # Create bypass markers for Intel Mac
        touch "$config_path/.profilesAreInstalled" 2>/dev/null
        touch "$config_path/.cloudConfigProfileInstalled" 2>/dev/null
        touch "$config_path/.cloudConfigRecordNotFound" 2>/dev/null

        # Remove activation records
        rm -rf "$config_path/.cloudConfigHasActivationRecord" 2>/dev/null
        rm -rf "$config_path/.cloudConfigRecordFound" 2>/dev/null

        success "MDM configuration removed"
        echo ""

        # Create LaunchDaemon to keep MDM blocked after updates (optional)
        info "Creating persistent MDM block (optional)..."

        mkdir -p "$system_path/Library/LaunchDaemons" 2>/dev/null

        cat > "$system_path/Library/LaunchDaemons/com.mdm.block.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mdm.block</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>echo "0.0.0.0 deviceenrollment.apple.com" >> /etc/hosts; echo "0.0.0.0 mdmenrollment.apple.com" >> /etc/hosts; echo "0.0.0.0 iprofiles.apple.com" >> /etc/hosts</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
</dict>
</plist>
EOF

        success "Persistent blocker created"
        echo ""

        echo ""
        echo -e "${GRN}╔═══════════════════════════════════════════════╗${NC}"
        echo -e "${GRN}║       MDM Bypass Completed Successfully!     ║${NC}"
        echo -e "${GRN}╚═══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}Next steps:${NC}"
        echo -e "  1. Close this terminal window"
        echo -e "  2. ${YEL}IMMEDIATELY turn off WiFi${NC} before rebooting"
        echo -e "  3. Reboot your Mac"
        echo -e "  4. Login with username: ${YEL}$username${NC} and password: ${YEL}$passw${NC}"
        echo -e "  5. Skip ALL setup prompts (Apple ID, Siri, etc.)"
        echo -e "  6. Create your permanent admin account in System Preferences"
        echo -e "  7. Delete this temporary user"
        echo ""
        echo -e "${RED}IMPORTANT: Keep WiFi OFF until you've created your permanent account!${NC}"
        echo ""
        break
        ;;
    "Reboot & Exit")
        echo ""
        info "Rebooting system..."
        reboot
        break
        ;;
    *)
        echo -e "${RED}Invalid option $REPLY${NC}"
        ;;
    esac
done
