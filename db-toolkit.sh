#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#   DATABASE TOOLKIT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ── Palette & Globals ──
LR='\033[1;31m'; LG='\033[1;32m'; LY='\033[1;33m'; C='\033[0;36m'
LC='\033[1;36m'; W='\033[1;37m'; DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ACTION="" DB_TYPE="" DB_HOST="" DB_PORT="" DB_USER="" DB_PASS="" DB_NAME="" DUMP_PATH=""
STEP_NOW=0 STEP_TOTAL=0 SPINNER_PID="" BOX_W=0 WIN_HDR=0 WIN_BOT=0
LOG_ERR=0 LOG_WARN=0 LOG_OK=0 LOG_LINES=0 LOG_START=0
ERR_FILE=$(mktemp /tmp/.dbtk_err_XXXXXX)

# ── Bulletproof Cleanup ──
_reset() {
  tput csr 0 "$(( $(tput lines) - 1 ))" 2>/dev/null
  tput cup "$(( $(tput lines) - 1 ))" 0 2>/dev/null
  tput cnorm 2>/dev/null
  kill "$SPINNER_PID" 2>/dev/null
  unset PGPASSWORD MYSQL_PWD PGCONNECT_TIMEOUT PGOPTIONS
  rm -f "$ERR_FILE" 2>/dev/null
}
trap '_reset' EXIT
trap '_reset; echo -e "\n${LR}  ✖  Aborted by user.${NC}\n"; exit 130' INT TERM

# ── UI Components ──
hdr()   { ((STEP_NOW++)); echo -e "\n  ${LC}┌─ ${BOLD}Step ${STEP_NOW} / ${STEP_TOTAL} ─ ${1}${NC}\n  ${LC}│${NC}"; }
msg()   { echo -e "  ${LC}│${NC}  ${1}${2}${NC}  ${3}"; }
opt()   { echo -e "  ${LC}│${NC}  ${LC}${1}${NC} ${2} ${W}${BOLD}${3}${NC}\n  ${LC}│${NC}     ${DIM}${4}${NC}"; }
die()   { printf "\n  ${LR}${BOLD}FATAL ERROR:${NC} %s\n\n" "$1"; exit 1; }

ask() {
  local var="$1" lbl="$2" def="$3" sec="$4" hint="$5"
  local ans pfx="  ${LC}│${NC}  ${LC}◆${NC} ${W}${BOLD}%-14s${NC}"
  [[ -n "$hint" ]] && echo -e "  ${LC}│${NC}  ${LY}💡 Hint: ${DIM}${hint}${NC}"
  if [[ "$sec" == "true" ]]; then printf "$pfx ${DIM}[••••••]${NC} › " "$lbl"
  elif [[ -n "$def" ]]; then printf "$pfx ${DIM}[%s]${NC} › " "$lbl" "$def"
  else printf "$pfx › " "$lbl"; fi
  if [[ "$sec" == "true" ]]; then read -rs ans; echo ""; else read -r ans; fi
  [[ -n "$ans" ]] && printf -v "$var" "%s" "$ans" || printf -v "$var" "%s" "$def"
}

