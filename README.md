# 🗄️ Database Toolkit (`db-toolkit`)

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![MySQL](https://img.shields.io/badge/MySQL-Supported-4479A1.svg?logo=mysql&logoColor=white)](https://www.mysql.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Supported-336791.svg?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![MongoDB](https://img.shields.io/badge/MongoDB-Supported-47A248.svg?logo=mongodb&logoColor=white)](https://www.mongodb.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`db-toolkit` is a unified, interactive terminal utility designed to simplify database **export (backup)** and **import (restore)** operations across MySQL, PostgreSQL, and MongoDB.

Tired of remembering the exact flags for `pg_dump`, `mysqldump`, or `mongorestore`? `db-toolkit` eliminates the friction by providing a **beautiful, step-by-step interactive CLI wizard** that securely prompts for credentials, handles connection testing, and provides a dynamic live-log viewer.

---

## ✨ Key Features

- **🌐 Multi-Engine Support**: Operates seamlessly with MySQL, PostgreSQL, and MongoDB using native binaries.
- **🎨 Interactive TUI (Terminal UI)**: Guided, colored step-by-step CLI with clear prompts, spinners, and structured menus.
- **🛡️ Bulletproof Restore**: Prevents accidental data loss by analyzing existing databases and interactively asking to rename/preserve them before overwriting.
- **📂 Flexible Export Formats**:
  - **MySQL**: Plain SQL, Compressed (`.sql.gz`).
  - **PostgreSQL**: Plain SQL, Custom pg_dump format (`.dump`).
  - **MongoDB**: Archive (`.archive`), Directory format.
- **📊 Dynamic Log Viewer**: A dedicated live-streaming window at the bottom of the terminal tracks execution, filters errors, and maintains running statistics (Warnings, Errors, Lines Processed).
- **🔒 Secure Credential Handling**: Evaluates credentials securely, auto-verifies connections before executing, and properly clears sensitive variables from memory upon exit.

---

## 🛠️ Prerequisites

The toolkit relies on standard Unix/Linux utilities pre-installed on most systems (`awk`, `sed`, `grep`, `tput`, `find`, `sort`, `mktemp`).

Additionally, depending on which database engines you intend to manage, their respective client tools must be installed. The script automatically checks for the presence of the chosen engine's binaries and stops elegantly if they are missing.

### MySQL
```bash
sudo apt install mysql-client  # Ubuntu/Debian
# Requires: mysql, mysqldump
```

### PostgreSQL
```bash
sudo apt install postgresql-client  # Ubuntu/Debian
# Requires: psql, pg_dump, pg_restore, createdb
```

### MongoDB
```bash
# Requires: mongosh, mongorestore, mongodump
# Note: MongoDB database tools need to be installed separately from the server in newer versions.
```

---

## 🚀 Installation

We provide a frictionless, one-line installation script that automatically pulls the latest `db-toolkit` and sets it up globally on your system. 

### Quick Install (Recommended)

Run the following command in your terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/raj5222/DB-Restore-Export-Script/main/install.sh)
```

#### What does the quick install do?
When you run the command above, the `install.sh` script handles the entire setup process automatically:
1. **Downloads the Tool**: It fetches the latest `db-toolkit` executable script directly from the `main` branch of this repository.
2. **Global Availability**: It places the script into a standard binary directory (usually `/usr/local/bin` or `~/bin/`), ensuring you can run it from any folder.
3. **Applies Permissions**: It automatically applies execution permissions (`chmod +x`) so the file is ready to run immediately.
4. **Environment Check**: It ensures the toolkit is properly linked to your system's `$PATH`. 

### Manual Installation (Alternative)

If you prefer to review everything manually, you can clone the repository:

```bash
git clone https://github.com/raj5222/DB-Restore-Export-Script.git
cd DB-Restore-Export-Script
sudo cp db-toolkit /usr/local/bin/
sudo chmod +x /usr/local/bin/db-toolkit
```

---

## 💻 Usage

Once installed, you can start the wizard from anywhere in your terminal by typing:

```bash
db-toolkit
```

### Step-by-Step Workflow

1. **Select Operation**: Choose **Restore** (📥) or **Export** (📤).
2. **Select Engine**: Choose `MySQL`, `PostgreSQL`, or `MongoDB`.
3. **Format Selection**: Choose the input/output format (e.g., Compressed, Archive, Plain SQL).
4. **Connection Setup**: The script prompts for `Host`, `Port`, `Username`, and `Password`. It will run a quick connectivity test (`SELECT 1;` or `ping`) before proceeding.
5. **Target Database**:
   - The script pulls a live list of databases from the server.
   - For **Exports**, select the database to back up.
   - For **Restores**, select where to import the data or type a brand new database name to create it on the fly.
6. **File Discovery**:
   - For **Restores**, the tool recursively finds compatible files (`.sql`, `.dump`, `.archive`, `.gz`) in your current directory up to 3 levels deep. You can select one from the list or enter an absolute path manually.
7. **Execution & Live Logs**: Watch the dynamic TUI process your data, parsing logs to display real-time counters for success, warnings, and fatal errors.

---

## 🛟 The "Safe Restore" Feature

Data is critical. If you attempt to restore into an *already existing database*, `db-toolkit` stops you and asks if you would like to automatically preserve the old data. 

You can choose to safely rename the currently existing database by appending:
- `_old` (e.g., `mydb_old`)
- A timestamp (e.g., `mydb_20260222_143000`)
- A completely custom name

The script automatically handles the complex underlying renaming operations (e.g., table-by-table move for MySQL, terminating active connections and renaming for Postgres, or duplicate-and-drop for MongoDB).

---

## 📋 Error Handling & Logging

When a process finishes, the script groups the outcomes:
- **✅ Success**: The process completed perfectly.
- **⚠️ Ignorable Warnings**: Particularly for Postgres, you might see "Role does not exist" or "Extension missing". These occur when the source environment differs from the local environment, but *the actual database data* is still completely restored. They are logged as non-fatal.
- **❌ Fatal Errors**: Missing files, dropped remote connections, or authentication failures. These represent blocked operations and are printed extensively at the end of the run.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! 

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.
