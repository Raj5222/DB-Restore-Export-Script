#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
REPO_SCRIPT="https://raw.githubusercontent.com/raj5222/DB-Restore-Export-Script/main/db-toolkit.sh"
INSTALL_PATH="/usr/local/bin/db-toolkit"
TMP_FILE="/tmp/db-toolkit-installer-$$"
BACKUP_FILE="/tmp/db-toolkit-backup-$$"

# Total steps for the progress bar
TOTAL_STEPS=6
CURRENT_STEP=0

# -----------------------------------------------------------------------------
# Colors & Formatting
# -----------------------------------------------------------------------------
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
NC="\033[0m" # No Color
BOLD="\033[1m"

# -----------------------------------------------------------------------------
# UI Functions
# -----------------------------------------------------------------------------

# Hide cursor to prevent flickering
tput civis

cleanup() {
    tput cnorm # Always restore cursor
    rm -f "$TMP_FILE" 2>/dev/null
    if [ -f "$BACKUP_FILE" ]; then
        sudo rm -f "$BACKUP_FILE" 2>/dev/null || true
    fi
}

ctrl_c() {
    tput cnorm
    echo -e "\n${RED} [ ✖ ] Cancelled by user.${NC}"
    cleanup
    exit 130
}

trap ctrl_c INT TERM
trap cleanup EXIT

draw_header() {
    local percent=$1
    local bar_width=40
    local filled=$(( bar_width * percent / 100 ))
    local empty=$(( bar_width - filled ))
    
    # Save cursor, jump to top, draw, restore cursor
    tput sc
    tput cup 0 0
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}                DB Toolkit Installer${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local bar=$(printf "%0.s=" $(seq 1 $filled))
    local space=$(printf "%0.s-" $(seq 1 $empty))
    
    echo -e " Progress: ${BLUE}[${bar}${CYAN}>${NC}${BLUE}${space}]${NC} ${percent}%"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    tput rc
}

# -----------------------------------------------------------------------------
# Task Runner
# -----------------------------------------------------------------------------

run_task() {
    local desc="$1"
    local cmd="$2"

    CURRENT_STEP=$((CURRENT_STEP + 1))
    local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    draw_header "$pct"

    printf "${BLUE} [ .. ]${NC} %s" "$desc"

    local output
    output=$(eval "$cmd" 2>&1)
    local status=$?

    sleep 0.3

    if [ $status -eq 0 ]; then
        printf "\r${GREEN} [ ✔ ]${NC} %s\033[K\n" "$desc"
    else
        printf "\r${RED} [ ✖ ]${NC} %s\033[K\n" "$desc"
        tput cnorm
        echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED} ERROR:${NC}"
        echo -e "${YELLOW}$output${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

clear
# Reserve space for header (5 lines)
echo -e "\n\n\n\n\n"
draw_header "0"

# --- STEP 1: SUDO CHECK (Interactive) ---
# We handle this manually to manage the password prompt visual
CURRENT_STEP=1
draw_header "$(( 1 * 100 / TOTAL_STEPS ))"

# Check if we already have sudo rights without password
if sudo -n true 2>/dev/null; then
    printf "${GREEN} [ ✔ ]${NC} Sudo permissions verified\n"
else
    # We need a password - Prompt nicely
    printf "${YELLOW} [ 🔑 ] Action Required: Enter sudo password${NC}"
    
    # Show cursor for typing
    tput cnorm
    
    # Read password silently (-s)
    # We trap errors here to avoid printing ugly sudo errors
    if sudo -v; then
        tput civis # Hide cursor again
        # Move cursor up one line (because enter creates a newline) and overwrite
        # tput cuu1 
        printf "\r${GREEN} [ ✔ ]${NC} Sudo permissions verified\033[K\n"
    else
        tput civis
        printf "\r${RED} [ ✖ ]${NC} Authentication failed\033[K\n"
        exit 1
    fi
fi

# --- STEP 2: DOWNLOAD ---
run_task "Downloading latest version" \
    "curl -fsSL '$REPO_SCRIPT' -o '$TMP_FILE' && [ -s '$TMP_FILE' ]"

# --- STEP 3: CHECK ---
run_task "Checking for updates" \
    "[ -f '$TMP_FILE' ]"

NEW_HASH=$(sha256sum "$TMP_FILE" | cut -d ' ' -f1)
INSTALL_TYPE="FRESH"

if [ -f "$INSTALL_PATH" ]; then
    CURRENT_HASH=$(sha256sum "$INSTALL_PATH" | cut -d ' ' -f1)
    
    if [ "$NEW_HASH" = "$CURRENT_HASH" ]; then
        draw_header "100"
        printf "${GREEN} [ ✔ ]${NC} System is already up to date\n"
        rm -f "$TMP_FILE"
        echo -e "\n${GREEN} You have the latest version.${NC}\n"
        exit 0
    else
        INSTALL_TYPE="UPDATE"
    fi
fi

# --- STEP 4: BACKUP ---
if [ "$INSTALL_TYPE" = "UPDATE" ]; then
    run_task "Backing up old version" \
        "sudo cp '$INSTALL_PATH' '$BACKUP_FILE'"
else
    run_task "Preparing installation" "true"
fi

# --- STEP 5: INSTALL ---
run_task "Installing to system" \
    "sudo mv -f '$TMP_FILE' '$INSTALL_PATH' && sudo chmod +x '$INSTALL_PATH'"

# --- STEP 6: CLEANUP ---
run_task "Cleaning up temporary files" \
    "rm -f '$TMP_FILE' && sudo rm -f '$BACKUP_FILE' 2>/dev/null"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
draw_header "100"
echo ""
echo -e " ${GREEN}✔ Installation Complete${NC}"
echo -e "   Run command: ${BOLD}db-toolkit${NC}"
echo ""