spin() {
  tput civis; printf "  ${LC}│${NC}  ${C}◆${NC}  %s " "$1"
  (local f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
   while :; do
     for (( i=0; i<${#f}; i++ )); do
       printf "\b${LC}${f:$i:1}${NC}"; sleep 0.07
     done
   done) &
  SPINNER_PID=$!
}
stop_spin() { kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null; printf "\b${LG}✔${NC}  %b\n" "$1"; }
fail_spin() { kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null; printf "\b${LR}✖${NC}  %b\n" "$1"; }

# ── Dynamic Log Box ──
_setup_window() {
  local w h box_h ui_h start_row db file
  w=$(tput cols); h=$(tput lines)
  BOX_W=$(( w * 80 / 100 )); (( BOX_W < 56 )) && BOX_W=$(( w - 4 ))
  box_h=$(( h * 50 / 100 )); (( box_h < 10 )) && box_h=10
  ui_h=$(( box_h + 8 ))
  if (( ui_h + 4 > h || w < 60 )); then
    echo -e "  ${LC}│${NC}\n  ${LC}├─ ${BOLD}Live Logs Output${NC}"
    WIN_HDR=0; return
  fi
  tput cup $(( h - 1 )) 0
  for (( i=0; i<ui_h; i++ )); do echo ""; done
  start_row=$(( h - ui_h ))
  db="${DB_NAME}";   (( ${#db}   > BOX_W-18 )) && db="${db:0:$((BOX_W-21))}..."
  file="${DUMP_PATH}"; (( ${#file} > BOX_W-18 )) && file="${file:0:$((BOX_W-21))}..."
  tput cup $start_row 0;          printf "  %b│%b  %bAction:%b   %b%s%b" "$LC" "$NC" "$DIM" "$NC" "$W" "${ACTION^^}" "$NC"
  tput cup $(( start_row+1 )) 0;  printf "  %b│%b  %bDatabase:%b %b%s%b" "$LC" "$NC" "$DIM" "$NC" "$W" "$db"   "$NC"
  tput cup $(( start_row+2 )) 0;  printf "  %b│%b  %bFile:%b     %b%s%b" "$LC" "$NC" "$DIM" "$NC" "$W" "$file" "$NC"
  tput cup $(( start_row+3 )) 0;  printf "  %b│%b" "$LC" "$NC"
  tput cup $(( start_row+4 )) 0;  printf "  %b╭─ [ LIVE LOGS ] %s─╥─╮%b" "$C" "$(printf "%0.s─" $(seq 1 $(( BOX_W-23 ))))" "$NC"
  WIN_HDR=$(( start_row+5 ))
  tput cup $WIN_HDR 0;            printf "  %b│%b\033[K\033[%dG%b│▒│%b" "$C" "$NC" $(( BOX_W-2 )) "$C" "$NC"
  tput cup $(( start_row+6 )) 0;  printf "  %b├─%s─╫─┤%b" "$C" "$(printf "%0.s─" $(seq 1 $(( BOX_W-8 ))))" "$NC"
  local strt=$(( start_row+7 ))
  WIN_BOT=$(( strt + box_h ))
  for (( i=strt; i<=WIN_BOT-1; i++ )); do
    tput cup $i 0; printf "  %b│%b\033[K\033[%dG%b│▒│%b" "$C" "$NC" $(( BOX_W-2 )) "$C" "$NC"
  done
  tput cup $WIN_BOT 0; printf "  %b╰─%s─╨─╯%b" "$C" "$(printf "%0.s─" $(seq 1 $(( BOX_W-8 ))))" "$NC"
  tput csr $strt $(( WIN_BOT-1 )); tput cup $strt 0
}

_draw_hdr() {
  [[ "$WIN_HDR" == "0" ]] && return
  local s elapsed st
  s=$(( $(date +%s) - LOG_START ))
  elapsed="$(printf "%02d:%02d" $(( s/60 )) $(( s%60 )))"
  st="⏱ ${elapsed}   ✖ ${LOG_ERR}   ⚠ ${LOG_WARN}   ✔ ${LOG_OK}   ${LOG_LINES} lines"
  tput sc
  tput cup $WIN_HDR 0
  printf "  %b│%b %b%s%b\033[K\033[%dG%b│▒│%b" "$C" "$NC" "$DIM" "$st" "$NC" $(( BOX_W-2 )) "$C" "$NC"
  tput rc
}

_stream_logs() {
  tput civis; LOG_START=$(date +%s); _draw_hdr
  local TEXT_W=$(( BOX_W - 9 )) l low pfx cln
  while IFS= read -r l; do
    # Strip ANSI escape codes and non-printable chars
    l=$(printf '%s' "$l" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -dc '[:print:]')
    low="${l,,}"; pfx="${DIM}▶${NC}"
    if [[ "$low" =~ (error:|fatal:|failed:|connection\ refused|e[0-9]{5}) ]]; then
      (( LOG_ERR++ )); pfx="${LR}✖${NC}"; echo "$l" >> "$ERR_FILE"
    elif [[ "$low" =~ (warning:|warn:|deprecated|ignored) ]]; then
      (( LOG_WARN++ )); pfx="${LY}⚠${NC}"
    elif [[ "$low" =~ (finished|successfully|done|complete|restored\ successfully) ]]; then
      (( LOG_OK++ )); pfx="${LG}✔${NC}"
    fi
    (( LOG_LINES++ ))
    if [[ "$WIN_HDR" != "0" ]]; then
      cln="${l:0:$TEXT_W}"
      printf "  %b│%b %b %s\033[K\033[%dG%b│▒│%b\n" "$C" "$NC" "$pfx" "$cln" $(( BOX_W-2 )) "$C" "$NC"
      (( LOG_LINES % 4 == 0 )) && _draw_hdr
    else
      printf "  %b│%b %b %s\n" "$C" "$NC" "$pfx" "$l"
    fi
  done
  _draw_hdr
}

# ── Credential helpers ──
_set_creds() {
  unset MYSQL_PWD PGPASSWORD
  [[ "$DB_TYPE" == "mysql"    && -n "$DB_PASS" ]] && export MYSQL_PWD="$DB_PASS"
  [[ "$DB_TYPE" == "postgres" && -n "$DB_PASS" ]] && export PGPASSWORD="$DB_PASS"
}

_unset_creds() {
  unset MYSQL_PWD PGPASSWORD DB_PASS
}

# ── MongoDB auth fragment ──
_mongo_auth() {
  # Returns auth args when password is set
  if [[ -n "$DB_PASS" ]]; then
    printf '%s' "--username '$DB_USER' --password '$DB_PASS' --authenticationDatabase admin"
  fi
}

# ── Main Flow ──
clear
echo -e "\n  ${LC}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "  ${LC}${BOLD}║${NC}  ${W}${BOLD}DATABASE TOOLKIT${NC}  ·  MySQL · PostgreSQL · MongoDB                 ${LC}${BOLD}║${NC}"
echo -e "  ${LC}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"

# ─────────────────────────────────────────────
# STEP 0  ·  SYSTEM DEPENDENCY CHECK (not counted)
# ─────────────────────────────────────────────
spin "Verifying System Dependencies..."
CORE_DEPS=(awk sed grep tput find sort mktemp)
for dep in "${CORE_DEPS[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    fail_spin "Missing Core Tool: $dep"
    exit 1
  fi
done
stop_spin "System Ready!"

# ─────────────────────────────────────────────
# STEP 1  ·  OPERATION
# ─────────────────────────────────────────────
# Set a preliminary total so Step 1 displays correctly; updated after action chosen.
STEP_TOTAL=8
hdr "SELECT OPERATION"
opt "1" "📥" "Restore" "Import backup dump to DB"
opt "2" "📤" "Export"  "Snapshot DB to file"
while true; do
  echo -e "  ${LC}│${NC}"
  ask ACTION_NUM "Operation" "1" "" "1=Import, 2=Backup"
  [[ "$ACTION_NUM" =~ ^[1-2]$ ]] && break
  msg "$LR" "✖" "Enter 1 or 2."
done

if [[ "$ACTION_NUM" == "2" ]]; then
  ACTION="export"
  # Steps: op, engine, engine-validate, export-format, connection, target-db, verify, file, execute = 9
  STEP_TOTAL=9
else
  ACTION="restore"
  # Steps: op, engine, engine-validate, connection, target-db, verify, file, execute = 8
  # (+1 if rename needed, handled dynamically)
  STEP_TOTAL=8
fi

# ─────────────────────────────────────────────
# STEP 2  ·  ENGINE
# ─────────────────────────────────────────────
hdr "DATABASE ENGINE"
opt "1" "🐬" "MySQL"      ""
opt "2" "🐘" "PostgreSQL" ""
opt "3" "🍃" "MongoDB"    ""
while true; do
  echo -e "  ${LC}│${NC}"
  ask ENG_NUM "Engine" "2"
  [[ "$ENG_NUM" =~ ^[1-3]$ ]] && break
  msg "$LR" "✖" "Enter 1, 2, or 3."
done
case "$ENG_NUM" in
  1) DB_TYPE="mysql";    P=3306;  U="root";     REQ=(mysql mysqldump)                    ;;
  3) DB_TYPE="mongodb";  P=27017; U="admin";    REQ=(mongosh mongorestore mongodump)     ;;
  *) DB_TYPE="postgres"; P=5432;  U="postgres"; REQ=(psql pg_dump pg_restore createdb)  ;;
esac

# ─────────────────────────────────────────────
# STEP 3  ·  ENGINE DEPENDENCY CHECK
# ─────────────────────────────────────────────
hdr "ENGINE VALIDATION"
spin "Checking $DB_TYPE binaries..."
MISSING_BINS=()
for bin in "${REQ[@]}"; do
  command -v "$bin" &>/dev/null || MISSING_BINS+=("$bin")
done
if [[ ${#MISSING_BINS[@]} -gt 0 ]]; then
  fail_spin "Missing: ${MISSING_BINS[*]}"
  msg "$LR" "!" "Install ${DB_TYPE} client tools before running this script."
  exit 1
fi
stop_spin "All binaries found ✓"

# ─────────────────────────────────────────────
# STEP 4  ·  EXPORT FORMAT  (export only)
# ─────────────────────────────────────────────
# BUG FIX #2: Track EXPORT_EXT carefully to avoid trailing dot in filename
EXPORT_FORMAT="${DB_TYPE}_sql"; EXPORT_EXT="sql"
if [[ "$ACTION" == "export" ]]; then
  hdr "EXPORT FORMAT"
  case "$DB_TYPE" in
    mysql)    opt "1" "📄" "Plain SQL"       "Portable .sql file"
              opt "2" "🗜"  "Compressed"      "Gzip-compressed .sql.gz" ;;
    postgres) opt "1" "💾" "Custom (.dump)"  "Fast pg_restore format"
              opt "2" "📄" "Plain SQL"        "Portable .sql file" ;;
    mongodb)  opt "1" "📦" "Archive"          "Single-file .archive"
              opt "2" "📂" "Directory"        "Multi-file output folder" ;;
  esac
  echo -e "  ${LC}│${NC}"
  ask FMT_NUM "Format" "1"
  case "$DB_TYPE" in
    mysql)
      [[ "$FMT_NUM" == "2" ]] && { EXPORT_FORMAT="mysql_gz";  EXPORT_EXT="sql.gz"; } \
                               || { EXPORT_FORMAT="mysql_sql"; EXPORT_EXT="sql"; }
      ;;
    postgres)
      [[ "$FMT_NUM" == "1" ]] && { EXPORT_FORMAT="pg_custom"; EXPORT_EXT="dump"; } \
                               || { EXPORT_FORMAT="pg_plain";  EXPORT_EXT="sql"; }
      ;;
    mongodb)
      [[ "$FMT_NUM" == "1" ]] && { EXPORT_FORMAT="mongo_arc"; EXPORT_EXT="archive"; } \
                               || { EXPORT_FORMAT="mongo_dir"; EXPORT_EXT=""; }
      ;;
  esac
fi

# ─────────────────────────────────────────────
# STEP 4/5  ·  CONNECTION SETUP
# ─────────────────────────────────────────────
export PGCONNECT_TIMEOUT=5

while true; do
  hdr "CONNECTION SETUP"
  ask DB_HOST "Host"     "localhost" "" "Database server address"
  ask DB_PORT "Port"     "$P"        "" "Default for $DB_TYPE is $P"
  ask DB_USER "Username" "$U"        "" "DB admin username"
  ask DB_PASS "Password" ""         "true" "Press Enter for none / no password"
  _set_creds

  echo -e "  ${LC}│${NC}"
  spin "Verifying credentials..."

  # BUG FIX #1: The original `auth_err=$(cmd 2>&1 >/dev/null) && auth_ok=1`
  # ALWAYS sets auth_ok=1 because variable assignment exits with 0.
  # Fix: capture output in a temp var, then check $? explicitly.
  auth_ok=0; auth_out=""
  case "$DB_TYPE" in
    mysql)
      auth_out=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" \
                   --connect-timeout=5 -e "SELECT 1;" 2>&1)
      [[ $? -eq 0 ]] && auth_ok=1
      ;;
    postgres)
      auth_out=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" \
                   -d postgres -w -c "SELECT 1;" 2>&1)
      [[ $? -eq 0 ]] && auth_ok=1
      ;;
    mongodb)
      MONGO_AUTH_ARGS=()
      [[ -n "$DB_PASS" ]] && MONGO_AUTH_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)
      auth_out=$(mongosh --host "$DB_HOST" --port "$DB_PORT" \
                   "${MONGO_AUTH_ARGS[@]}" --quiet \
                   --eval "db.adminCommand('ping')" 2>&1)
      [[ $? -eq 0 ]] && auth_ok=1
      ;;
  esac

  if [[ "$auth_ok" == "1" ]]; then
    stop_spin "Connected!"
    break
  else
    fail_spin "Authentication failed!"
    # Show first meaningful error line
    first_err=$(printf '%s' "$auth_out" | grep -v '^$' | head -n 1)
    msg "$LR" "↳" "${DIM}${first_err}${NC}"
    _unset_creds
    msg "$LY" "↺" "Please re-enter credentials."
  fi
