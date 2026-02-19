#!/bin/bash

# ============================================================
#   ❖ Pro Database Toolkit (Restore & Export)
#   Strict Validation | Smart Suggestions | Sticky Window
# ============================================================

# --- Universal Standard Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Globals ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SPINNER_PID=""
HR="------------------------------------------------------------"
ACTION="" 
DB_EXISTS=0

# --- Process Cleanup ---
kill_spinner() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    SPINNER_PID=""
  fi
}

trap cleanup EXIT INT TERM
cleanup() {
  kill_spinner
  tput cnorm # Ensure cursor is visible
}

# --- UI Helpers ---
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}  ========================================================${NC}"
  echo -e "${CYAN}${BOLD}    ❖  DATABASE TOOLKIT (RESTORE & EXPORT)${NC}"
  echo -e "${CYAN}${BOLD}  ========================================================${NC}"
  echo ""
}

print_step() {
  echo -e "\n${BOLD}${BLUE} [ STEP ] ${NC}${BOLD}$1${NC}"
  echo -e "${DIM}${HR}${NC}"
}

prompt_input() {
  local label="$1"
  local default_val="$2"
  local is_secret="$3"
  local hint="$4"
  
  if [[ -n "$hint" ]]; then
    echo -e "  ${DIM}↳ $hint${NC}"
  fi

  if [[ -n "$default_val" && "$default_val" != "hidden" ]]; then
    printf "  ${CYAN}?${NC} %-12s ${DIM}[%s]${NC}: " "$label" "$default_val"
  elif [[ "$default_val" == "hidden" ]]; then
    printf "  ${CYAN}?${NC} %-12s ${DIM}[hidden]${NC}: " "$label"
  else
    printf "  ${CYAN}?${NC} %-12s : " "$label"
  fi

  if [[ "$is_secret" == "true" ]]; then
    read -rs USER_INPUT
    echo "" 
  else
    read -r USER_INPUT
  fi
}

success() { echo -e "${GREEN}  ✔ ${NC} $1"; }

# Safely kill spinner and print error
error() { 
  if [[ -n "$SPINNER_PID" ]]; then
    kill_spinner
    echo -e "\b\b\b${RED}✖${NC}\n" # Replace spinner with Red X
    echo -e "  ${RED}↳ Error:${NC} $1"
  else
    echo -e "\n  ${RED}✖ Error:${NC} $1"
  fi
  tput cnorm
  exit 1
}

info() { echo -e "${YELLOW}  ℹ ${NC} $1"; }

# --- Background Spinner ---
start_spinner() {
  local msg="$1"
  tput civis
  echo -ne "  ${CYAN}*${NC} ${msg}... "
  (
    local spinstr='|/-\'
    while true; do
      local temp=${spinstr#?}
      printf "[%c]" "$spinstr"
      local spinstr=$temp${spinstr%"$temp"}
      sleep 0.1
      printf "\b\b\b"
    done
  ) &
  SPINNER_PID=$!
}

stop_spinner() {
  local result_msg="$1"
  kill_spinner
  echo -e "\b\b\b${GREEN}✔${NC} ${result_msg}"
}

# ─── Step 1: Choose Action ────────────────────────────────
step_choose_action() {
  print_banner
  print_step "Select Operation"
  
  echo -e "  1. 📥 Restore (Import dump into database)"
  echo -e "  2. 📤 Export  (Backup database to dump file)"
  echo ""
  
  prompt_input "Choice" "1" "false" "Enter 1 for Restore, 2 for Export"
  local ACTION_CHOICE="${USER_INPUT:-1}"

  if [[ "$ACTION_CHOICE" == "2" ]]; then ACTION="export"; else ACTION="restore"; fi
}

# ─── Step 2: Choose Engine ────────────────────────────────
step_choose_db() {
  print_step "Select Target Environment"
  echo -e "  1. MySQL / MariaDB"
  echo -e "  2. PostgreSQL ${DIM}(default)${NC}"
  echo -e "  3. MongoDB"
  echo ""
  
  prompt_input "Choice" "2" "false" "Enter 1, 2, or 3 for the database engine"
  local DB_CHOICE="${USER_INPUT:-2}"

  case "$DB_CHOICE" in
    1) DB_TYPE="mysql"    ;;
    3) DB_TYPE="mongodb"  ;;
    *) DB_TYPE="postgres" ;;
  esac
}

