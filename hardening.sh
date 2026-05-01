#!/bin/bash
set -euo pipefail

# ==========================================
# Version 3 - Fully Idempotent Hardened Script
# Ubuntu 22.04 LTS
# ==========================================

USERNAME1="xyzinfra"
USERNAME2="xyzinfra2"
TIMESTAMP=$(date +%F-%H%M%S)

log() {
    echo "[INFO] $1"
}

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.bak.$TIMESTAMP"
        log "Backup created: $1.bak.$TIMESTAMP"
    fi
}

# Generic key=value config setter
set_config_param() {
    local file="$1"
    local key="$2"
    local value="$3"

    if grep -Eq "^[#[:space:]]*$key" "$file"; then
        sed -i "s|^[#[:space:]]*$key.*|$key $value|" "$file"
    else
        echo "$key $value" >> "$file"
    fi
}

# Ensure exact line exists (for PAM)
ensure_line_exists() {
    local file="$1"
    local line="$2"

    grep -Fxq "$line" "$file" || echo "$line" >> "$file"
}

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run as root."
    exit 1
fi

log "Starting Version 3 Production Hardening..."

# ==========================================
# Step 1: Install Required Packages
# ==========================================
apt update -y
apt install -y libpam-pwquality

# ==========================================
# Step 2: Configure Password Complexity
# ==========================================
backup_file /etc/security/pwquality.conf

set_config_param /etc/security/pwquality.conf "minlen" "= 8"
set_config_param /etc/security/pwquality.conf "minclass" "= 3"

log "Password complexity configured."

# ==========================================
# Step 3: Configure Password Aging
# ==========================================
backup_file /etc/login.defs

set_config_param /etc/login.defs "PASS_MAX_DAYS" "90"
set_config_param /etc/login.defs "PASS_MIN_DAYS" "0"
set_config_param /etc/login.defs "PASS_WARN_AGE" "7"

log "Password aging configured."

# ==========================================
# Step 4: Configure Account Lockout
# ==========================================
backup_file /etc/security/faillock.conf

set_config_param /etc/security/faillock.conf "deny" "= 5"
set_config_param /etc/security/faillock.conf "unlock_time" "= 900"

# PAM configuration (idempotent)
backup_file /etc/pam.d/common-auth
backup_file /etc/pam.d/common-account

ensure_line_exists /etc/pam.d/common-auth "auth required pam_faillock.so preauth"
ensure_line_exists /etc/pam.d/common-auth "auth required pam_faillock.so authfail"
ensure_line_exists /etc/pam.d/common-account "account required pam_faillock.so"

log "Account lockout configured."

# ==========================================
# Step 5: Configure Session Timeout
# ==========================================
backup_file /etc/profile

if ! grep -q "^TMOUT=" /etc/profile; then
    echo -e "\n# Auto logout after 5 minutes\nTMOUT=300\nexport TMOUT" >> /etc/profile
fi

log "Session timeout configured."

# ==========================================
# Step 6: Configure SSH Timeout
# ==========================================
backup_file /etc/ssh/sshd_config

set_config_param /etc/ssh/sshd_config "ClientAliveInterval" "300"
set_config_param /etc/ssh/sshd_config "ClientAliveCountMax" "0"

systemctl restart ssh
log "SSH timeout configured."

# ==========================================
# Step 7: Create Users (After Policies Applied)
# ==========================================
for USER in "$USERNAME1" "$USERNAME2"
do
    if id "$USER" &>/dev/null; then
        log "User $USER already exists."
    else
        adduser --gecos "" "$USER"
        log "User $USER created."
    fi

    chage -M 90 "$USER"
    usermod -aG sudo "$USER"

    echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
    chmod 440 /etc/sudoers.d/$USER

done

log "========================================="
log "Version 3 Hardening Completed Successfully"
log "========================================="