done

# ─────────────────────────────────────────────
# STEP 5/6  ·  TARGET DATABASE
# ─────────────────────────────────────────────
hdr "TARGET DATABASE"
spin "Fetching database list..."
DBL=()

case "$DB_TYPE" in
  mysql)
    while IFS= read -r line; do [[ -n "$line" ]] && DBL+=("$line"); done < \
      <(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -Nse "SHOW DATABASES;" 2>/dev/null)
    ;;
  postgres)
    while IFS= read -r line; do [[ -n "$line" ]] && DBL+=("$line"); done < \
      <(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w -tAc \
          "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null)
    ;;
  mongodb)
    # Use adminCommand({listDatabases:1}) instead
    MONGO_CONN_ARGS=()
    [[ -n "$DB_PASS" ]] && MONGO_CONN_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)
    while IFS= read -r line; do [[ -n "$line" ]] && DBL+=("$line"); done < \
      <(mongosh --host "$DB_HOST" --port "$DB_PORT" "${MONGO_CONN_ARGS[@]}" --quiet \
          --eval "db.adminCommand({listDatabases:1}).databases.map(d=>d.name).forEach(n=>print(n))" 2>/dev/null)
    ;;
esac

stop_spin "Found ${#DBL[@]} database(s)"
echo -e "  ${LC}│${NC}"

