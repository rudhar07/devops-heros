#!/bin/bash
# system_info.sh
# Prints basic system information (date, hostname, username, disk usage,
# running processes), asks the user for input, creates a directory and a
# file, and saves the running-process list into that file using > redirection.

# ---------- 1. Take user input (read -p) ----------
read -p "Enter your name: " user_name
read -p "Enter a directory name to store the report: " dir_name

# ---------- 2. Store data in variables ----------
current_date=$(date)          # current date and time
host_name=$(hostname)         # machine name
login_user=$(whoami)          # user running the script
file_name="$dir_name/processes.txt"

# ---------- 3. Create the directory and the file ----------
mkdir -p "$dir_name"          # -p: no error if it already exists
touch "$file_name"            # create an empty file

# ---------- 4. Print system information ----------
echo "==================== SYSTEM INFORMATION ===================="
echo "Report for : $user_name"
echo "Date       : $current_date"
echo "Hostname   : $host_name"
echo "Username   : $login_user"
echo

echo "==================== DISK USAGE (df -h) ===================="
df -h
echo

echo "==================== RUNNING PROCESSES (ps) ================"
echo "(first 15 processes shown on screen, the full list goes to the file)"
ps -eo pid,ppid,user,%cpu,%mem,stat,start,time,comm | head -n 15
echo

# ---------- 5. Save running processes to the file with > ----------
ps -eo pid,ppid,user,%cpu,%mem,stat,start,time,comm > "$file_name"

process_count=$(wc -l < "$file_name")
echo "Saved $process_count lines of process information to: $file_name"
echo "Done."
