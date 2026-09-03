# Linux Fundamentals - Homework

**Name:** Rudhar Bajaj
**Environment:** Ubuntu 24.04.4 LTS running as a container with systemd as PID 1 on Docker Desktop (macOS 26.5.2, Apple Silicon, kernel 6.12 linuxkit)

The four tasks are: soft links vs hard links, `adduser` vs `useradd`, `journalctl`,
and the Linux command cheat sheet. Every command output below is real output
from my machine. The raw transcripts are saved in [`outputs/`](outputs).

## Contents

1. [How the Linux lab was set up](#how-the-linux-lab-was-set-up)
2. [Task 1 - Soft link and hard link](#task-1---soft-link-and-hard-link)
3. [Task 2 - adduser vs useradd](#task-2---adduser-vs-useradd)
4. [Task 3 - journalctl](#task-3---journalctl)
5. [Task 4 - Linux command cheat sheet](#task-4---linux-command-cheat-sheet)
6. [Summary](#summary)

---

## How the Linux lab was set up

My laptop runs macOS, and `adduser`, `useradd` and `journalctl` do not exist
there. `journalctl` also needs `systemd-journald` running, which a plain
`docker run ubuntu bash` does not have. So I built a small Ubuntu image with
systemd, `openssh-server` (to have a real service with logs) and the user
management tools, and started it with systemd as PID 1.

Files: [`linux-lab/Dockerfile`](linux-lab/Dockerfile) and
[`linux-lab/lab.sh`](linux-lab/lab.sh) (the script that runs each task and
prints every command before its output).

```bash
docker build -t linux-lab ./linux-lab

docker run -d --name linux-lab --hostname ubuntu-lab --privileged \
  --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp linux-lab

docker exec linux-lab systemctl is-system-running   # prints: running
docker exec -it linux-lab bash                       # interactive shell in the lab
```

---

## Task 1 - Soft link and hard link

### The idea

Every file on a Linux filesystem is really an **inode** (the metadata plus
pointers to the data blocks). A file name in a directory is just a label that
points to an inode.

- A **hard link** is a second name for the same inode. `ls -li` shows the same
  inode number and the link count goes up. Deleting one name does not delete
  the data while another name still points at it.
- A **soft link** (symbolic link) is a separate tiny file whose content is a
  *path* to another file. It has its own inode. If the target is deleted or
  moved, the soft link is left dangling.

### Commands

| Command | Purpose |
| --- | --- |
| `ln original.txt hardlink.txt` | create a hard link |
| `ln -s original.txt softlink.txt` | create a soft (symbolic) link |
| `ls -li` | list files with inode numbers and link counts |
| `stat -c '%i %h' file` | show inode and number of hard links |
| `readlink softlink.txt` | print where a soft link points |
| `rm link` | delete a link (only that name is removed) |

### Practice (real output)

```text
### Environment

$ cat /etc/os-release | head -2; uname -r; whoami; pwd
PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
6.12.76-linuxkit
root
/root/linklab

### Create a file, a hard link and a soft link

$ echo "Hello from the original file" > original.txt

$ ln original.txt hardlink.txt

$ ln -s original.txt softlink.txt

$ ls -li
total 8
892995 -rw-r--r-- 2 root root 29 Sep  3 15:04 hardlink.txt
892995 -rw-r--r-- 2 root root 29 Sep  3 15:04 original.txt
892996 lrwxrwxrwx 1 root root 12 Sep  3 15:04 softlink.txt -> original.txt

$ stat -c '%n  inode=%i  links=%h  type=%F' original.txt hardlink.txt softlink.txt
original.txt  inode=892995  links=2  type=regular file
hardlink.txt  inode=892995  links=2  type=regular file
softlink.txt  inode=892996  links=1  type=symbolic link

$ readlink softlink.txt
original.txt

### Both links show the same content, and follow changes to the original

$ cat hardlink.txt
Hello from the original file

$ cat softlink.txt
Hello from the original file

$ echo "Second line, appended through the original" >> original.txt

$ cat hardlink.txt; echo "---"; cat softlink.txt
Hello from the original file
Second line, appended through the original
---
Hello from the original file
Second line, appended through the original

### Delete the original: hard link survives, soft link dangles

$ rm original.txt

$ ls -li
total 4
892995 -rw-r--r-- 1 root root 72 Sep  3 15:04 hardlink.txt
892996 lrwxrwxrwx 1 root root 12 Sep  3 15:04 softlink.txt -> original.txt

$ cat hardlink.txt
Hello from the original file
Second line, appended through the original

$ cat softlink.txt
cat: softlink.txt: No such file or directory

$ stat -c '%n  links=%h' hardlink.txt
hardlink.txt  links=1

### Directories: soft link allowed, hard link refused

$ ln -s /etc etc-softlink && ls -ld etc-softlink
lrwxrwxrwx 1 root root 4 Sep  3 15:04 etc-softlink -> /etc

$ ln /etc etc-hardlink
ln: /etc: hard link not allowed for directory

### Across filesystems: soft link allowed, hard link refused

$ df -h /root /dev/shm
Filesystem      Size  Used Avail Use% Mounted on
overlay         911G  120G  746G  14% /
shm              64M     0   64M   0% /dev/shm

$ ln hardlink.txt /dev/shm/cross-fs-hardlink
ln: failed to create hard link '/dev/shm/cross-fs-hardlink' => 'hardlink.txt': Invalid cross-device link

$ ln -s /root/linklab/hardlink.txt /dev/shm/cross-fs-softlink && ls -l /dev/shm/
total 0
lrwxrwxrwx 1 root root 26 Sep  3 15:04 cross-fs-softlink -> /root/linklab/hardlink.txt

### Delete the links (deleting a link never touches the data of other links)

$ rm softlink.txt etc-softlink /dev/shm/cross-fs-softlink

$ rm hardlink.txt

$ ls -la
total 8
drwxr-xr-x 2 root root 4096 Sep  3 15:04 .
drwx------ 1 root root 4096 Sep  3 15:04 ..
```

### Soft link vs hard link

| | Hard link | Soft link |
| --- | --- | --- |
| Command | `ln target name` | `ln -s target name` |
| Points to | the inode (the data itself) | a path string |
| Inode number | same as the original | its own inode |
| `ls -l` type | regular file, link count > 1 | `l` type, shows `name -> target` |
| Original deleted | still works, data stays | broken (dangling) link |
| Link directories | not allowed | allowed |
| Cross filesystems | not allowed (`Invalid cross-device link`) | allowed |
| Permissions | shared with the original (same inode) | `lrwxrwxrwx`, target's permissions apply |
| Size | same as the file | length of the path string |

### What I understood

The transcript proves each row of the table. After `ln`, `hardlink.txt` and
`original.txt` showed inode `892995` with a link count of 2, while
`softlink.txt` got inode `892996`. Writing to the original was visible through
both links because they all reach the same data. After `rm original.txt` the
hard link still printed the content and its link count dropped to 1, while
`cat softlink.txt` failed with `No such file or directory` because the path it
stores no longer exists. `ln /etc etc-hardlink` was refused for a directory and
`ln hardlink.txt /dev/shm/...` failed with `Invalid cross-device link`, because
an inode number only makes sense inside one filesystem. A soft link is just a
path, so both of those worked with `ln -s`.

### Interview answers

**Q: What is the difference between a soft link and a hard link?**
A hard link is another directory entry for the same inode, so it is
indistinguishable from the original file and keeps the data alive as long as
one link exists. A soft link is a separate file that stores a path to the
target. It can point to directories and across filesystems, but it breaks if the
target is removed or renamed.

**Q: Why can a hard link not cross filesystems or point to a directory?**
Inode numbers are only unique within one filesystem, so a directory entry on one
filesystem cannot reference an inode on another. Hard-linking directories is
refused because it could create loops in the directory tree and confuse `..`.

**Q: How do you find all hard links of a file?**
`stat` or `ls -li` gives the inode, then `find / -xdev -inum <inode>`.

---

## Task 2 - adduser vs useradd

### The idea

Both commands create users, but they live at different levels:

- **`useradd`** is the low-level binary from the `passwd` package
  (shadow-utils). It exists on every Linux distribution, does exactly what its
  flags say and nothing more: by default no home directory, no password, and
  the shell from `/etc/default/useradd` (`/bin/sh` on Ubuntu).
- **`adduser`** on Debian and Ubuntu is a Perl script that wraps `useradd` and
  `groupadd`. It picks a UID from the configured range, creates a group with
  the same name, creates the home directory, copies `/etc/skel`, fixes
  permissions, adds the user to `users`, and interactively asks for a password
  and full name.

### Practice (real output)

```text
### Which commands exist and what they are

$ which adduser useradd
/usr/sbin/adduser
/usr/sbin/useradd

$ adduser --version | head -1
adduser version 3.137ubuntu1

$ head -1 /usr/sbin/adduser
#! /usr/bin/perl

$ file /usr/sbin/useradd 2>/dev/null || head -c 4 /usr/sbin/useradd | od -c | head -1
0000000 177   E   L   F

$ dpkg -S /usr/sbin/adduser /usr/sbin/useradd
adduser: /usr/sbin/adduser
passwd: /usr/sbin/useradd

### useradd (low level): no home directory unless -m, default shell /bin/sh

$ useradd testuser1

$ id testuser1
uid=1001(testuser1) gid=1001(testuser1) groups=1001(testuser1)

$ grep testuser1 /etc/passwd
testuser1:x:1001:1001::/home/testuser1:/bin/sh

$ ls -ld /home/testuser1
ls: cannot access '/home/testuser1': No such file or directory

$ useradd -m -s /bin/bash -c "Test User Two" testuser2

$ grep testuser2 /etc/passwd
testuser2:x:1002:1002:Test User Two:/home/testuser2:/bin/bash

$ ls -la /home/testuser2
total 20
drwxr-x--- 2 testuser2 testuser2 4096 Sep  3 15:04 .
drwxr-xr-x 1 root      root      4096 Sep  3 15:04 ..
-rw-r--r-- 1 testuser2 testuser2  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 testuser2 testuser2 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 testuser2 testuser2  807 Mar 31  2024 .profile

### adduser (high level, recommended on Ubuntu): creates group, home, copies /etc/skel, sets permissions

$ adduser --gecos "Test User Three" --disabled-password testuser3
info: Adding user `testuser3' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `testuser3' (1003) ...
info: Adding new user `testuser3' (1003) with group `testuser3 (1003)' ...
info: Creating home directory `/home/testuser3' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `testuser3' to supplemental / extra groups `users' ...
info: Adding user `testuser3' to group `users' ...

$ id testuser3
uid=1003(testuser3) gid=1003(testuser3) groups=1003(testuser3),100(users)

$ grep testuser3 /etc/passwd /etc/group
/etc/passwd:testuser3:x:1003:1003:Test User Three,,,:/home/testuser3:/bin/bash
/etc/group:users:x:100:testuser3
/etc/group:testuser3:x:1003:

$ ls -la /home/testuser3
total 20
drwxr-x--- 2 testuser3 testuser3 4096 Sep  3 15:04 .
drwxr-xr-x 1 root      root      4096 Sep  3 15:04 ..
-rw-r--r-- 1 testuser3 testuser3  220 Sep  3 15:04 .bash_logout
-rw-r--r-- 1 testuser3 testuser3 3771 Sep  3 15:04 .bashrc
-rw-r--r-- 1 testuser3 testuser3  807 Sep  3 15:04 .profile

$ echo 'testuser3:Passw0rd!' | chpasswd && passwd -S testuser3
testuser3 P 2026-09-03 0 99999 7 -1

### Defaults each tool reads

$ grep -E '^(DHOME|DSHELL|SKEL|FIRST_UID|LAST_UID|USERGROUPS)=' /etc/adduser.conf

$ grep -E '^(HOME|SHELL|SKEL|CREATE_MAIL_SPOOL)=' /etc/default/useradd
SHELL=/bin/sh

$ getent passwd testuser1 testuser2 testuser3
testuser1:x:1001:1001::/home/testuser1:/bin/sh
testuser2:x:1002:1002:Test User Two:/home/testuser2:/bin/bash
testuser3:x:1003:1003:Test User Three,,,:/home/testuser3:/bin/bash

### Cleanup of the two useradd test users (testuser3 is kept)

$ userdel testuser1 && userdel -r testuser2 && ls /home && getent passwd testuser1 testuser2 || echo "testuser1 and testuser2 removed"
userdel: testuser2 mail spool (/var/mail/testuser2) not found
testuser3
ubuntu
testuser1 and testuser2 removed
```

Note: the `grep` on `/etc/adduser.conf` printed nothing because in adduser
3.137 every setting in that file is shipped commented out, so the built-in
defaults apply (`DHOME=/home`, `DSHELL=/bin/bash`, `SKEL=/etc/skel`,
`FIRST_UID=1000`, `LAST_UID=59999`, `USERGROUPS=yes`).

### Comparison

| | `useradd` | `adduser` (Debian/Ubuntu) |
| --- | --- | --- |
| Type | compiled binary, package `passwd` | Perl script, package `adduser` |
| Available on | every Linux distro | Debian, Ubuntu and derivatives (on RHEL it is just an alias of `useradd`) |
| Interactive | no | yes (asks for password and full name unless told not to) |
| Home directory | only with `-m` | created automatically |
| Copies `/etc/skel` | only with `-m` | yes |
| Default shell | `/bin/sh` (from `/etc/default/useradd`) | `/bin/bash` (from `adduser.conf`) |
| Password | set separately with `passwd` | prompted, or `--disabled-password` |
| Extra groups | none | adds the user to `users` |
| Best for | scripts, automation, portability | creating users by hand on Ubuntu |

### Which command is preferred on Ubuntu and why

On Ubuntu `adduser` is the recommended command for creating a normal user by
hand. It applies the distribution's sensible defaults in one step, so you cannot
forget the home directory or end up with `/bin/sh` as a login shell, which is
exactly what happened with my `useradd testuser1` (no `/home/testuser1`, shell
`/bin/sh`). `useradd` is still the right tool inside scripts and Dockerfiles,
because it is non-interactive, behaves the same on every distribution, and every
option is explicit.

The test user requested by the assignment was created with the recommended
command:

```bash
sudo adduser testuser3          # interactive on a real machine
# in my lab (no terminal for prompts):
adduser --gecos "Test User Three" --disabled-password testuser3
id testuser3                    # uid=1003(testuser3) gid=1003(testuser3) groups=1003(testuser3),100(users)
```

---

## Task 3 - journalctl

### What journalctl is used for

`systemd-journald` is the logging service on every systemd distribution. It
collects kernel messages, the stdout/stderr of every service, syslog messages
and audit records into one binary, indexed journal. `journalctl` is the command
that reads that journal. Because entries are structured (unit name, PID,
priority, boot ID, timestamp), it can filter precisely instead of relying on
`grep` over `/var/log/*.log`.

### Options practised

| Command | What it shows |
| --- | --- |
| `journalctl` | the whole journal, oldest first (pager) |
| `journalctl -n 15` | only the newest 15 lines |
| `journalctl -u ssh` | only the entries of the `ssh.service` unit |
| `journalctl -u ssh -n 5` | newest 5 entries of that service |
| `journalctl -u ssh --since '5 min ago'` | time filter (`--until` also works) |
| `journalctl -f` | follow, like `tail -f` |
| `journalctl -r` | reverse order, newest first |
| `journalctl -b` | current boot only; `-b -1` is the previous boot |
| `journalctl -p warning` | priority filter (emerg, alert, crit, err, warning, notice, info, debug) |
| `journalctl -k` | kernel messages only (like `dmesg`) |
| `journalctl _PID=1` | filter by any journal field, here PID 1 (systemd) |
| `journalctl -o json-pretty` | show the structured fields of each entry |
| `journalctl --list-boots` | boots the journal knows about |
| `journalctl --disk-usage` | space the journal uses |

### Practice (real output)

Before querying I restarted `ssh.service` and made one failed login attempt so
the service would have fresh log lines to look at.

```text
### Generate some fresh ssh log lines first (restart the service, one failed login attempt)

$ systemctl restart ssh && sleep 1

$ ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=3 baduser@localhost true; echo "exit code: $?"
Warning: Permanently added 'localhost' (ED25519) to the list of known hosts.
baduser@localhost: Permission denied (publickey,password).
exit code: 255

$ sleep 1

### What journalctl is: the query tool for systemd-journald

$ systemctl status systemd-journald --no-pager | head -5
● systemd-journald.service - Journal Service
     Loaded: loaded (/usr/lib/systemd/system/systemd-journald.service; static)
    Drop-In: /usr/lib/systemd/system/systemd-journald.service.d
             └─nice.conf
     Active: active (running) since Thu 2026-09-03 15:03:13 UTC; 1min 40s ago

$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.

$ journalctl --list-boots
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
  0 91ba79757a54480b855d9606ce19d16a Thu 2026-09-03 15:03:13 UTC Thu 2026-09-03 15:04:54 UTC

### Whole-system log (newest 15 lines)

$ journalctl --no-pager -n 15
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on 0.0.0.0 port 22.
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on :: port 22.
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]
Sep 03 15:04:53 ubuntu-lab kernel: docker0: port 3(vetha6fdb54) entered disabled state
Sep 03 15:04:53 ubuntu-lab kernel: vethc0f25c1: renamed from eth0
Sep 03 15:04:53 ubuntu-lab kernel: docker0: port 3(vetha6fdb54) entered disabled state
Sep 03 15:04:53 ubuntu-lab kernel: vetha6fdb54 (unregistering): left allmulticast mode
Sep 03 15:04:53 ubuntu-lab kernel: vetha6fdb54 (unregistering): left promiscuous mode
Sep 03 15:04:53 ubuntu-lab kernel: docker0: port 3(vetha6fdb54) entered disabled state
Sep 03 15:04:54 ubuntu-lab kernel: docker0: port 3(veth0f3cb36) entered blocking state
Sep 03 15:04:54 ubuntu-lab kernel: docker0: port 3(veth0f3cb36) entered disabled state
Sep 03 15:04:54 ubuntu-lab kernel: veth0f3cb36: entered allmulticast mode
Sep 03 15:04:54 ubuntu-lab kernel: veth0f3cb36: entered promiscuous mode

### Logs for a specific service: -u ssh

$ journalctl --no-pager -u ssh
Sep 03 15:03:13 ubuntu-lab systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Sep 03 15:03:13 ubuntu-lab sshd[85]: Server listening on 0.0.0.0 port 22.
Sep 03 15:03:13 ubuntu-lab sshd[85]: Server listening on :: port 22.
Sep 03 15:03:13 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:51 ubuntu-lab systemd[1]: Stopping ssh.service - OpenBSD Secure Shell server...
Sep 03 15:04:51 ubuntu-lab sshd[85]: Received signal 15; terminating.
Sep 03 15:04:51 ubuntu-lab systemd[1]: ssh.service: Deactivated successfully.
Sep 03 15:04:51 ubuntu-lab systemd[1]: Stopped ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:51 ubuntu-lab systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on 0.0.0.0 port 22.
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on :: port 22.
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]

$ journalctl --no-pager -u ssh -n 5
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on 0.0.0.0 port 22.
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on :: port 22.
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]

$ journalctl --no-pager -u ssh --since '5 min ago' | tail -6
Sep 03 15:04:51 ubuntu-lab systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on 0.0.0.0 port 22.
Sep 03 15:04:52 ubuntu-lab sshd[291]: Server listening on :: port 22.
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]

$ systemctl status ssh --no-pager | head -12
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/usr/lib/systemd/system/ssh.service; enabled; preset: enabled)
     Active: active (running) since Thu 2026-09-03 15:04:52 UTC; 2s ago
TriggeredBy: ● ssh.socket
       Docs: man:sshd(8)
             man:sshd_config(5)
    Process: 290 ExecStartPre=/usr/sbin/sshd -t (code=exited, status=0/SUCCESS)
   Main PID: 291 (sshd)
      Tasks: 1 (limit: 9519)
     Memory: 1.7M (peak: 3.3M)
        CPU: 33ms
     CGroup: /docker/e15a3eafe1af97cfbfc2f37ab809253d86d7e4737912813fd5a875c63dffb4cf/system.slice/ssh.service

### Filtering: by priority, by boot, by PID, by kernel, reverse, follow

$ journalctl --no-pager -p warning -b | tail -8
Sep 03 15:03:13 ubuntu-lab kernel: pci-host-generic 40000000.pci: Memory resource size exceeds max for 32 bits
Sep 03 15:03:13 ubuntu-lab kernel: netlink: 'initd': attribute type 4 has an invalid length.
Sep 03 15:03:13 ubuntu-lab kernel: fakeowner: loading out-of-tree module taints kernel.
Sep 03 15:03:13 ubuntu-lab kernel: hrtimer: interrupt took 3713042 ns
Sep 03 15:03:13 ubuntu-lab systemd-sysctl[37]: Couldn't write '1' to 'kernel/yama/ptrace_scope', ignoring: No such file or directory

$ journalctl --no-pager -b | head -5
Sep 03 15:03:13 ubuntu-lab kernel: Booting Linux on physical CPU 0x0000000000 [0x610f0000]
Sep 03 15:03:13 ubuntu-lab kernel: Linux version 6.12.76-linuxkit (root@buildkitsandbox) (gcc (Alpine 15.2.0) 15.2.0, GNU ld (GNU Binutils) 2.45.1) #1 SMP Thu Jun 25 13:45:40 UTC 2026
Sep 03 15:03:13 ubuntu-lab kernel: OF: reserved mem: Reserved memory: No reserved-memory node in the DT
Sep 03 15:03:13 ubuntu-lab kernel: Zone ranges:
Sep 03 15:03:13 ubuntu-lab kernel:   DMA      [mem 0x0000000070000000-0x00000000ffffffff]

$ journalctl --no-pager _PID=1 -n 5
Sep 03 15:04:51 ubuntu-lab systemd[1]: Stopping ssh.service - OpenBSD Secure Shell server...
Sep 03 15:04:51 ubuntu-lab systemd[1]: ssh.service: Deactivated successfully.
Sep 03 15:04:51 ubuntu-lab systemd[1]: Stopped ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:51 ubuntu-lab systemd[1]: Starting ssh.service - OpenBSD Secure Shell server...
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.

$ journalctl --no-pager -k | head -5
Sep 03 15:03:13 ubuntu-lab kernel: Booting Linux on physical CPU 0x0000000000 [0x610f0000]
Sep 03 15:03:13 ubuntu-lab kernel: Linux version 6.12.76-linuxkit (root@buildkitsandbox) (gcc (Alpine 15.2.0) 15.2.0, GNU ld (GNU Binutils) 2.45.1) #1 SMP Thu Jun 25 13:45:40 UTC 2026
Sep 03 15:03:13 ubuntu-lab kernel: OF: reserved mem: Reserved memory: No reserved-memory node in the DT
Sep 03 15:03:13 ubuntu-lab kernel: Zone ranges:
Sep 03 15:03:13 ubuntu-lab kernel:   DMA      [mem 0x0000000070000000-0x00000000ffffffff]

$ journalctl --no-pager -u ssh -r -n 3
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.

$ timeout 3 journalctl -f --no-pager -n 3 -u ssh; echo "(journalctl -f keeps following; stopped after 3s with timeout)"
Sep 03 15:04:52 ubuntu-lab systemd[1]: Started ssh.service - OpenBSD Secure Shell server.
Sep 03 15:04:53 ubuntu-lab sshd[295]: Invalid user baduser from ::1 port 44012
Sep 03 15:04:53 ubuntu-lab sshd[295]: Connection closed by invalid user baduser ::1 port 44012 [preauth]
(journalctl -f keeps following; stopped after 3s with timeout)

### Structured output of one entry

$ journalctl --no-pager -u ssh -o json-pretty -n 1 | grep -E "\"(MESSAGE|_PID|_COMM|_SYSTEMD_UNIT|PRIORITY|SYSLOG_IDENTIFIER|_HOSTNAME)\""
	"_SYSTEMD_UNIT" : "ssh.service",
	"_HOSTNAME" : "ubuntu-lab",
	"PRIORITY" : "6",
	"_COMM" : "sshd",
	"MESSAGE" : "Connection closed by invalid user baduser ::1 port 44012 [preauth]",
	"SYSLOG_IDENTIFIER" : "sshd",
	"_PID" : "295",
```

### What I understood

`journalctl -u ssh` gave me the complete story of one service without any
noise: the first start at boot, my `systemctl restart` (signal 15, stop, start),
the new listener on port 22, and then `Invalid user baduser from ::1` for the
failed login. `-n`, `-r`, `--since` and `-f` control *how much* and *in which
order* I see, while `-u`, `-p`, `-k` and `_PID=` control *which* entries. The
`json-pretty` output showed why the filters work: every entry carries fields
such as `_SYSTEMD_UNIT`, `_PID`, `PRIORITY` and `_HOSTNAME`, so `-u ssh` is
just a match on `_SYSTEMD_UNIT=ssh.service`. `-b` and `--list-boots` matter on a
real server because the journal keeps entries from earlier boots, which is how
you investigate a crash after a reboot. When debugging a service the routine is
`systemctl status <unit>` for the current state and `journalctl -u <unit> -n 50`
or `-f` for the history.

---

## Task 4 - Linux command cheat sheet

### Commands and their purpose

| Area | Command | Purpose |
| --- | --- | --- |
| Navigation | `pwd` | print the current directory |
| | `ls -la` | list everything, long format, including hidden files |
| | `cd dir` | change directory |
| Directories and files | `mkdir -p a/b` | create directories, including parents |
| | `touch f` | create an empty file or update its timestamp |
| | `cp src dst` | copy |
| | `mv src dst` | move or rename |
| | `rm -r dir` | delete (recursive for directories) |
| Viewing | `cat f` | print a whole file |
| | `head -n 1 f` / `tail -n 1 f` | first / last lines |
| | `wc -l f` | count lines |
| | `less f` | scroll through a file (q to quit) |
| Searching | `grep -n pattern f` | search inside files, `-r` recursive, `-n` line numbers |
| | `find path -name "*.txt"` | search for files by name |
| Permissions | `chmod 600 f` | set permissions (owner rw only) |
| | `chown user:group f` | change owner and group |
| | `sudo cmd` | run a command as root |
| Users | `whoami`, `id` | current user and its groups |
| System | `uname -a`, `hostname`, `uptime` | kernel, machine name, load |
| Processes | `ps aux` | all processes |
| | `top` | live view (`-bn1` for one batch frame) |
| | `kill PID` | send a signal to a process |
| Disk and memory | `df -h` | disk usage per filesystem |
| | `du -sh dir` | size of a directory |
| | `free -h` | memory and swap |
| Redirection | `>`, `>>`, `\|` | overwrite, append, pipe to another command |

### Practice (real output)

```text
### Navigation and directories

$ pwd
/root/cheatlab

$ ls -la
total 12
drwxr-xr-x 2 root root 4096 Sep  3 15:04 .
drwx------ 1 root root 4096 Sep  3 15:04 ..

$ mkdir -p projects/demo && ls -R
.:
projects

./projects:
demo

./projects/demo:

### Files: create, write, view, copy, move, remove

$ touch projects/demo/notes.txt && ls -l projects/demo
total 0
-rw-r--r-- 1 root root 0 Sep  3 15:04 notes.txt

$ echo "line one" > projects/demo/notes.txt && echo "line two" >> projects/demo/notes.txt && echo "line three" >> projects/demo/notes.txt

$ cat projects/demo/notes.txt
line one
line two
line three

$ head -n 1 projects/demo/notes.txt
line one

$ tail -n 1 projects/demo/notes.txt
line three

$ wc -l projects/demo/notes.txt
3 projects/demo/notes.txt

$ cp projects/demo/notes.txt projects/demo/copy.txt && mv projects/demo/copy.txt projects/demo/renamed.txt && ls -l projects/demo
total 8
-rw-r--r-- 1 root root 29 Sep  3 15:04 notes.txt
-rw-r--r-- 1 root root 29 Sep  3 15:04 renamed.txt

### Searching

$ grep -n two projects/demo/notes.txt
2:line two

$ grep -rn "line" projects/
projects/demo/renamed.txt:1:line one
projects/demo/renamed.txt:2:line two
projects/demo/renamed.txt:3:line three
projects/demo/notes.txt:1:line one
projects/demo/notes.txt:2:line two
projects/demo/notes.txt:3:line three

$ find /root/cheatlab -name "*.txt"
/root/cheatlab/projects/demo/renamed.txt
/root/cheatlab/projects/demo/notes.txt

### Permissions and ownership

$ ls -l projects/demo/notes.txt && chmod 600 projects/demo/notes.txt && ls -l projects/demo/notes.txt
-rw-r--r-- 1 root root 29 Sep  3 15:04 projects/demo/notes.txt
-rw------- 1 root root 29 Sep  3 15:04 projects/demo/notes.txt

$ chown testuser3:testuser3 projects/demo/renamed.txt && ls -l projects/demo/renamed.txt
-rw-r--r-- 1 testuser3 testuser3 29 Sep  3 15:04 projects/demo/renamed.txt

### Users and system

$ whoami
root

$ id
uid=0(root) gid=0(root) groups=0(root)

$ uname -a
Linux ubuntu-lab 6.12.76-linuxkit #1 SMP Thu Jun 25 13:45:40 UTC 2026 aarch64 aarch64 aarch64 GNU/Linux

$ hostname
ubuntu-lab

$ uptime
 15:04:57 up 5 days,  2:46,  0 user,  load average: 0.82, 0.41, 0.18

$ echo $SHELL
/bin/bash

### Processes

$ ps aux | head -n 6
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.1  0.1  20680 11436 ?        Ss   15:03   0:00 /sbin/init
root          24  0.0  0.1  33628 11340 ?        S<s  15:03   0:00 /usr/lib/systemd/systemd-journald
root          81  0.0  0.0   2692  1692 tty1     Ss+  15:03   0:00 /sbin/agetty -o -p -- \u --noclear - linux
root          82  0.0  0.0   2692  1696 tty2     Ss+  15:03   0:00 /sbin/agetty -o -p -- \u --noclear - linux
root          83  0.0  0.0   2692  1688 tty3     Ss+  15:03   0:00 /sbin/agetty -o -p -- \u --noclear - linux

$ top -bn1 | head -n 7
top - 15:04:57 up 5 days,  2:46,  0 user,  load average: 0.82, 0.41, 0.18
Tasks:  13 total,   1 running,  12 sleeping,   0 stopped,   0 zombie
%Cpu(s):  2.0 us,  2.6 sy,  0.0 ni, 88.9 id,  5.9 wa,  0.0 hi,  0.7 si,  0.0 st 
MiB Mem :   7935.3 total,    390.9 free,   1874.7 used,   5868.5 buff/cache     
MiB Swap:   1024.0 total,    942.4 free,     81.6 used.   6060.7 avail Mem 

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND

### Disk and memory

$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
overlay         911G  120G  746G  14% /

$ du -sh /root/cheatlab
20K	/root/cheatlab

$ free -h
               total        used        free      shared  buff/cache   available
Mem:           7.7Gi       1.8Gi       380Mi       152Ki       5.7Gi       5.9Gi
Swap:          1.0Gi        81Mi       942Mi

### Cleanup

$ rm -r projects && ls -la
total 12
drwxr-xr-x 2 root root 4096 Sep  3 15:04 .
drwx------ 1 root root 4096 Sep  3 15:04 ..
```

### What I understood

The commands fall into a few groups and the flags repeat across them: `-r` for
recursive (`rm -r`, `grep -r`), `-h` for human readable (`df -h`, `du -sh`,
`free -h`), `-n` for a number of lines (`head`, `tail`, `journalctl`) or line
numbers (`grep -n`). `ls -l` is the single most useful command because one line
tells me the type, permissions, link count, owner, group, size and date of a
file. `chmod 600` changed `-rw-r--r--` to `-rw-------`, and `chown` handed a
file to `testuser3`, the user created in Task 2. `ps`, `top`, `df`, `du` and
`free` are the first things to run when a machine is slow or full.

---

## Cleanup

```bash
docker rm -f linux-lab
```

## Summary

| Assignment requirement | Where it is done |
| --- | --- |
| Learn the difference between soft and hard links | Task 1 idea and comparison table |
| Learn the commands to create both | `ln` and `ln -s`, commands table |
| Practice creating and deleting soft and hard links | Task 1 transcript, `outputs/task1-links.txt` |
| Prepare as an interview question | Task 1 interview answers |
| Difference between `adduser` and `useradd` | Task 2 idea and comparison table |
| Which is preferred on Ubuntu and why | Task 2, "Which command is preferred" |
| Create a test user with the recommended command | `adduser ... testuser3`, `outputs/task2-adduser-vs-useradd.txt` |
| What `journalctl` is used for | Task 3 introduction |
| View system and service logs | `journalctl -n 15`, `journalctl -u ssh` |
| Check logs for a specific service | `journalctl -u ssh`, `outputs/task3-journalctl.txt` |
| Review and practice the cheat sheet commands | Task 4 table and transcript, `outputs/task4-cheatsheet.txt` |