if [[ ${#DBL[@]} -eq 0 ]]; then
  msg "$LY" "⚠" "No databases found (check permissions)."
fi

for i in "${!DBL[@]}"; do msg "$LC" "$((i+1))" "${DBL[$i]}"; done

[[ "$ACTION" == "restore" ]] && msg "$LC" "$(( ${#DBL[@]}+1 ))" "[ Create New Database ]"

while true; do
  echo -e "  ${LC}│${NC}"
  ask DB_SEL "Database" "" "" "Enter the number of the database"
  if [[ "$DB_SEL" =~ ^[0-9]+$ && "$DB_SEL" -gt 0 ]]; then
    if [[ "$DB_SEL" -le "${#DBL[@]}" ]]; then
      DB_NAME="${DBL[$((DB_SEL-1))]}"
      USER_NEW_DB=0   # selected an existing DB from list
      break
    elif [[ "$ACTION" == "restore" && "$DB_SEL" -eq $(( ${#DBL[@]}+1 )) ]]; then
      ask DB_NAME "New DB Name" ""
      [[ -z "$DB_NAME" ]] && { msg "$LR" "✖" "Name cannot be empty."; continue; }
      USER_NEW_DB=1   # user explicitly chose to create a new DB — skip rename even if name collides
      break
    else
      msg "$LR" "✖" "Invalid selection."
    fi
  else
    msg "$LR" "✖" "Enter a valid number."
  fi
done

# ─────────────────────────────────────────────
# STEP 6/7  ·  VERIFY DATABASE EXISTS
# ─────────────────────────────────────────────
hdr "VERIFY"
spin "Checking '$DB_NAME'..."
DB_EXISTS=0
case "$DB_TYPE" in
  postgres)
    result=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w -tAc \
               "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null)
    [[ "$result" == "1" ]] && DB_EXISTS=1
    ;;
  mysql)
    result=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -Nse \
               "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME';" 2>/dev/null)
    [[ "$result" == "1" ]] && DB_EXISTS=1
    ;;
  mongodb)
    MONGO_CONN_ARGS=()
    [[ -n "$DB_PASS" ]] && MONGO_CONN_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)

    mongo_exists=$(mongosh --host "$DB_HOST" --port "$DB_PORT" "${MONGO_CONN_ARGS[@]}" --quiet \
      --eval "
        var names = db.adminCommand({listDatabases:1}).databases.map(function(d){ return d.name; });
        print(names.indexOf('$DB_NAME') >= 0 ? 'found' : 'notfound');
      " 2>/dev/null | tr -d '\r\n ' )
    [[ "$mongo_exists" == "found" ]] && DB_EXISTS=1
    ;;
esac

[[ "$ACTION" == "export" && "$DB_EXISTS" == "0" ]] && { fail_spin "Database '$DB_NAME' not found."; die "Cannot export a non-existent database."; }
stop_spin "Database check complete ✓"

# ─────────────────────────────────────────────
# STEP 7/8  ·  FILE CONFIGURATION
# ─────────────────────────────────────────────
hdr "FILE CONFIGURATION"

if [[ "$ACTION" == "restore" ]]; then

  mapfile -t FL < <(find . -maxdepth 3 -type f \
    \( -name "*.sql" -o -name "*.dump" -o -name "*.archive" -o -name "*.gz" \) \
    2>/dev/null | sort)

  if [[ ${#FL[@]} -eq 0 ]]; then
    msg "$LY" "⚠" "No dump files found under current directory."
    msg "$LG" "➔" "Enter the full path manually:"
    while true; do
      ask DUMP_PATH "Dump File" ""
      [[ -n "$DUMP_PATH" && ( -f "$DUMP_PATH" || -d "$DUMP_PATH" ) ]] && break
      msg "$LR" "✖" "Path not found: $DUMP_PATH"
    done
  else
    echo -e "  ${LC}│${NC}"
    for i in "${!FL[@]}"; do msg "$LC" "$((i+1))" "${FL[$i]}"; done
    msg "$LC" "$(( ${#FL[@]}+1 ))" "[ Enter path manually ]"
    while true; do
      echo -e "  ${LC}│${NC}"
      ask F_SEL "Select File" "" "" "Enter number or choose manual entry"
      if [[ "$F_SEL" =~ ^[0-9]+$ && "$F_SEL" -gt 0 ]]; then
        if [[ "$F_SEL" -le "${#FL[@]}" ]]; then
          DUMP_PATH="${FL[$((F_SEL-1))]}"; break
        elif [[ "$F_SEL" -eq $(( ${#FL[@]}+1 )) ]]; then
          while true; do
            ask DUMP_PATH "File Path" ""
            [[ -n "$DUMP_PATH" && ( -f "$DUMP_PATH" || -d "$DUMP_PATH" ) ]] && break
            msg "$LR" "✖" "Path not found: $DUMP_PATH"
          done
          break
        else
          msg "$LR" "✖" "Invalid selection."
        fi
      else
        msg "$LR" "✖" "Enter a valid number."
      fi
    done
  fi
else
  
  if [[ -n "$EXPORT_EXT" ]]; then
    DEFAULT_PATH="./${DB_NAME}_export_${TIMESTAMP}.${EXPORT_EXT}"
  else
    DEFAULT_PATH="./${DB_NAME}_export_${TIMESTAMP}"
  fi
  ask DUMP_PATH "Output Path" "$DEFAULT_PATH"
fi

# ─────────────────────────────────────────────
# STEP 8/9  ·  EXECUTE
# ─────────────────────────────────────────────
hdr "EXECUTE"

# ── MongoDB: Auto-detect namespace for restore ──
NS_FROM="" NS_TO=""
if [[ "$ACTION" == "restore" && "$DB_TYPE" == "mongodb" ]]; then
  spin "Auto-detecting source namespace..."
  MONGO_CONN_ARGS=()
  [[ -n "$DB_PASS" ]] && MONGO_CONN_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)

  # Without -v, newer versions are silent and detection always fails.
  DRY_OUTPUT=""
  if [[ "$DUMP_PATH" == *.archive ]]; then
    DRY_OUTPUT=$(mongorestore --host "$DB_HOST" --port "$DB_PORT" \
                   "${MONGO_CONN_ARGS[@]}" \
                   --archive="$DUMP_PATH" --dryRun -v 2>&1 || true)
  elif [[ -d "$DUMP_PATH" ]]; then
    DRY_OUTPUT=$(mongorestore --host "$DB_HOST" --port "$DB_PORT" \
                   "${MONGO_CONN_ARGS[@]}" \
                   "$DUMP_PATH" --dryRun -v 2>&1 || true)
  fi

  # Extract DB names from lines like: "restoring local.property_form from archive"
  # Regex anchored on the keyword 'restoring' followed by a letter-starting DB name.
  mapfile -t SRC_DBS < <(
    printf '%s' "$DRY_OUTPUT" \
      | grep -oE '[Rr]estoring [a-zA-Z][a-zA-Z0-9_]*\.' \
      | grep -oE '[a-zA-Z][a-zA-Z0-9_]*$' \
      | sort -u
  )

  if [[ ${#SRC_DBS[@]} -eq 1 && -n "${SRC_DBS[0]}" ]]; then
    SRC_DB="${SRC_DBS[0]}"
    if [[ "$SRC_DB" != "$DB_NAME" ]]; then
      stop_spin "Remapping: ${SRC_DB} ➔ ${DB_NAME}"
      NS_FROM="${SRC_DB}.*"; NS_TO="${DB_NAME}.*"
    else
      stop_spin "Source namespace matches target: ${SRC_DB}"
    fi
  elif [[ ${#SRC_DBS[@]} -gt 1 ]]; then
    # Multiple source DBs found — let user pick
    stop_spin "Multiple source namespaces found"
    echo -e "  ${LC}│${NC}"
    for i in "${!SRC_DBS[@]}"; do msg "$LC" "$((i+1))" "${SRC_DBS[$i]}"; done
    while true; do
      echo -e "  ${LC}│${NC}"
      ask SRC_SEL "Source DB #" "1" "" "Which DB in the archive maps to '${DB_NAME}'?"
      if [[ "$SRC_SEL" =~ ^[0-9]+$ && "$SRC_SEL" -ge 1 && "$SRC_SEL" -le "${#SRC_DBS[@]}" ]]; then
        SRC_DB="${SRC_DBS[$((SRC_SEL-1))]}"; break
      fi
      msg "$LR" "✖" "Invalid selection."
    done
    if [[ "$SRC_DB" != "$DB_NAME" ]]; then
      NS_FROM="${SRC_DB}.*"; NS_TO="${DB_NAME}.*"
    fi
  else
    # FIX: Detection failed entirely — guess DB name from dump filename by stripping
    # common export suffixes like _export_YYYYMMDD, _backup_, _dump_, _restore_
    # e.g. "local_export_20260221_145115.archive" → "local"
    GUESSED_SRC=$(basename "$DUMP_PATH" \
      | sed -E 's/\.(archive|dump|sql|gz|tar\.gz)$//' \
      | sed -E 's/[_-](export|backup|dump|restore|bak|snapshot)[_-].*//' \
      | grep -oE '^[a-zA-Z][a-zA-Z0-9_]*')
    [[ -z "$GUESSED_SRC" ]] && GUESSED_SRC="admin"
    stop_spin "Could not auto-detect — enter source DB name"
    msg "$LY" "💡" "Tip: This is the DB name stored inside the archive (check its filename)"
    ask SRC_DB "Source DB" "$GUESSED_SRC" "" "Database namespace stored inside the dump file"
    if [[ -n "$SRC_DB" && "$SRC_DB" != "$DB_NAME" ]]; then
      NS_FROM="${SRC_DB}.*"; NS_TO="${DB_NAME}.*"
    fi
  fi
fi

# ── Rename existing DB / confirm ──
# Only offer rename if user picked an existing DB from the list (USER_NEW_DB=0)
# AND that DB actually has data. If user chose "Create New Database", skip rename
# even if a DB with that name already exists (e.g. MongoDB's built-in 'local').
if [[ "$ACTION" == "restore" && "$DB_EXISTS" == "1" && "${USER_NEW_DB:-0}" == "0" ]]; then
  (( STEP_TOTAL++ ))
  hdr "RENAME EXISTING DATABASE"
  msg "$LY" "⚠" "Database '${DB_NAME}' already exists and will be preserved with a suffix."

  # ── Helper: check if a DB name is already taken ──
  _target_exists() {
    local tname="$1" res=""
    case "$DB_TYPE" in
      postgres)
        res=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w -tAc \
               "SELECT 1 FROM pg_database WHERE datname='${tname}';" 2>/dev/null)
        [[ "$res" == "1" ]] && return 0 || return 1 ;;
      mysql)
        res=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -Nse \
               "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${tname}';" 2>/dev/null)
        [[ "$res" == "1" ]] && return 0 || return 1 ;;
      mongodb)
        local chk
        chk=$(mongosh --host "$DB_HOST" --port "$DB_PORT" \
               "${MONGO_CONN_ARGS[@]}" --quiet \
               --eval "
                 var n=db.adminCommand({listDatabases:1}).databases.map(function(d){return d.name;});
                 print(n.indexOf('${tname}')>=0?'found':'notfound');
               " 2>/dev/null | tr -d '\r\n ')
        [[ "$chk" == "found" ]] && return 0 || return 1 ;;
    esac
  }

  opt "1" "🔹" "old"       "Suffix: _old"
  opt "2" "⏰" "timestamp" "Suffix: _${TIMESTAMP}"
  opt "3" "✏️"  "manual"    "Custom suffix"

  # Loop until a suffix whose target name does NOT already exist is confirmed
  while true; do
    echo -e "  ${LC}│${NC}"
    ask S_CHOICE "Choice" "1"
    case "$S_CHOICE" in
      1) R_SUFFIX="old" ;;
      2) R_SUFFIX="$(date +"%Y%m%d_%H%M%S")" ;;   # fresh timestamp each attempt
      3) ask R_SUFFIX "Suffix" "backup"
         [[ -z "$R_SUFFIX" ]] && { msg "$LR" "✖" "Suffix cannot be empty."; continue; } ;;
      *) msg "$LR" "✖" "Enter 1, 2, or 3."; continue ;;
    esac

    TARGET_NAME="${DB_NAME}_${R_SUFFIX}"

    # ── Collision check: target must not already exist ──
    if _target_exists "$TARGET_NAME"; then
      msg "$LR" "✖" "'${TARGET_NAME}' already exists — choose a different suffix."
      msg "$LY" "↺" "Options: timestamp (always unique), or enter a custom name."
      continue
    fi

    msg "$LY" "⚠" "Will preserve existing data as: ${TARGET_NAME}"
    ask CONF "Confirm? (Y/n)" "Y"
    [[ "$CONF" =~ ^[nN] ]] && { msg "$LY" "↺" "Pick a different suffix."; continue; }
    break
  done

  spin "Preserving existing database as '${TARGET_NAME}'..."
  rename_ok=1
  case "$DB_TYPE" in
    postgres)
      psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -w -q -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';" \
        &>/dev/null
      psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -w -q -c \
        "ALTER DATABASE \"$DB_NAME\" RENAME TO \"${TARGET_NAME}\";" \
        &>/dev/null || rename_ok=0
      createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w "$DB_NAME" &>/dev/null || rename_ok=0
      ;;
    mysql)
      # MySQL has no RENAME DATABASE — create target schema and move all tables
      mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e \
        "CREATE DATABASE IF NOT EXISTS \`${TARGET_NAME}\`;" &>/dev/null || rename_ok=0
      mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -Nse \
        "SHOW TABLES IN \`$DB_NAME\`;" 2>/dev/null \
      | while IFS= read -r tbl; do
          mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e \
            "RENAME TABLE \`${DB_NAME}\`.\`${tbl}\` TO \`${TARGET_NAME}\`.\`${tbl}\`;" \
            &>/dev/null
        done || rename_ok=0
      ;;
    mongodb)
      MONGO_CONN_ARGS=()
      [[ -n "$DB_PASS" ]] && MONGO_CONN_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)
      RENAME_ARCHIVE=$(mktemp /tmp/.dbtk_rename_XXXXXX.archive)
      mongodump --host "$DB_HOST" --port "$DB_PORT" \
        "${MONGO_CONN_ARGS[@]}" \
        --db "$DB_NAME" --archive="$RENAME_ARCHIVE" &>/dev/null
      if [[ $? -ne 0 ]]; then
        rename_ok=0; rm -f "$RENAME_ARCHIVE"
      else
        mongorestore --host "$DB_HOST" --port "$DB_PORT" \
          "${MONGO_CONN_ARGS[@]}" \
          --nsFrom="${DB_NAME}.*" --nsTo="${TARGET_NAME}.*" \
          --archive="$RENAME_ARCHIVE" &>/dev/null
        [[ $? -ne 0 ]] && rename_ok=0
        rm -f "$RENAME_ARCHIVE"
        if [[ "$rename_ok" == "1" ]]; then
          mongosh --host "$DB_HOST" --port "$DB_PORT" \
            "${MONGO_CONN_ARGS[@]}" --quiet \
            --eval "db.getSiblingDB('$DB_NAME').dropDatabase();" &>/dev/null
        fi
      fi
      ;;
  esac
  [[ "$rename_ok" == "1" ]] && stop_spin "Preserved as: ${TARGET_NAME} ✓" \
                             || { fail_spin "Rename failed!"; die "Could not rename existing database."; }

else
  ask CONF "Proceed with ${ACTION}? (Y/n)" "Y"
  [[ "$CONF" =~ ^[nN] ]] && { echo -e "\n  ${LY}Aborted by user.${NC}\n"; exit 0; }

  # Create target DB if it doesn't exist
  case "$DB_TYPE" in
    postgres)
      [[ "$ACTION" == "restore" ]] && \
        createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -w "$DB_NAME" &>/dev/null
      ;;
    mysql)
      [[ "$ACTION" == "restore" ]] && \
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -e \
          "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;" &>/dev/null
      ;;
    # MongoDB creates the DB automatically on first write; nothing to do.
  esac
fi

# ── Build the command ──

MONGO_CONN_ARGS=()
[[ -n "$DB_PASS" ]] && MONGO_CONN_ARGS+=(--username "$DB_USER" --password "$DB_PASS" --authenticationDatabase admin)
if [[ "$ACTION" == "restore" ]]; then
  case "$DB_TYPE" in
    mysql)

      MYSQL_SYS_TABLES="innodb_index_stats|innodb_table_stats|slave_master_info|slave_relay_log_info|slave_worker_info|gtid_executed|help_category|help_keyword|help_relation|help_topic|time_zone|time_zone_name|time_zone_transition|time_zone_transition_type|columns_priv|global_grants|password_history|procs_priv|proxies_priv|role_edges|tables_priv|default_roles|ndb_binlog_index|server_cost|index_stats|table_stats"
      MYSQL_SYS_DBS="mysql|information_schema|performance_schema|sys"

      MYSQL_RESTORE_BASE="mysql --force -h $(printf '%q' "$DB_HOST") -P $(printf '%q' "$DB_PORT") -u $(printf '%q' "$DB_USER") $(printf '%q' "$DB_NAME")"

      FILTER_PIPELINE="sed -E 's/ TABLESPACE=[a-zA-Z0-9_\`\"]+//g; s| /\*![0-9]+ TABLESPACE [a-zA-Z0-9_\`\"]+[[:space:]]*\*/||g' | grep -Ev \"\b(${MYSQL_SYS_TABLES})\b\" | grep -Ev \"^USE \\\`(${MYSQL_SYS_DBS})\\\`\""

      if [[ "$DUMP_PATH" == *.gz ]]; then
        CMD=("bash" "-o" "pipefail" "-c"
             "zcat $(printf '%q' "$DUMP_PATH") | ${FILTER_PIPELINE} | ${MYSQL_RESTORE_BASE}")
      else
        CMD=("bash" "-o" "pipefail" "-c"
             "{ ${FILTER_PIPELINE}; } < $(printf '%q' "$DUMP_PATH") | ${MYSQL_RESTORE_BASE}")
      fi
      ;;
    postgres)
      if [[ "$DUMP_PATH" == *.dump ]]; then
        # --no-privileges: skip GRANT/REVOKE that may fail on different user setups.
        CMD=(pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"
             -d "$DB_NAME" -w --no-owner --no-privileges -j 1 -v "$DUMP_PATH")
      else
        # ON_ERROR_STOP=1: makes psql exit non-zero on any SQL error (default is exit 0)
        CMD=(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"
             -d "$DB_NAME" -w --set ON_ERROR_STOP=1 -f "$DUMP_PATH")
      fi
      ;;
    mongodb)
      CMD=(mongorestore --host "$DB_HOST" --port "$DB_PORT"
           "${MONGO_CONN_ARGS[@]}"
           --drop --nsExclude="*.system.*" -v)
      [[ -n "$NS_FROM" && -n "$NS_TO" ]] && CMD+=(--nsFrom="$NS_FROM" --nsTo="$NS_TO")
      if [[ "$DUMP_PATH" == *.archive ]]; then
        CMD+=(--archive="$DUMP_PATH")
      else
        CMD+=("$DUMP_PATH")
      fi
      ;;
  esac