# ─── Step 3: Check Dependencies ───────────────────────────
step_check_dependencies() {
  print_step "System Verification"
  start_spinner "Checking required tools for ${DB_TYPE^^}"

  local cmds=()
  case "$DB_TYPE" in
    mysql)    cmds=(mysql mysqldump) ;;
    postgres) cmds=(psql createdb pg_restore pg_dump) ;;
    mongodb)  cmds=(mongosh mongorestore mongodump) ;;
  esac

  for cmd in "${cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      error "Required dependency '${BOLD}$cmd${NC}${RED}' is missing. Please install it."
    fi
  done

  stop_spinner "All dependencies found"
}

# ─── Step 4: Credentials ──────────────────────────────────
step_credentials() {
  print_banner
  print_step "Configure Connection: ${DB_TYPE^^}"

  case "$DB_TYPE" in
    mysql)    DEFAULT_PORT=3306;  DEFAULT_USER="root"     ;;
    postgres) DEFAULT_PORT=5432;  DEFAULT_USER="postgres" ;;
    mongodb)  DEFAULT_PORT=27017; DEFAULT_USER="admin"    ;;
  esac

  prompt_input "Host" "localhost" "false" "Server address (e.g., localhost, 127.0.0.1)"
  DB_HOST="${USER_INPUT:-localhost}"

  prompt_input "Port" "$DEFAULT_PORT" "false" "Network port for the database service"
  DB_PORT="${USER_INPUT:-$DEFAULT_PORT}"

  prompt_input "Username" "$DEFAULT_USER" "false" "Database user"
  DB_USER="${USER_INPUT:-$DEFAULT_USER}"

  prompt_input "Password" "hidden" "true" "Leave completely blank if no password is required"
  DB_PASS="$USER_INPUT"
}

# ─── Step 5: Test Connection ──────────────────────────────
step_test_connection() {
  print_step "Validating Access"
  start_spinner "Verifying credentials on ${DB_HOST}:${DB_PORT}"
  
  local pass_arg=""
  [[ -n "$DB_PASS" ]] && pass_arg="-p${DB_PASS}"
  
  case "$DB_TYPE" in
    mysql)
      mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${pass_arg} -e "SELECT 1;" < /dev/null &>/dev/null \
        || error "MySQL Connection Failed. Invalid credentials or server offline." 
      ;;
    postgres)
      export PGPASSWORD="$DB_PASS"
      psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -w -c "SELECT 1;" < /dev/null &>/dev/null \
        || error "PostgreSQL Connection Failed. Invalid credentials or server offline." 
      ;;
    mongodb)
      local mongo_pass=""
      [[ -n "$DB_PASS" ]] && mongo_pass="--username $DB_USER --password $DB_PASS"
      mongosh --host "$DB_HOST" --port "$DB_PORT" $mongo_pass --quiet --eval "db.adminCommand('ping')" < /dev/null &>/dev/null \
        || error "MongoDB Connection Failed. Invalid credentials or server offline." 
      ;;
  esac
  stop_spinner "Credentials verified"
}

