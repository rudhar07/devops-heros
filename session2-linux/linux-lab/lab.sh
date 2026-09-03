#!/bin/bash
# Transcript recorder: prints each command with a $ prompt, then its real output.
LABDIR=/root
run() { printf '\n$ %s\n' "$*"; (cd "$LABDIR" && bash -c "$*") 2>&1; }

case "$1" in
task1)
  mkdir -p /root/linklab; LABDIR=/root/linklab
  echo "### Environment"; run 'cat /etc/os-release | head -2; uname -r; whoami; pwd'
  echo; echo "### Create a file, a hard link and a soft link"
  run 'echo "Hello from the original file" > original.txt'
  run 'ln original.txt hardlink.txt'
  run 'ln -s original.txt softlink.txt'
  run 'ls -li'
  run "stat -c '%n  inode=%i  links=%h  type=%F' original.txt hardlink.txt softlink.txt"
  run 'readlink softlink.txt'
  echo; echo "### Both links show the same content, and follow changes to the original"
  run 'cat hardlink.txt'
  run 'cat softlink.txt'
  run 'echo "Second line, appended through the original" >> original.txt'
  run 'cat hardlink.txt; echo "---"; cat softlink.txt'
  echo; echo "### Delete the original: hard link survives, soft link dangles"
  run 'rm original.txt'
  run 'ls -li'
  run 'cat hardlink.txt'
  run 'cat softlink.txt'
  run "stat -c '%n  links=%h' hardlink.txt"
  echo; echo "### Directories: soft link allowed, hard link refused"
  run 'ln -s /etc etc-softlink && ls -ld etc-softlink'
  run 'ln /etc etc-hardlink'
  echo; echo "### Across filesystems: soft link allowed, hard link refused"
  run 'df -h /root /dev/shm'
  run 'ln hardlink.txt /dev/shm/cross-fs-hardlink'
  run 'ln -s /root/linklab/hardlink.txt /dev/shm/cross-fs-softlink && ls -l /dev/shm/'
  echo; echo "### Delete the links (deleting a link never touches the data of other links)"
  run 'rm softlink.txt etc-softlink /dev/shm/cross-fs-softlink'
  run 'rm hardlink.txt'
  run 'ls -la'
  ;;
task2)
  echo "### Which commands exist and what they are"
  run 'which adduser useradd'
  run 'adduser --version | head -1'
  run 'head -1 /usr/sbin/adduser'
  run 'file /usr/sbin/useradd 2>/dev/null || head -c 4 /usr/sbin/useradd | od -c | head -1'
  run "dpkg -S /usr/sbin/adduser /usr/sbin/useradd"
  echo; echo "### useradd (low level): no home directory unless -m, default shell /bin/sh"
  run 'useradd testuser1'
  run 'id testuser1'
  run 'grep testuser1 /etc/passwd'
  run 'ls -ld /home/testuser1'
  run 'useradd -m -s /bin/bash -c "Test User Two" testuser2'
  run 'grep testuser2 /etc/passwd'
  run 'ls -la /home/testuser2'
  echo; echo "### adduser (high level, recommended on Ubuntu): creates group, home, copies /etc/skel, sets permissions"
  run 'adduser --gecos "Test User Three" --disabled-password testuser3'
  run 'id testuser3'
  run 'grep testuser3 /etc/passwd /etc/group'
  run 'ls -la /home/testuser3'
  run "echo 'testuser3:Passw0rd!' | chpasswd && passwd -S testuser3"
  echo; echo "### Defaults each tool reads"
  run "grep -E '^(DHOME|DSHELL|SKEL|FIRST_UID|LAST_UID|USERGROUPS)=' /etc/adduser.conf"
  run "grep -E '^(HOME|SHELL|SKEL|CREATE_MAIL_SPOOL)=' /etc/default/useradd"
  run 'getent passwd testuser1 testuser2 testuser3'
  echo; echo "### Cleanup of the two useradd test users (testuser3 is kept)"
  run 'userdel testuser1 && userdel -r testuser2 && ls /home && getent passwd testuser1 testuser2 || echo "testuser1 and testuser2 removed"'
  ;;