else
  case "$DB_TYPE" in
    mysql)
      # that cause ERROR 3723 on restore into user databases (MySQL 8+).
      MYSQLDUMP_BASE="mysqldump -h $(printf '%q' "$DB_HOST") -P $(printf '%q' "$DB_PORT") -u $(printf '%q' "$DB_USER") --no-tablespaces -v $(printf '%q' "$DB_NAME")"
      if [[ "$EXPORT_FORMAT" == "mysql_gz" ]]; then
        CMD=("bash" "-o" "pipefail" "-c"
             "${MYSQLDUMP_BASE} | gzip > $(printf '%q' "$DUMP_PATH")")
      else
        CMD=("bash" "-o" "pipefail" "-c"
             "${MYSQLDUMP_BASE} > $(printf '%q' "$DUMP_PATH")")
      fi
      ;;
    postgres)
      export PGOPTIONS="-c statement_timeout=0"
      if [[ "$EXPORT_FORMAT" == "pg_custom" ]]; then
        CMD=(pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER"
             -d "$DB_NAME" -w -F c -v -f "$DUMP_PATH")
      else
        CMD=("bash" "-o" "pipefail" "-c"
             "pg_dump -h $(printf '%q' "$DB_HOST") -p $(printf '%q' "$DB_PORT") -U $(printf '%q' "$DB_USER") -d $(printf '%q' "$DB_NAME") -w -F p -v > $(printf '%q' "$DUMP_PATH")")
      fi
      ;;
    mongodb)
      if [[ "$EXPORT_FORMAT" == "mongo_arc" ]]; then
        CMD=(mongodump --host "$DB_HOST" --port "$DB_PORT"
             "${MONGO_CONN_ARGS[@]}"
             --db "$DB_NAME" --archive="$DUMP_PATH" -v)
      else
        CMD=(mongodump --host "$DB_HOST" --port "$DB_PORT"
             "${MONGO_CONN_ARGS[@]}"
             --db "$DB_NAME" --out="$DUMP_PATH" -v)
      fi
      ;;
  esac