# ─── Step 6: Select Target DB ─────────────────────────────
step_target_db() {
  print_step "Database Selection"
  echo -e "  ${DIM}↳ Fetching available databases from the server...${NC}"

  DB_LIST=()
  case "$DB_TYPE" in
    mysql)
      mapfile -t DB_LIST < <(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -sse "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA;" < /dev/null 2>/dev/null)
      ;;
    postgres)
      mapfile -t DB_LIST < <(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w -tAc "SELECT datname FROM pg_database WHERE datistemplate = false;" < /dev/null 2>/dev/null)
      ;;
    mongodb)
      local mongo_pass=""
      [[ -n "$DB_PASS" ]] && mongo_pass="--username $DB_USER --password $DB_PASS"
      mapfile -t DB_LIST < <(mongosh --host "$DB_HOST" --port "$DB_PORT" $mongo_pass --quiet --eval "db.getMongo().getDBNames().forEach(db => console.log(db)); null" < /dev/null 2>/dev/null | grep -v 'null' | grep -v 'undefined' | grep -v '^$')
      ;;
  esac

  DB_NAME=""
  if [[ ${#DB_LIST[@]} -gt 0 ]]; then
    echo -e "  ${GREEN}Found ${#DB_LIST[@]} database(s):${NC}"
    for i in "${!DB_LIST[@]}"; do
      echo -e "    ${CYAN}$((i+1))${NC}. ${DB_LIST[$i]}"
    done
    
    local CUSTOM_OPT=$(( ${#DB_LIST[@]} + 1 ))
    
    if [[ "$ACTION" == "restore" ]]; then
      echo -e "    ${CYAN}${CUSTOM_OPT}${NC}. ${DIM}[ Type a custom database name (will be created) ]${NC}"
    fi
    echo ""

    while true; do
      printf "  ${CYAN}?${NC} %-12s : " "Choice"
      read -e -r USER_DB_INPUT

      if [[ "$USER_DB_INPUT" =~ ^[0-9]+$ ]] && [ "$USER_DB_INPUT" -ge 1 ] && [ "$USER_DB_INPUT" -le "${#DB_LIST[@]}" ]; then
        DB_NAME="${DB_LIST[$((USER_DB_INPUT-1))]}"
        break
      elif [[ "$USER_DB_INPUT" == "$CUSTOM_OPT" && "$ACTION" == "restore" ]]; then
        echo -e "\n  ${DIM}↳ Enter the exact name of the new database.${NC}"
        printf "  ${CYAN}?${NC} %-12s : " "Custom DB"
        read -e -r DB_NAME
        [[ -n "$DB_NAME" ]] && break
      elif [[ -n "$USER_DB_INPUT" ]]; then
        if [[ "$ACTION" == "export" ]]; then
          local found=false
          for db in "${DB_LIST[@]}"; do
            if [[ "$db" == "$USER_DB_INPUT" ]]; then found=true; break; fi
          done
          if [[ "$found" == "true" ]]; then
            DB_NAME="$USER_DB_INPUT"
            break
          else
            echo -e "    ${RED}↳ Error: Database '$USER_DB_INPUT' does not exist. Cannot export.${NC}"
          fi
        else
          DB_NAME="$USER_DB_INPUT"
          break
        fi
      else
        echo -e "    ${RED}↳ Invalid choice.${NC}"
      fi
    done
  else
    echo -e "  ${DIM}Could not fetch database list automatically.${NC}"
    while [[ -z "$DB_NAME" ]]; do
      prompt_input "Target DB" "" "false" "Enter exact name of the database"
      DB_NAME="$USER_INPUT"
    done
  fi
}

# ─── Step 7: Verify Target DB Exists ──────────────────────
step_verify_database() {
  print_step "Verification"
  start_spinner "Checking existence of '${DB_NAME}'"

  case "$DB_TYPE" in
    postgres)
      local res=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';" < /dev/null 2>/dev/null)
      [[ "$res" == "1" ]] && DB_EXISTS=1
      ;;
    mysql)
      local res=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -sse "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';" < /dev/null 2>/dev/null)
      [[ "$res" == "1" ]] && DB_EXISTS=1
      ;;
    mongodb)
      local mongo_pass=""
      [[ -n "$DB_PASS" ]] && mongo_pass="--username $DB_USER --password $DB_PASS"
      local res=$(mongosh --host "$DB_HOST" --port "$DB_PORT" $mongo_pass --quiet --eval "console.log(db.getMongo().getDBNames().includes('${DB_NAME}') ? 1 : 0); null" < /dev/null 2>/dev/null | grep -o '1')
      [[ "$res" == "1" ]] && DB_EXISTS=1
      ;;
  esac

  if [[ "$ACTION" == "export" && "$DB_EXISTS" == "0" ]]; then
    error "Database '${DB_NAME}' does not exist on the server. Cannot export!"
  elif [[ "$DB_EXISTS" == "1" ]]; then
    stop_spinner "Database '${DB_NAME}' located"
  else
    stop_spinner "Database '${DB_NAME}' is new (will be created)"
  fi
}

# ─── Step 8: File Configuration ───────────────────────────
step_file_config() {
  print_step "File Configuration"
  
  if [[ "$ACTION" == "restore" ]]; then
    echo -e "  ${DIM}↳ Scanning current directory for potential backup files...${NC}"
    mapfile -t DUMP_FILES < <(find . -maxdepth 2 -type f \( -name "*.sql" -o -name "*.dump" -o -name "*.bak" -o -name "*.gz" -o -name "*.tar" -o -name "*.bson" -o -name "*.archive" \) 2>/dev/null | sed 's|^\./||')

    if [[ ${#DUMP_FILES[@]} -gt 0 ]]; then
      echo -e "  ${GREEN}Found ${#DUMP_FILES[@]} potential file(s):${NC}"
      for i in "${!DUMP_FILES[@]}"; do echo -e "    ${CYAN}$((i+1))${NC}. ${DUMP_FILES[$i]}"; done
      local CUSTOM_OPT=$(( ${#DUMP_FILES[@]} + 1 ))
      echo -e "    ${CYAN}${CUSTOM_OPT}${NC}. ${DIM}[ Provide custom complete file path ]${NC}\n"
      
      while true; do
        printf "  ${CYAN}?${NC} %-12s : " "Choice"
        read -e -r USER_DUMP_INPUT
        if [[ "$USER_DUMP_INPUT" =~ ^[0-9]+$ ]] && [ "$USER_DUMP_INPUT" -ge 1 ] && [ "$USER_DUMP_INPUT" -le "${#DUMP_FILES[@]}" ]; then
          DUMP_PATH="${DUMP_FILES[$((USER_DUMP_INPUT-1))]}"; break
        elif [[ "$USER_DUMP_INPUT" == "$CUSTOM_OPT" ]]; then
          echo -e "\n  ${DIM}↳ Enter the full or relative path to your backup file.${NC}"
          printf "  ${CYAN}?${NC} %-12s : " "Custom Path"
          read -e -r DUMP_PATH; break
        elif [[ -f "$USER_DUMP_INPUT" || -d "$USER_DUMP_INPUT" ]]; then
          DUMP_PATH="$USER_DUMP_INPUT"; break
        else
          echo -e "    ${RED}↳ Invalid choice.${NC}"
        fi
      done
    else
      echo -e "  ${DIM}No backup files detected nearby.${NC}"
      printf "  ${CYAN}?${NC} %-12s : " "File Path"
      read -e -r DUMP_PATH
    fi

    while [[ ! -f "$DUMP_PATH" && ! -d "$DUMP_PATH" ]]; do
      echo -e "    ${RED}✖ Error: File or directory not found: '$DUMP_PATH'${NC}"
      printf "  ${CYAN}?${NC} %-12s : " "Try Again"
      read -e -r DUMP_PATH
    done
    BACKUP_NAME="${DB_NAME}_backup_${TIMESTAMP}"
    
  else
    # ACTION == export
    local EXT="dump"
    [[ "$DB_TYPE" == "mysql" ]] && EXT="sql"
    [[ "$DB_TYPE" == "mongodb" ]] && EXT="archive"
    
    local DEFAULT_DUMP="./${DB_NAME}_export_${TIMESTAMP}.${EXT}"
    echo -e "  ${DIM}↳ Specify where to save the exported database.${NC}"
    prompt_input "Output Path" "$DEFAULT_DUMP" "false" ""
    DUMP_PATH="${USER_INPUT:-$DEFAULT_DUMP}"
  fi
}

# ─── Step 9: Handle Existing DB (Restore Only) ────────────
step_handle_existing() {
  if [[ "$ACTION" != "restore" ]]; then return; fi

  print_step "Preparing Target Database"

  case "$DB_TYPE" in
    postgres)
      if [[ "$DB_EXISTS" == "1" ]]; then
        start_spinner "Backing up existing DB to ${BACKUP_NAME}"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -w -q -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid();" < /dev/null >/dev/null 2>&1
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -w -c "ALTER DATABASE \"${DB_NAME}\" RENAME TO \"${BACKUP_NAME}\";" < /dev/null 2>/dev/null || error "Rename failed."
        stop_spinner "Backup secured"
      fi
      start_spinner "Creating clean database"
      createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w "$DB_NAME" < /dev/null 2>/dev/null || error "Failed to create DB."
      stop_spinner "Ready for data"
      ;;
    mysql)
       start_spinner "Initializing database"
       mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;" < /dev/null >/dev/null 2>&1
       stop_spinner "Database initialized"
       ;;
    mongodb)
       start_spinner "Preparing MongoDB"
       stop_spinner "MongoDB ready"
       ;;
  esac
}

# ─── Step 10: Execute w/ Dynamic Sticky Window ────────────
step_execute() {
  print_step "Execution Overview"
  echo -e "  Operation       : ${CYAN}${ACTION^^}${NC}"
  echo -e "  Target Database : ${CYAN}${DB_NAME}${NC}"
  echo -e "  File Path       : ${CYAN}${DUMP_PATH}${NC}"
  echo ""
  
  if [[ "$ACTION" == "restore" ]]; then
    echo -e "  ${DIM}↳ Warning: Data restoration will overwrite current database state.${NC}"
  fi
  
  prompt_input "Proceed?" "Y/n" "false" ""
  [[ "$USER_INPUT" =~ ^[nN] ]] && { info "Aborted by user."; exit 0; }

  echo ""
  
  local TERM_COLS=$(tput cols 2>/dev/null || echo 80)
  local TERM_LINES=$(tput lines 2>/dev/null || echo 24)

  local BOX_WIDTH=$(( TERM_COLS * 70 / 100 ))
  local BOX_HEIGHT=$(( TERM_LINES * 60 / 100 ))

  [[ $BOX_WIDTH -lt 45 ]] && BOX_WIDTH=45
  local LOG_LINES=$(( BOX_HEIGHT - 4 )) 
  [[ $LOG_LINES -lt 5 ]] && LOG_LINES=5

  local TEXT_WIDTH=$(( BOX_WIDTH - 4 ))
  local H_LINE=$(printf '─%.0s' $(seq 1 $((BOX_WIDTH - 2))))

  echo -e "  ${CYAN}┌${H_LINE}┐${NC}"
  printf "  ${CYAN}│${NC} ${BOLD}%-*s${NC} ${CYAN}│${NC}\n" "$TEXT_WIDTH" "LIVE ${ACTION^^} LOGS"
  echo -e "  ${CYAN}├${H_LINE}┤${NC}"
  for ((i=0; i<LOG_LINES; i++)); do
    printf "  ${CYAN}│${NC} %-*s ${CYAN}│${NC}\n" "$TEXT_WIDTH" ""
  done
  echo -e "  ${CYAN}└${H_LINE}┘${NC}"

  local LOG_BUFFER=()
  for ((i=0; i<LOG_LINES; i++)); do LOG_BUFFER+=(""); done
  
  set -o pipefail
  local exit_code=0
  tput civis

  draw_logs() {
    while IFS= read -r line; do
      line="${line//$'\t'/ }"
      line="${line//$'\r'/}"
      LOG_BUFFER=("${LOG_BUFFER[@]:1}" "$line")
      
      tput cuu $(( LOG_LINES + 1 )) 
      
      for ((i=0; i<LOG_LINES; i++)); do
        printf "  ${CYAN}│${NC} ${DIM}%-*.*s${NC} ${CYAN}│${NC}\n" "$TEXT_WIDTH" "$TEXT_WIDTH" "${LOG_BUFFER[$i]}"
      done
      
      echo -e "  ${CYAN}└${H_LINE}┘${NC}"
    done
  }

  if [[ "$ACTION" == "restore" ]]; then
    case "$DB_TYPE" in
      mysql) mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -v "$DB_NAME" < "$DUMP_PATH" 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]} ;;
      postgres)
        if head -c 10 "$DUMP_PATH" | grep -q "PGDMP"; then
          pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -w --no-owner -v "$DUMP_PATH" 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]}
        else
          psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -w -f "$DUMP_PATH" -a 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]}
        fi
        ;;
      mongodb) mongorestore --host "$DB_HOST" --port "$DB_PORT" ${DB_PASS:+--username "$DB_USER" --password "$DB_PASS"} --db "$DB_NAME" -v "$DUMP_PATH" 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]} ;;
    esac
  elif [[ "$ACTION" == "export" ]]; then
    case "$DB_TYPE" in
      mysql) mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" ${DB_PASS:+-p"$DB_PASS"} -v "$DB_NAME" > "$DUMP_PATH" 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]} ;;
      postgres) pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -w -F c -v -f "$DUMP_PATH" 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]} ;;
      mongodb) mongodump --host "$DB_HOST" --port "$DB_PORT" ${DB_PASS:+--username "$DB_USER" --password "$DB_PASS"} --db "$DB_NAME" --archive="$DUMP_PATH" -v 2>&1 | draw_logs; exit_code=${PIPESTATUS[0]} ;;
    esac
  fi

  tput cnorm
  set +o pipefail
  unset PGPASSWORD

  if [ $exit_code -ne 0 ]; then
     error "Process completed with warnings/errors. Check integrity."
  fi
}

# ─── Main Execution ───────────────────────────────────────
main() {
  clear
  step_choose_action
  step_choose_db
  step_check_dependencies
  step_credentials
  step_test_connection
  step_target_db
  step_verify_database
  step_file_config
  step_handle_existing
  step_execute

  echo -e "\n${GREEN}${BOLD}  ✔ ${ACTION^^} COMPLETE${NC}"
  echo -e "${DIM}  ${HR}${NC}"
  echo -e "  Database : ${CYAN}${DB_NAME}${NC}"
  
  if [[ "$ACTION" == "restore" ]]; then
    [[ -n "$BACKUP_NAME" ]] && echo -e "  Old DB   : ${CYAN}${BACKUP_NAME}${NC}"
  else
    echo -e "  Saved To : ${CYAN}${DUMP_PATH}${NC}"
  fi
  echo ""
}

main
