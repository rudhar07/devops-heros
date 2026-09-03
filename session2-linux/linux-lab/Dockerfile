# Ubuntu with systemd + journald + openssh-server, used as a Linux lab
# on macOS so adduser/useradd/journalctl can be practised for real.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv openssh-server sudo passwd adduser iproute2 less \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN systemctl enable ssh
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