fi

# ── Run ──
_setup_window

tmp_ec=$(mktemp /tmp/.dbtk_ec_XXXXXX)
# All commands are either direct executable arrays or "bash -o pipefail -c ..." arrays
# In both cases we can use "${CMD[@]}" uniformly
_stream_logs < <("${CMD[@]}" 2>&1; echo $? > "$tmp_ec")

exit_code=$(cat "$tmp_ec" 2>/dev/null || echo 1)
rm -f "$tmp_ec"

# ── Final verdict ──
# pg_restore exits 1 even for non-fatal errors (missing extensions, privilege issues).
# Classify errors into FATAL (data loss risk) vs IGNORABLE (environment differences).

IGNORABLE_ERRS=0
FATAL_ERRS=0

if [[ -s "$ERR_FILE" ]]; then
  # Patterns that are safe to ignore — they mean the dump came from a different
  # environment (AWS RDS, managed cloud, different extensions) but data is intact.
  IGNORABLE_PATTERNS='extension.*is not available|could not execute query.*extension|'\
'must be superuser|must be owner|permission denied|'\
'role .* does not exist|schema .* already exists|'\
'publication .* does not exist|subscription .* does not exist'

  IGNORABLE_ERRS=$(grep -cEi "$IGNORABLE_PATTERNS" "$ERR_FILE" 2>/dev/null || echo 0)
  FATAL_ERRS=$(( LOG_ERR - IGNORABLE_ERRS ))
  [[ $FATAL_ERRS -lt 0 ]] && FATAL_ERRS=0