task3)
  echo "### Generate some fresh ssh log lines first (restart the service, one failed login attempt)"
  run 'systemctl restart ssh && sleep 1'
  run 'ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=3 baduser@localhost true; echo "exit code: $?"'
  run 'sleep 1'
  echo; echo "### What journalctl is: the query tool for systemd-journald"
  run 'systemctl status systemd-journald --no-pager | head -5'
  run 'journalctl --disk-usage'
  run 'journalctl --list-boots'
  echo; echo "### Whole-system log (newest 15 lines)"
  run 'journalctl --no-pager -n 15'
  echo; echo "### Logs for a specific service: -u ssh"
  run 'journalctl --no-pager -u ssh'
  run 'journalctl --no-pager -u ssh -n 5'
  run "journalctl --no-pager -u ssh --since '5 min ago' | tail -6"
  run 'systemctl status ssh --no-pager | head -12'
  echo; echo "### Filtering: by priority, by boot, by PID, by kernel, reverse, follow"
  run 'journalctl --no-pager -p warning -b | tail -8'
  run 'journalctl --no-pager -b | head -5'
  run 'journalctl --no-pager _PID=1 -n 5'
  run 'journalctl --no-pager -k | head -5'
  run 'journalctl --no-pager -u ssh -r -n 3'
  run 'timeout 3 journalctl -f --no-pager -n 3 -u ssh; echo "(journalctl -f keeps following; stopped after 3s with timeout)"'
  echo; echo "### Structured output of one entry"
  run 'journalctl --no-pager -u ssh -o json-pretty -n 1 | grep -E "\"(MESSAGE|_PID|_COMM|_SYSTEMD_UNIT|PRIORITY|SYSLOG_IDENTIFIER|_HOSTNAME)\""'
  ;;
task4)
  mkdir -p /root/cheatlab; LABDIR=/root/cheatlab
  echo "### Navigation and directories"
  run 'pwd'
  run 'ls -la'
  run 'mkdir -p projects/demo && ls -R'
  echo; echo "### Files: create, write, view, copy, move, remove"
  run 'touch projects/demo/notes.txt && ls -l projects/demo'
  run 'echo "line one" > projects/demo/notes.txt && echo "line two" >> projects/demo/notes.txt && echo "line three" >> projects/demo/notes.txt'
  run 'cat projects/demo/notes.txt'
  run 'head -n 1 projects/demo/notes.txt'
  run 'tail -n 1 projects/demo/notes.txt'
  run 'wc -l projects/demo/notes.txt'
  run 'cp projects/demo/notes.txt projects/demo/copy.txt && mv projects/demo/copy.txt projects/demo/renamed.txt && ls -l projects/demo'
  echo; echo "### Searching"
  run 'grep -n two projects/demo/notes.txt'
  run 'grep -rn "line" projects/'
  run 'find /root/cheatlab -name "*.txt"'
  echo; echo "### Permissions and ownership"
  run 'ls -l projects/demo/notes.txt && chmod 600 projects/demo/notes.txt && ls -l projects/demo/notes.txt'
  run 'chown testuser3:testuser3 projects/demo/renamed.txt && ls -l projects/demo/renamed.txt'
  echo; echo "### Users and system"
  run 'whoami'
  run 'id'
  run 'uname -a'
  run 'hostname'
  run 'uptime'
  run 'echo $SHELL'
  echo; echo "### Processes"
  run 'ps aux | head -n 6'
  run 'top -bn1 | head -n 7'
  echo; echo "### Disk and memory"
  run 'df -h /'
  run 'du -sh /root/cheatlab'
  run 'free -h'
  echo; echo "### Cleanup"
  run 'rm -r projects && ls -la'
  ;;
esac