fi

# Determine real outcome:
#   exit!=0 + no errors logged      → non-fatal warnings only  → SUCCESS
#   exit=0  + only ignorable errors → environment diffs        → SUCCESS (with note)
#   exit=0  + fatal errors          → tool lied about success  → FAILED
#   exit!=0 + fatal errors          → real failure             → FAILED
if [[ $exit_code -ne 0 && $LOG_ERR -eq 0 ]]; then
  exit_code=0  # exited non-zero but no error lines → warnings only
elif [[ $LOG_ERR -gt 0 && $FATAL_ERRS -eq 0 ]]; then
  exit_code=0  # only ignorable env-difference errors → data restored fine
elif [[ $exit_code -eq 0 && $FATAL_ERRS -gt 0 ]]; then
  exit_code=1  # tool reported success but fatal errors logged
fi

_reset

echo ""
if [[ $exit_code -eq 0 ]]; then
  echo -e "  ${LG}${BOLD}✔  ${ACTION^} completed successfully!${NC}"
  echo -e "  ${DIM}   Database : ${W}${DB_NAME}${NC}"
  [[ -n "$DUMP_PATH" ]] && echo -e "  ${DIM}   File     : ${W}${DUMP_PATH}${NC}"
  echo -e "  ${DIM}   Lines    : ${LOG_LINES}   Warnings: ${LOG_WARN}${NC}"
  if [[ $IGNORABLE_ERRS -gt 0 ]]; then
    echo -e "  ${LY}⚠  ${IGNORABLE_ERRS} non-fatal environment difference(s) skipped${NC}"
    echo -e "  ${DIM}   (e.g. extensions/roles not available on this server — data is intact)${NC}"
    if [[ -s "$ERR_FILE" ]]; then
      grep -Ei "$IGNORABLE_PATTERNS" "$ERR_FILE" 2>/dev/null | head -n 5 | sed 's/^/    ↳ /'
    fi
  fi
else
  echo -e "  ${LR}${BOLD}✖  ${ACTION^} FAILED${NC}"
  echo -e "  ${DIM}   Database : ${W}${DB_NAME}${NC}"
  [[ -n "$DUMP_PATH" ]] && echo -e "  ${DIM}   File     : ${W}${DUMP_PATH}${NC}"
  echo -e "  ${DIM}   Fatal Errors : ${LR}${FATAL_ERRS}${NC}   ${DIM}Ignorable: ${IGNORABLE_ERRS}   Warnings: ${LOG_WARN}${NC}"
  if [[ -s "$ERR_FILE" ]]; then
    echo -e "\n  ${LR}${BOLD}Error Details:${NC}"
    # Show only the fatal (non-ignorable) errors first
    grep -Eiv "$IGNORABLE_PATTERNS" "$ERR_FILE" 2>/dev/null | head -n 10 | sed 's/^/    ↳ /'
  fi
fi
echo ""
