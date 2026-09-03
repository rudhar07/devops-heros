# Networking Fundamentals - Commands Practice

**Name:** Rudhar Bajaj

**Environment:** macOS 26.5.2 (Apple Silicon), hostname Rudhars-MacBook-Pro.local, interface en0 (Wi-Fi)

**Date run:** 3 September 2026 (IST), on my office Wi-Fi

This folder is my submission for the Networking Fundamentals section. The instructor's notes (`ip.md`) and the list of reference repos (`resources.md`) are kept as they were; my own work is this README plus the `outputs/` directory.

Every output block below is a real capture from my laptop. I ran each command once and redirected the result into `outputs/NN-<command>.txt`; the blocks in this README are copied from those files. Where a listing was very long (routing table, ARP cache, Docker image pull progress) I have trimmed it and said so inline with a `[... trimmed ...]` marker. Nothing has been edited or invented, with one deliberate exception: because this repository is public, I removed the MAC addresses of other people's devices on the office Wi-Fi from the routing table and ARP captures (in both the README and the raw files), and one DHCP option that encodes the DHCP server's hardware serial number. Each removal is marked in place. Because I captured `stderr` together with `stdout`, a few blocks include noise such as curl's progress meter; I left it in rather than hand-edit it out, except for one progress line that contains carriage-return characters, which I replaced with a marker because Markdown cannot show it as it really is.

## Table of Contents

| # | Command | Question it answers | Layer |
|---|---------|---------------------|-------|
| 1 | `hostname`, `scutil --get LocalHostName` | What does my machine call itself on the network? | L7 (naming) |
| 2 | `ifconfig en0`, `ipconfig getifaddr en0`, `route get default` | What is my IP, mask, MAC and default gateway? | L2 / L3 |
| 3 | `ping -c 4 google.com`, `ping -c 4 8.8.8.8` | Can I reach the Internet, and is DNS or IP the problem? | L3 (ICMP) |
| 4 | `traceroute -m 15 -q 1 -w 2 google.com` | Which routers does my traffic pass through? | L3 (TTL / ICMP) |
| 5 | `nslookup google.com`, `nslookup -type=mx google.com` | Which resolver do I use and what does it return? | L7 (DNS) |
| 6 | `dig ...` (A, +short, NS, -x) | Full DNS answer detail, name servers, reverse lookup | L7 (DNS) |
| 7 | `host google.com` | Quick A / AAAA / MX summary for a name | L7 (DNS) |
| 8 | `netstat -rn` | Where does the kernel send packets for each destination? | L3 (routing) |
| 9 | `netstat -an \| grep LISTEN` | Which TCP ports are open on my machine (incl. Docker)? | L4 (TCP) |
| 10 | `lsof -nP -iTCP -sTCP:LISTEN \| head -20` | Which process owns each listening port? | L4 (TCP) |
| 11 | `arp -a` | Which MAC address belongs to each IP on my LAN? | L2 (ARP) |
| 12 | `curl -I`, `curl -w '...'`, `curl -v` | Does HTTPS work, how long does each phase take, what does the TLS handshake look like? | L4 - L7 (TCP, TLS, HTTP) |
| 13 | `nc -zv google.com 443`, `nc -zv -G 3 google.com 81` | Is a specific TCP port open, closed or filtered? | L4 (TCP) |
| 14 | `whois example.com \| head -20` | Who registered a domain? | L7 (WHOIS) |
| 15 | `docker run --rm nicolaka/netshoot ...` (`ip addr`, `ip route`, `ss -tuln`, `cat /etc/resolv.conf`) | What do the Linux equivalents look like inside a container? | L2 - L7 |
| 16 | `ipconfig getpacket en0`, `scutil --dns` (extra) | What did DHCP hand me, and why does nslookup talk to 1.1.1.1? | L7 (DHCP / DNS config) |

## Task 1 - Resources practised

### The instructor's notes (`ip.md`)

`ip.md` is a set of class notes on IPv4 addressing: the classful ranges (A: 1-127, B: 128-191, C: 192-223, D: 224-239), the default masks for each class (255.0.0.0, 255.255.0.0, 255.255.255.0), CIDR notation such as `120.27.1.0/8`, how the mask splits an address into a network part and a host part, the private range 10.0.0.0 - 10.255.255.255, and the host-count formula (2^host-bits, minus 2 for the network and broadcast addresses).

I applied these notes to my own address instead of a textbook example. From command 2 below my laptop has `172.20.2.108` with netmask `0xfffff800`:

- `0xfffff800` in binary is `11111111.11111111.11111000.00000000`, which is 21 one-bits, so the network is `172.20.2.108/21` and the dotted mask is `255.255.248.0` (confirmed by `ipconfig getoption en0 subnet_mask`).
- 32 - 21 = 11 host bits, so 2^11 = 2048 addresses, of which 2046 are usable.
- The network address is `172.20.0.0` and the broadcast address is `172.20.7.255`. `ifconfig` printed exactly that broadcast, and it also shows up in `arp -a` mapped to `ff:ff:ff:ff:ff:ff`.
- `172.20.x.x` falls in `172.16.0.0/12`, the private block that sits alongside the `10.0.0.0/8` range listed in `ip.md`. Classfully it would be "Class B", but the /21 mask shows that in practice CIDR, not the class, decides where the network/host split is.

### The instructor's reference repos (`resources.md`)

`resources.md` links to seven repos under `github.com/Nency-Ravaliya`. I read each README through the GitHub API (`gh api repos/Nency-Ravaliya/<repo>/readme`). What they cover, and what I practised from each:

| Repo | What it covers | What I practised |
|------|----------------|------------------|
| Network-Troubleshooting | A ten-step walk-through for "I cannot reach google.com": `ping`, `traceroute`, `netstat -tuln`, `telnet google.com 80`, `sudo tcpdump -i eth0 host google.com`, `nslookup`, `dig`, `curl -I https://www.google.com`, `arp -a`, `systemctl status NetworkManager`. | `ping`, `traceroute`, `netstat`, `nslookup`, `dig`, `curl -I`, `arp -a` (commands 3-9, 11, 12). `telnet` is not shipped on macOS (`command -v telnet` returns nothing), so I used `nc -zv` for the same port test (command 13). `tcpdump` exists at `/usr/sbin/tcpdump` but needs root to capture, so I did not run it. `systemctl` is Linux/systemd only; macOS uses `launchctl`, and the netshoot container has no systemd either, so I skipped it. `netstat -tuln` is Linux syntax; I ran the macOS form `netstat -an \| grep LISTEN` and the modern Linux replacement `ss -tuln` inside the container (command 15). |
| OSI-Network-devices | Maps the OSI layers to devices and attributes: Wi-Fi/cable at L1, switch/bridge and MAC addresses at L2, router and IP at L3, TCP/UDP ports at L4, HTTP/DNS at L5-L7. | I tagged every command in this README with the layer it works at, and the ARP table (L2), routing table (L3), listening ports (L4) and DNS/HTTP/TLS (L7) sections each show that layer's real data. |
| Networking | A step-by-step story of a laptop opening google.com: DHCP lease, ARP for the gateway MAC, routing hop by hop, TCP port 443, then the HTTP request/response. | Commands 16 (the actual DHCP ACK), 11 (gateway MAC in the ARP cache), 4 (the hops), 13 (TCP 443 open) and 12 (the HTTP response) are the real-life version of that story on my machine. |
| Subnetting | Splitting `192.168.1.0/24` into four `/26` subnets: borrow 2 bits, 64 addresses per subnet, 62 usable. | Applied the same method to my `/21` above. |
| IP-quest | Four worked questions: highest host in `/24`, host bits in `255.255.252.0`, hosts in `255.255.248.0`, usable hosts in `/21`. | Q3 and Q4 are literally my network (`255.255.248.0` = `/21`, 2046 usable). I checked the answers against what `ifconfig` reports. |
| IPFIX-NETFLOW-NTP | Concept notes on flow export (5-tuple flows, exporter/collector) and NTP for consistent timestamps. | Concept only; nothing to run locally. I did notice `curl -w` and `dig` both print precise timings, which only make sense if clocks are in sync. |
| How-DHCP-Works | The DORA exchange (Discover, Offer, Request, Acknowledge) and what a lease contains. | `ipconfig getpacket en0` (command 16) prints the real ACK my laptop received: server, lease time, mask, router, DNS servers and T1/T2 timers. |

## Task 2 - Commands, output and what I understood

### 1. `hostname` and `scutil --get LocalHostName`

**What it does:** `hostname` prints the name the kernel uses for this machine; `scutil --get LocalHostName` prints the Bonjour/mDNS name macOS advertises on the local network (the `.local` name without the suffix). I also printed `ComputerName`, which is the human-friendly name shown in Finder and AirDrop.

```bash
hostname
scutil --get LocalHostName
scutil --get ComputerName
```

```text
$ hostname
Rudhars-MacBook-Pro.local

$ scutil --get LocalHostName
Rudhars-MacBook-Pro

$ scutil --get ComputerName
Rudhar’s MacBook Pro
```

**What I understood:** A hostname is just a label at the application layer (L7); it is not what routers or switches use. On macOS the three names are related but stored separately: `hostname` shows `Rudhars-MacBook-Pro.local` because the system derives it from the LocalHostName plus the `.local` mDNS domain, while `ComputerName` is allowed to contain spaces and an apostrophe. The `.local` suffix matters: other devices on my Wi-Fi can find me by multicast DNS (I can see `mdns.mcast.net` at `224.0.0.251` in the ARP output later), but that name means nothing on the public Internet. Raw output: `outputs/01-hostname.txt`.

### 2. `ifconfig en0`, `ipconfig getifaddr en0`, `route get default`

**What it does:** `ifconfig <iface>` dumps the interface's link-layer (MAC) and IP configuration. `ipconfig getifaddr` prints only the IPv4 address, and `ipconfig getoption` reads individual DHCP options. `route get default` asks the kernel which gateway and interface the default route uses. I confirmed `en0` is the active interface first with `route -n get default` (it printed `interface: en0`) and `networksetup -listallhardwareports` (which lists `en0` as the Wi-Fi port).

```bash
ifconfig en0
ipconfig getifaddr en0
ipconfig getoption en0 subnet_mask
ipconfig getoption en0 router
route get default
```

```text
$ ifconfig en0
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
	ether fc:b2:14:b6:6a:8e
	inet6 fe80::8b7:51ec:a7fe:76ec%en0 prefixlen 64 secured scopeid 0xf 
	inet 172.20.2.108 netmask 0xfffff800 broadcast 172.20.7.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active

$ ipconfig getifaddr en0
172.20.2.108

$ ipconfig getoption en0 subnet_mask
255.255.248.0

$ ipconfig getoption en0 router
172.20.0.1

$ route get default
   route to: default
destination: default
       mask: default
    gateway: 172.20.0.1
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
       0         0         0         0         0         0      1500         0 
```

**What I understood:** This one command shows two layers at once. The `ether fc:b2:14:b6:6a:8e` line is my Wi-Fi card's MAC address (L2), which only has meaning on my local segment. The `inet 172.20.2.108 netmask 0xfffff800` line is my L3 identity; the mask in hex is 21 one-bits, so I am on `172.20.0.0/21` (2046 usable hosts, as worked out in Task 1) and the kernel derived the broadcast `172.20.7.255` from it. `route get default` tells me that anything not in `172.20.0.0/21` is handed to the gateway `172.20.0.1` via `en0`, and the `mtu 1500` is the standard Ethernet/Wi-Fi frame payload size. There is only an IPv6 link-local (`fe80::`) address, no global one, which explains why `curl -v` later says `IPv6: (none)` and uses IPv4. Raw output: `outputs/02-ifconfig-ipconfig-route.txt`.

### 3. `ping -c 4 google.com` and `ping -c 4 8.8.8.8`

**What it does:** `ping` sends ICMP Echo Request packets and waits for Echo Replies, printing the round-trip time for each. `-c 4` stops after four packets. Pinging a hostname first requires a DNS lookup; pinging a raw IP does not, which is why the pair is useful.

```bash
ping -c 4 google.com
ping -c 4 8.8.8.8
```

```text
$ ping -c 4 google.com
PING google.com (142.250.66.14): 56 data bytes
64 bytes from 142.250.66.14: icmp_seq=0 ttl=118 time=15.296 ms
64 bytes from 142.250.66.14: icmp_seq=1 ttl=118 time=13.085 ms
64 bytes from 142.250.66.14: icmp_seq=2 ttl=118 time=25.713 ms
64 bytes from 142.250.66.14: icmp_seq=3 ttl=118 time=17.441 ms

--- google.com ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 13.085/17.884/25.713/4.775 ms

$ ping -c 4 8.8.8.8
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: icmp_seq=0 ttl=118 time=14.450 ms
64 bytes from 8.8.8.8: icmp_seq=1 ttl=118 time=21.046 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=118 time=21.307 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=118 time=14.106 ms

--- 8.8.8.8 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 14.106/17.727/21.307/3.453 ms
```

**What I understood:** ICMP lives at L3 next to IP, so ping tests reachability without involving any port or application. Both targets answered all four packets with 0% loss and roughly 13-26 ms, which is what I expect from an Indian office to Google's Mumbai/Chennai edge. The `ttl=118` is interesting: Google's servers usually send with an initial TTL of 128, so 128 - 118 = 10 routers decremented it on the way back, which is in the same ballpark as the 8 hops traceroute finds on the forward path (the two directions do not have to be identical). Because `ping google.com` succeeded, I know DNS resolved the name (to `142.250.66.14`) before ICMP was even sent; if that had failed but `ping 8.8.8.8` had worked, the fault would be DNS, not the network. Raw output: `outputs/03-ping.txt`.

### 4. `traceroute -m 15 -q 1 -w 2 google.com`

**What it does:** `traceroute` sends probes with TTL 1, 2, 3, ... so each router along the path returns an ICMP "Time Exceeded" and reveals itself. `-m 15` caps the hop count, `-q 1` sends one probe per hop instead of three, and `-w 2` waits at most two seconds per probe, which keeps the run fast.

```bash
traceroute -m 15 -q 1 -w 2 google.com
```

```text
$ traceroute -m 15 -q 1 -w 2 google.com
traceroute to google.com (142.250.66.14), 15 hops max, 40 byte packets
 1  172.20.0.1 (172.20.0.1)  10.385 ms
 2  49.200.242.17 (49.200.242.17)  4.769 ms
 3  128.185.120.53 (128.185.120.53)  6.870 ms
 4  116.119.161.147 (116.119.161.147)  13.926 ms
 5  *
 6  142.251.70.211 (142.251.70.211)  14.615 ms
 7  142.251.49.218 (142.251.49.218)  26.043 ms
 8  bom07s35-in-f14.1e100.net (142.250.66.14)  150.261 ms
```

**What I understood:** This is L3 routing made visible. Hop 1 is my default gateway `172.20.0.1`, exactly what `route get default` said. Hop 2 is the first public address, `49.200.242.17`, which is my ISP's edge router; hops 3-4 are the ISP's backbone; hops 6-7 are already inside Google's `142.251.x.x` space; and the final hop resolves to `bom07s35-in-f14.1e100.net`, where `bom` is Google's airport-code naming for Mumbai. Hop 5 printed `*`, meaning that router did not send an ICMP Time Exceeded within two seconds; that is normal for routers configured not to answer and does not mean traffic is lost, since hops 6-8 responded fine. The 150 ms on the last hop is a single sample (`-q 1`) and ping shows the real latency is 13-26 ms, a reminder that routers deprioritise generating ICMP errors, so traceroute timings are hints, not measurements. Raw output: `outputs/04-traceroute.txt`.

### 5. `nslookup google.com` and `nslookup -type=mx google.com`

**What it does:** `nslookup` queries the system's configured DNS resolver. Without a type it asks for A (IPv4) records; `-type=mx` asks for the mail exchanger records that say which servers accept email for the domain.

```bash
nslookup google.com
nslookup -type=mx google.com
```

```text
$ nslookup google.com
Server:		1.1.1.1
Address:	1.1.1.1#53

Non-authoritative answer:
Name:	google.com
Address: 142.250.67.46


$ nslookup -type=mx google.com
Server:		1.1.1.1
Address:	1.1.1.1#53

Non-authoritative answer:
google.com	mail exchanger = 10 smtp.google.com.

Authoritative answers can be found from:
```

**What I understood:** DNS is an L7 protocol carried over UDP/TCP port 53 (`1.1.1.1#53`). The `Server:` line told me something I did not know about my own network: the office DHCP server hands out Cloudflare's `1.1.1.1` as the first resolver (I verified this in command 16). "Non-authoritative" means Cloudflare answered from its cache rather than being the owner of the `google.com` zone. The A record came back as `142.250.67.46`, which differs from the `142.250.66.14` ping used a minute earlier; Google rotates answers for load balancing, so two lookups of the same name are not guaranteed to match. The MX answer `10 smtp.google.com.` shows mail for `google.com` goes to a single host with priority 10 (lower is preferred). Raw output: `outputs/05-nslookup.txt`.

### 6. `dig` (full answer, `+short`, NS records, reverse lookup)

**What it does:** `dig` is the more detailed DNS tool. The plain form prints the whole DNS message including header flags, TTL and timing; `+short` prints only the answer data; `NS` asks for the authoritative name servers of the zone; `-x` does a reverse (PTR) lookup from an IP back to a name.

```bash
dig google.com
dig +short google.com
dig google.com NS +short
dig -x 8.8.8.8 +short
```

```text
$ dig google.com

; <<>> DiG 9.10.6 <<>> google.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 10726
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;google.com.			IN	A

;; ANSWER SECTION:
google.com.		266	IN	A	142.250.67.46

;; Query time: 116 msec
;; SERVER: 1.1.1.1#53(1.1.1.1)
;; WHEN: Thu Sep 03 20:33:31 IST 2026
;; MSG SIZE  rcvd: 55


$ dig +short google.com
142.250.206.14

$ dig google.com NS +short
ns2.google.com.
ns4.google.com.
ns3.google.com.
ns1.google.com.

$ dig -x 8.8.8.8 +short
dns.google.
```

**What I understood:** The full `dig` output is the anatomy of a DNS response at L7. `status: NOERROR` means the name exists; the flags `qr rd ra` mean this is a response (qr), I asked for recursion (rd) and the server supports it (ra). The `266` in the answer section is the TTL in seconds, so Cloudflare will keep serving this cached answer for another ~4.5 minutes before asking Google's authoritative servers again. Two seconds later `+short` returned a different address (`142.250.206.14`), which again shows Google's DNS-based load balancing. The NS query tells me the zone is actually owned by `ns1`-`ns4.google.com`, and the reverse lookup of `8.8.8.8` returning `dns.google.` confirms that IP really belongs to Google Public DNS. Raw output: `outputs/06-dig.txt`.

### 7. `host google.com`

**What it does:** `host` is a compact DNS lookup tool that, given a name, prints its A, AAAA and MX records in one go.

```bash
host google.com
```

```text
$ host google.com
google.com has address 142.250.66.14
google.com has IPv6 address 2404:6800:4007:804::200e
google.com mail is handled by 10 smtp.google.com.
```

**What I understood:** Three record types in three lines, all L7 DNS: an A record (IPv4), an AAAA record (IPv6, `2404:6800:...` is Google's Asia-Pacific range) and the same MX record `nslookup` showed. This time the A record matched the one ping used (`142.250.66.14`), which underlines that the rotation is per query, not per tool. In day-to-day work `host` is what I would reach for when I want a quick answer, `dig` when I need to debug why an answer is wrong, and `nslookup` mainly because it exists on Windows too. Raw output: `outputs/07-host.txt`.

### 8. `netstat -rn` (routing table)

**What it does:** `netstat -r` prints the kernel routing table and `-n` keeps addresses numeric instead of resolving them to names. On macOS the table also includes cached per-host entries (one per neighbour the machine has spoken to), which makes it long.

```bash
netstat -rn
```

The real output is 336 lines. Below I kept the header, the default route, the network routes and the special entries, and trimmed the block of per-host `UHLWI` entries and most of the IPv6 section. The raw capture is in `outputs/08-netstat-rn.txt`, with the same per-host entries removed for privacy.

```text
$ netstat -rn
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            172.20.0.1         UGScg                 en0       
127                127.0.0.1          UCS                   lo0       
127.0.0.1          127.0.0.1          UH                    lo0       
169.254            link#15            UCS                   en0      !
169.254            link#23            UCSI                  en9      !
172.20/21          link#15            UCS                   en0      !
172.20.0.1/32      link#15            UCS                   en0      !
172.20.0.1         d4:b4:c0:a4:ba:e9  UHLWIir               en0   1190
[... about 235 more 172.20.x.x per-host entries (flags UHLWI) removed - one line per neighbour in the ARP cache; other devices' MAC addresses are not published ...]
172.20.2.108/32    link#15            UCS                   en0      !
172.20.2.108       fc:b2:14:b6:6a:8e  UHLWI                 lo0       
172.20.7.255       ff:ff:ff:ff:ff:ff  UHLWbI                en0      !
224.0.0/4          link#15            UmCS                  en0      !
224.0.0.251        1:0:5e:0:0:fb      UHmLWI                en0       
255.255.255.255/32 link#15            UCS                   en0      !

Internet6:
Destination                             Gateway                                 Flags               Netif Expire
default                                 fe80::%utun0                            UGcIg               utun0       
[... IPv6 section trimmed: five more utun default routes plus link-local (fe80::) and multicast (ff00::/8) entries ...]
```

**What I understood:** The routing table is the L3 decision list the kernel walks, most specific prefix first. The line that matters most is `default 172.20.0.1 UGScg en0`: any destination that does not match a more specific route (which in practice means the whole Internet) is sent to the gateway `172.20.0.1` out of `en0`; `U` = up, `G` = via a gateway, `S` = static, `c`/`g` = clone/gateway-related flags. Just above it, `172.20/21 link#15 en0` is my own subnet, and `link#15` instead of an IP means "deliver directly on the link, no gateway needed", which is the L3-to-L2 boundary: for these destinations the kernel ARPs for the MAC instead of forwarding to a router. The `172.20.0.1 d4:b4:c0:a4:ba:e9 UHLWIir` entry is the gateway's resolved MAC with an expiry counter (1190 s), so macOS keeps ARP results inside the routing table itself. The other pieces are the loopback `127/8` on `lo0`, the link-local `169.254/16` block (one on `en0`, one on `en9`, the iPhone-USB interface), the broadcast `172.20.7.255` mapped to `ff:ff:ff:ff:ff:ff`, and multicast `224.0.0/4` including mDNS at `224.0.0.251`. The IPv6 defaults point at `utun` tunnel interfaces (created by VPN/relay software); they only carry IPv6 here and do not affect my IPv4 default route.

### 9. `netstat -an | grep LISTEN` (listening ports)

**What it does:** `netstat -an` lists every socket (`-a` includes listening ones, `-n` keeps numbers) and `grep LISTEN` keeps only TCP sockets waiting for incoming connections. To see which container owns each Docker port I also ran a read-only `docker ps`.

```bash
netstat -an | grep LISTEN
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```

```text
$ netstat -an | grep LISTEN
tcp46      0      0  *.8091                 *.*                    LISTEN     
tcp46      0      0  *.8095                 *.*                    LISTEN     
tcp46      0      0  *.8083                 *.*                    LISTEN     
tcp46      0      0  *.8082                 *.*                    LISTEN     
tcp46      0      0  *.8081                 *.*                    LISTEN     
tcp46      0      0  *.8084                 *.*                    LISTEN     
tcp46      0      0  *.5001                 *.*                    LISTEN     
tcp46      0      0  *.3000                 *.*                    LISTEN     
tcp46      0      0  *.8090                 *.*                    LISTEN     
tcp46      0      0  *.8770                 *.*                    LISTEN     
tcp6       0      0  fe80::f820:84ff:.65493 *.*                    LISTEN     
tcp6       0      0  fe80::f820:84ff:.65492 *.*                    LISTEN     
tcp46      0      0  *.49856                *.*                    LISTEN     
tcp46      0      0  *.49855                *.*                    LISTEN     
tcp6       0      0  *.65206                *.*                    LISTEN     
tcp4       0      0  *.65206                *.*                    LISTEN     
tcp4       0      0  127.0.0.1.51480        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.18431        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.64714        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.53551        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.61445        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.25451        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.8100         *.*                    LISTEN     
tcp46      0      0  *.3010                 *.*                    LISTEN     
tcp46      0      0  *.3001                 *.*                    LISTEN     
tcp4       0      0  127.0.0.1.60283        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.56752        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.9222         *.*                    LISTEN     
tcp4       0      0  127.0.0.1.57344        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.51902        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.51894        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.51893        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.37956        *.*                    LISTEN     
tcp6       0      0  *.5000                 *.*                    LISTEN     
tcp4       0      0  *.5000                 *.*                    LISTEN     
tcp6       0      0  *.7000                 *.*                    LISTEN     
tcp4       0      0  *.7000                 *.*                    LISTEN     

# Supplementary (read-only) - to see which container owns each published port:
$ docker ps --format 'table {{.Names}}	{{.Image}}	{{.Ports}}'
NAMES                                    IMAGE                           PORTS
nginx-bind                               nginx:alpine                    0.0.0.0:8091->80/tcp, [::]:8091->80/tcp
apache-published                         httpd:2.4                       0.0.0.0:8095->80/tcp, [::]:8095->80/tcp
apache-host                              httpd:2.4                       
hello-nginx                              hello-nginx                     0.0.0.0:8083->80/tcp, [::]:8083->80/tcp
hello-react                              hello-react                     0.0.0.0:8082->80/tcp, [::]:8082->80/tcp
hello-apache                             hello-apache                    0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
hello-java                               hello-java                      0.0.0.0:8084->8080/tcp, [::]:8084->8080/tcp
hello-python                             hello-python                    0.0.0.0:5001->5000/tcp, [::]:5001->5000/tcp
hello-nodejs                             hello-nodejs                    0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp
database                                 mysql:8.0                       3306/tcp, 33060/tcp
backend                                  nginx:alpine                    80/tcp
frontend                                 nginx:alpine                    0.0.0.0:8090->80/tcp, [::]:8090->80/tcp
linux-lab                                linux-lab                       
buildx_buildkit_multiplatform-builder0   moby/buildkit:buildx-stable-1   
```

**What I understood:** This is the L4 view: 37 TCP sockets in `LISTEN` state, each identified by address and port. The first block, `*.3000`, `*.5001`, `*.8081`-`*.8084`, `*.8090`, `*.8091` and `*.8095`, are the ports my Docker containers from the earlier sessions publish with `-p host:container`; `docker ps` maps each one (for example `8084->8080` is `hello-java`, `5001->5000` is `hello-python`). They show as `tcp46 *.PORT`, i.e. bound on all IPv4 and IPv6 addresses, so anyone on my Wi-Fi could reach them, not just localhost. Two containers are a good counter-example: `database` only *exposes* `3306/tcp` and `backend` only exposes `80/tcp`, so neither port appears in `netstat`; EXPOSE is documentation, only `-p` actually opens a host port. The `127.0.0.1.*` entries are services that deliberately listen on loopback only (VS Code helpers, a local Python server on 8100, Chrome's remote debugging on 9222) and cannot be reached from the network at all, which is the safer default. `*.5000`/`*.7000` and `*.65206`/`*.8770` are macOS's own AirPlay Receiver and Continuity services (identified in the next command). Raw output: `outputs/09-netstat-listen.txt`.

### 10. `lsof -nP -iTCP -sTCP:LISTEN | head -20`

**What it does:** `lsof` lists open files, and on Unix a socket is a file. `-iTCP` selects TCP sockets, `-sTCP:LISTEN` keeps only listening ones, `-n`/`-P` skip name and port lookups. Unlike `netstat`, it shows the owning process and PID. `head -20` keeps the first 20 lines; since `lsof` sorts by PID and Docker Desktop's backend has a high PID (75790), its lines fall outside the first 20, so I added a `grep` for them.

```bash
lsof -nP -iTCP -sTCP:LISTEN | head -20
lsof -nP -iTCP -sTCP:LISTEN | wc -l
lsof -nP -iTCP -sTCP:LISTEN | grep com.docke
```

```text
$ lsof -nP -iTCP -sTCP:LISTEN | head -20
COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
ControlCe   623 rudhar    9u  IPv4 0xe71ff4efee7534a8      0t0  TCP *:7000 (LISTEN)
ControlCe   623 rudhar   10u  IPv6 0x1cc4b6d1f686383e      0t0  TCP *:7000 (LISTEN)
ControlCe   623 rudhar   11u  IPv4 0x99c1f76e433344c0      0t0  TCP *:5000 (LISTEN)
ControlCe   623 rudhar   12u  IPv6 0xe3a305c9df8ef69f      0t0  TCP *:5000 (LISTEN)
rapportd    632 rudhar   10u  IPv4 0x74470b0e2d76c35c      0t0  TCP *:65206 (LISTEN)
rapportd    632 rudhar   11u  IPv6 0xbfcecd1a5ac02343      0t0  TCP *:65206 (LISTEN)
rapportd    632 rudhar   18u  IPv6 0x3f401309e1ab7ae2      0t0  TCP *:49855 (LISTEN)
rapportd    632 rudhar   20u  IPv6 0x1913eb71c8dfb5cf      0t0  TCP *:49856 (LISTEN)
sharingd    728 rudhar   18u  IPv6 0x2c0664986479ab85      0t0  TCP *:8770 (LISTEN)
Code\x20H  4188 rudhar   37u  IPv4 0x571e7933d98018be      0t0  TCP 127.0.0.1:51893 (LISTEN)
Code\x20H  4189 rudhar   35u  IPv4 0x7535d80a5db19b21      0t0  TCP 127.0.0.1:37956 (LISTEN)
Code\x20H  4189 rudhar   45u  IPv4 0x7f05f96722c5ef45      0t0  TCP 127.0.0.1:51902 (LISTEN)
Code\x20H  4192 rudhar   36u  IPv4  0x2c5c42672d8173a      0t0  TCP 127.0.0.1:51894 (LISTEN)
Code\x20H  4192 rudhar   66u  IPv4 0x4c4f043e26a4805f      0t0  TCP 127.0.0.1:57344 (LISTEN)
python3.1  4488 rudhar    3u  IPv4 0x9001e774cc7f3c43      0t0  TCP 127.0.0.1:8100 (LISTEN)
Code\x20H  6191 rudhar   20u  IPv4 0xe0e04c6600437a4f      0t0  TCP 127.0.0.1:56752 (LISTEN)
Code\x20H  6713 rudhar   20u  IPv4 0xe6c5c3d725431c74      0t0  TCP 127.0.0.1:60283 (LISTEN)
Google     6768 rudhar   69u  IPv4 0x9f8cfcd022c2af36      0t0  TCP 127.0.0.1:9222 (LISTEN)
node      19713 rudhar   13u  IPv6 0x9c6a84326d6c39ce      0t0  TCP *:3001 (LISTEN)

# Supplementary - total listening sockets, and only the Docker Desktop (com.docker.backend) ones:
$ lsof -nP -iTCP -sTCP:LISTEN | wc -l
      37
$ lsof -nP -iTCP -sTCP:LISTEN | grep com.docke
com.docke 75790 rudhar   73u  IPv6 0x78fa575fc7c65f1b      0t0  TCP *:8095 (LISTEN)
com.docke 75790 rudhar  117u  IPv6  0x6864d956fe3183a      0t0  TCP *:8090 (LISTEN)
com.docke 75790 rudhar  135u  IPv6 0xe352b7f1733923dc      0t0  TCP *:3000 (LISTEN)
com.docke 75790 rudhar  136u  IPv6  0xadd9e961fd5ca6a      0t0  TCP *:5001 (LISTEN)
com.docke 75790 rudhar  138u  IPv6 0x7362f94fd0ae6628      0t0  TCP *:8084 (LISTEN)
com.docke 75790 rudhar  142u  IPv6 0xe4e9aaad9f286157      0t0  TCP *:8081 (LISTEN)
com.docke 75790 rudhar  145u  IPv6 0x23437d03dda72653      0t0  TCP *:8091 (LISTEN)
com.docke 75790 rudhar  156u  IPv6  0x38f6350cc85ed00      0t0  TCP *:8082 (LISTEN)
com.docke 75790 rudhar  157u  IPv6 0xc40780acbcc7da01      0t0  TCP *:8083 (LISTEN)
```

**What I understood:** `lsof` answers the question `netstat` cannot: *who* is listening. It is the same L4 information but joined to the process table. The mystery ports from command 9 now have names: `ControlCe` (Control Center) owns 5000 and 7000 for AirPlay Receiver, `rapportd` and `sharingd` are Apple's Continuity/Handoff daemons, the `127.0.0.1` ports belong to `Code Helper` processes of VS Code, and `node` on 3001 is a dev server of mine. The most instructive part is the `grep`: all nine Docker ports are owned by one process, `com.docker.backend` (PID 75790), not by nginx, httpd or Java. That is because on macOS containers run inside a Linux VM; the host-side backend opens the port on the Mac and forwards traffic into the VM, so from the Mac's point of view Docker Desktop itself is the listener. If a port I expected is missing from this list, either the container is not running or it was started without `-p`. Raw output: `outputs/10-lsof-listen.txt`.

### 11. `arp -a`

**What it does:** `arp -a` prints the ARP cache, the table of IP address to MAC address mappings the kernel has learned for hosts on directly attached networks.

```bash
arp -a
```

The real output has 242 entries because the office Wi-Fi is a busy `/21`. I kept the gateway, my own entry and the special entries; the other devices are removed from the raw capture in `outputs/11-arp.txt` as well.

```text
$ arp -a
? (169.254.169.254) at (incomplete) on en0 [ethernet]
rudhars-iphone.local (169.254.249.111) at c6:ac:aa:4b:e6:36 on en9 [ethernet]
? (172.20.0.1) at d4:b4:c0:a4:ba:e9 on en0 ifscope [ethernet]
[... about 235 more 172.20.x.x entries removed - other devices' MAC addresses are not published ...]
? (172.20.2.108) at fc:b2:14:b6:6a:8e on en0 ifscope permanent [ethernet]
? (172.20.7.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
mdns.mcast.net (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
```

**What I understood:** ARP is the glue between L3 and L2: before my laptop can send an IP packet to any host on the same subnet, including the gateway, it has to know that host's MAC address, and this cache is where the answers are stored. The single most important line is `172.20.0.1 at d4:b4:c0:a4:ba:e9`: every packet I send to the Internet is actually put in an Ethernet frame addressed to that MAC, with the real destination IP inside. My own entry is marked `permanent`, and so is `224.0.0.251` (mDNS), whose MAC `01:00:5e:00:00:fb` is the standard multicast mapping rather than a real device. `(incomplete)` next to `169.254.169.254` means something on my machine sent an ARP request for that address and nobody answered, which is what a failed ARP looks like. The `?` means `-a` could not reverse-resolve the IP to a name; the one it could, `rudhars-iphone.local` on `en9`, is my phone over USB, using a self-assigned `169.254.x.x` link-local address because that link has no DHCP server. Seeing ~240 neighbours also explains why the routing table in command 8 was so long.

### 12. `curl -I`, `curl -w` timings and `curl -v` (TLS handshake)

**What it does:** `curl -I` sends an HTTP HEAD request and prints only the response headers. `-s -o /dev/null -w '...'` discards the body and prints timing variables for each phase (DNS, TCP connect, TLS, total). `-v` prints the verbose connection log, including the TLS handshake messages; I kept the first 25 lines with `head -25`.

```bash
curl -I https://example.com
curl -s -o /dev/null -w 'dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}\n' https://example.com
curl -v https://example.com 2>&1 | head -25
```

```text
$ curl -I https://example.com
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
[... one progress-meter redraw line trimmed: curl rewrites it using carriage-return characters, which cannot be reproduced faithfully in Markdown; it is intact in outputs/12-curl.txt ...]
HTTP/2 200 
date: Thu, 03 Sep 2026 15:03:56 GMT
content-type: text/html
server: cloudflare
last-modified: Wed, 02 Sep 2026 22:14:26 GMT
allow: GET, HEAD
accept-ranges: bytes
age: 9768
cf-cache-status: HIT
cf-ray: a355a4e418c77eeb-MAA


$ curl -s -o /dev/null -w 'dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s http=%{http_code}
' https://example.com
dns=0.001927s connect=0.030437s tls=0.067764s total=0.153964s http=200

$ curl -v https://example.com 2>&1 | head -25
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0* Host example.com:443 was resolved.
* IPv6: (none)
* IPv4: 172.66.147.243, 104.20.23.154
*   Trying 172.66.147.243:443...
* Connected to example.com (172.66.147.243) port 443
* ALPN: curl offers h2,http/1.1
* (304) (OUT), TLS handshake, Client hello (1):
} [316 bytes data]
*  CAfile: /etc/ssl/cert.pem
*  CApath: none
* (304) (IN), TLS handshake, Server hello (2):
{ [122 bytes data]
* (304) (IN), TLS handshake, Unknown (8):
{ [19 bytes data]
* (304) (IN), TLS handshake, Certificate (11):
{ [3686 bytes data]
* (304) (IN), TLS handshake, CERT verify (15):
{ [80 bytes data]
* (304) (IN), TLS handshake, Finished (20):
{ [36 bytes data]
* (304) (OUT), TLS handshake, Finished (20):
} [36 bytes data]
* SSL connection using TLSv1.3 / AEAD-CHACHA20-POLY1305-SHA256 / [blank] / UNDEF
```

**What I understood:** This command walks up the stack from L4 to L7 and the timings show each layer's cost. DNS took 1.9 ms because the answer was cached; the TCP three-way handshake finished at 30 ms (about one round trip to Cloudflare's Chennai edge, `MAA` in the `cf-ray` header); the TLS 1.3 handshake finished at 68 ms (one more round trip: `Client hello` out, `Server hello`, `Certificate` and `Finished` in, my `Finished` out, then the connection is `using TLSv1.3 / AEAD-CHACHA20-POLY1305-SHA256`); and the HTTP response arrived at 154 ms. `ALPN: curl offers h2,http/1.1` is how the client and server agreed on HTTP/2 inside the TLS handshake, which is why the status line says `HTTP/2 200`. The headers are the L7 payload: `server: cloudflare`, `cf-cache-status: HIT` and `age: 9768` tell me a CDN cache served this page, and `allow: GET, HEAD` explains why HEAD worked. The `% Total ...` progress-meter lines are curl writing to stderr, which I captured together with stdout; I left the header lines in and trimmed only the one redraw line, because it contains carriage-return characters that Markdown cannot show as they really are. Raw output: `outputs/12-curl.txt`.

### 13. `nc -zv google.com 443` and `nc -zv -G 3 google.com 81`

**What it does:** `nc` (netcat) opens a raw TCP connection. `-z` means "just check whether the port accepts a connection, do not send data", `-v` prints the result, and `-G 3` (macOS flag) caps the connection attempt at three seconds so a filtered port does not hang for a minute.

```bash
nc -zv google.com 443
nc -zv -G 3 google.com 81
```

```text
$ nc -zv google.com 443
Connection to google.com port 443 [tcp/https] succeeded!
exit code: 0

$ nc -zv -G 3 google.com 81
nc: connectx to google.com port 81 (tcp) failed: Operation timed out
exit code: 1
```

**What I understood:** This is a pure L4 test, and the two outcomes teach the difference between reachability and service availability. Port 443 answered the SYN with a SYN-ACK, so the TCP handshake completed and `nc` reported success without ever speaking HTTP. Port 81 produced `Operation timed out` after three seconds, not `Connection refused`: a refusal would mean the host replied with a RST (host up, nothing listening), whereas a timeout means my SYN got no answer at all, which is the signature of a firewall silently dropping packets. So `ping` succeeding (command 3) proves the host is up at L3, `nc` on 443 proves the service is up at L4, and `nc` on 81 shows why "the server is up" and "the port is open" are different questions. This is the modern replacement for the `telnet google.com 80` check in the instructor's troubleshooting guide, since telnet is not installed on macOS. Raw output: `outputs/13-nc.txt`.

### 14. `whois example.com | head -20`

**What it does:** `whois` queries a registry database over TCP port 43 and prints the registration record for a domain (registrar, dates, name servers). `head -20` limits the output.

```bash
whois example.com | head -20
```

```text
$ whois example.com | head -20
% IANA WHOIS server
% for more information on IANA, visit http://www.iana.org
% This query returned 1 object

domain:       EXAMPLE.COM

organisation: Internet Assigned Numbers Authority

created:      1992-01-01
source:       IANA
```

**What I understood:** `whois` worked (macOS ships it at `/usr/bin/whois`), but the record is only nine lines, so `head -20` trimmed nothing. That is because `example.com` is special: it is reserved by IANA for documentation (RFC 2606), so instead of a commercial registrar's long record the IANA WHOIS server answers directly, showing the organisation as the Internet Assigned Numbers Authority and a creation date of 1992. WHOIS is an L7 protocol in its own right, distinct from DNS: DNS tells me where a name points right now, WHOIS tells me who owns it and when it was registered, which is the tool I would use to check whether a suspicious domain was created last week. Raw output: `outputs/14-whois.txt`.

### 15. Linux equivalents inside a throwaway container

**What it does:** `docker run --rm nicolaka/netshoot sh -c '...'` starts a disposable container from the netshoot image (a Linux toolbox for network debugging) and runs the Linux counterparts of the macOS commands above: `ip addr` (like `ifconfig`), `ip route` (like `netstat -rn`), `ss -tuln` (like `netstat -an | grep LISTEN`) and `cat /etc/resolv.conf` (the DNS resolver config). `--rm` deletes the container when it exits.

```bash
docker run --rm nicolaka/netshoot sh -c 'ip addr; echo ---; ip route; echo ---; ss -tuln; echo ---; cat /etc/resolv.conf'
```

The image was not cached locally so Docker pulled it first. I trimmed the 43 layer-progress lines and the eight unused tunnel interfaces (`gre0` ... `ip6gre0`, all `state DOWN`); the complete output is in `outputs/15-docker-linux.txt`.

```text
$ docker run --rm nicolaka/netshoot sh -c 'ip addr; echo ---; ip route; echo ---; ss -tuln; echo ---; cat /etc/resolv.conf'
Unable to find image 'nicolaka/netshoot:latest' locally
latest: Pulling from nicolaka/netshoot
[... 43 image-layer pull progress lines trimmed ...]
Digest: sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
Status: Downloaded newer image for nicolaka/netshoot:latest
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host proto kernel_lo 
       valid_lft forever preferred_lft forever
2: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
[... interfaces 3-10 (gre0, gretap0, erspan0, ip_vti0, ip6_vti0, sit0, ip6tnl0, ip6gre0), all state DOWN, trimmed ...]
11: eth0@if32: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP group default 
    link/ether f2:3a:a3:71:6c:77 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.5/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
---
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.5 
---
Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port
---
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 192.168.65.7

# Based on host file: '/etc/resolv.conf' (legacy)
# Overrides: []
exit code: 0
```

**What I understood:** The container is a complete, separate network stack, which is the point of a network namespace. It has its own L2 identity (`eth0` with MAC `f2:3a:a3:71:6c:77`, a locally administered address Docker generated), its own L3 address `172.17.0.5/16` on Docker's default bridge network, and its own two-line routing table: the subnet is reachable directly on `eth0` and everything else goes `via 172.17.0.1`, the bridge gateway, which is the same pattern as my Mac's `default 172.20.0.1` but one layer of NAT further in. `ss -tuln` printed only its header because nothing in this throwaway container listens on any port, which contrasts nicely with the 37 listeners on my Mac. `/etc/resolv.conf` points at `192.168.65.7`, Docker Desktop's internal DNS forwarder, which relays to the resolvers my Mac learned from DHCP (1.1.1.1 and friends), so the container resolves names without knowing anything about my Wi-Fi. The BSD tools (`ifconfig`, `netstat -rn`, `route`) and the Linux iproute2 tools (`ip addr`, `ip route`, `ss`) show the same concepts with different syntax, and I now know which to reach for on which OS. `eth0@if32` and the `mtu 65535` are artefacts of Docker Desktop's virtualised networking on macOS.

### 16. Extra: `ipconfig getpacket en0` and `scutil --dns`

**What it does:** `ipconfig getpacket en0` prints the last DHCP packet my interface received, i.e. the actual ACK from the DORA exchange described in the instructor's How-DHCP-Works repo. `scutil --dns` prints the resolver configuration macOS built from it. I added this because it ties several earlier outputs together (gateway, mask, and why `nslookup` used `1.1.1.1`). Neither command changes anything.

```bash
ipconfig getpacket en0
scutil --dns | head -25
```

I removed one vendor-specific DHCP option (`option_224`, an opaque hex blob that decodes to the DHCP server's hardware serial number) from the block below and from `outputs/16-dhcp-lease-and-dns-config.txt`.

```text
$ ipconfig getpacket en0
op = BOOTREPLY
htype = 1
flags = 0x0
hlen = 6
hops = 0
xid = 0x7319123d
secs = 0
ciaddr = 0.0.0.0
yiaddr = 172.20.2.108
siaddr = 0.0.0.0
giaddr = 0.0.0.0
chaddr = fc:b2:14:b6:6a:8e
sname = 
file = 
options:
Options count is 10
dhcp_message_type (uint8): ACK 0x5
server_identifier (ip): 172.20.0.1
lease_time (uint32): 0x93a80
subnet_mask (ip): 255.255.248.0
router (ip_mult): {172.20.0.1}
domain_name_server (ip_mult): {1.1.1.1, 8.8.8.8, 103.8.46.5, 103.8.45.5}
renewal_t1_time_value (uint32): 0x49d40
rebinding_t2_time_value (uint32): 0x81330
[... option_224 (opaque vendor data) trimmed ...]
end (none): 

$ scutil --dns | head -25
DNS configuration

resolver #1
  nameserver[0] : 1.1.1.1
  nameserver[1] : 8.8.8.8
  nameserver[2] : 103.8.46.5
  nameserver[3] : 103.8.45.5
  if_index : 15 (en0)
  flags    : Request A records
  reach    : 0x00000002 (Reachable)

resolver #2
  domain   : local
  options  : mdns
  timeout  : 5
  flags    : Request A records
  reach    : 0x00000000 (Not Reachable)
  order    : 300000

resolver #3
  domain   : 254.169.in-addr.arpa
  options  : mdns
  timeout  : 5
  flags    : Request A records
  reach    : 0x00000000 (Not Reachable)
```

**What I understood:** This is the DORA "A" from the How-DHCP-Works repo, captured for real. `dhcp_message_type: ACK` confirms the exchange completed, `chaddr` is my MAC (the L2 address the whole exchange was keyed on, since I had no IP yet), and `yiaddr` ("your IP address") is the `172.20.2.108` that `ifconfig` shows. The server at `172.20.0.1` is both the DHCP server and my router, which is typical of a gateway appliance. The lease options are exactly the values I saw elsewhere: `subnet_mask 255.255.248.0` (the `/21`), `router 172.20.0.1` (the default route) and the DNS list starting with `1.1.1.1` (why `nslookup` and `dig` reported that server). The hex timers convert to `lease_time` 0x93a80 = 604800 s = 7 days, T1 = 302400 s = 3.5 days (when my laptop will start trying to renew, at 50% of the lease) and T2 = 529200 s ≈ 6.1 days (87.5%, when it would broadcast to any server). `scutil --dns` then shows how macOS turned that into resolver #1 on `en0`, with separate mDNS resolvers for `.local` names. Almost every number in this README traces back to this one packet.

## A troubleshooting order

If I had to debug "the Internet is not working" on this laptop, the commands above give me a sequence that isolates one layer at a time, from the closest thing to me outward. In my own words:

1. **Do I have an address?** `ifconfig en0` / `ipconfig getifaddr en0`. If I see `169.254.x.x` or nothing, DHCP failed and the problem is between me and the access point (L1/L2), so nothing further will work. `ipconfig getpacket en0` shows what the lease contained.
2. **Can I reach my gateway?** `route get default` to find it (`172.20.0.1`), then `ping -c 4 172.20.0.1`. A failure here is my Wi-Fi or the router itself; `arp -a` should show the gateway's MAC, and an `(incomplete)` entry means the router is not even answering at L2.
3. **Can I reach the Internet by IP?** `ping -c 4 8.8.8.8`. If the gateway answers but this does not, the fault is upstream of my router (ISP or the router's own uplink), and DNS cannot be blamed yet.
4. **Does name resolution work?** `dig +short google.com` or `nslookup google.com`. If step 3 works but this fails, the problem is DNS: check which server `scutil --dns` lists and try `dig @8.8.8.8 google.com` to see whether a different resolver answers.
5. **Where along the path does it break?** `traceroute -q 1 -w 2 google.com`. The last hop that answers before a run of `*` tells me roughly where packets are being dropped: my network, the ISP, or the far side.
6. **Is the specific port open?** `nc -zv -G 3 host 443`. Reachability at L3 does not mean the service is up at L4; `succeeded` means listening, `Connection refused` means the host is up but nothing is on that port, `Operation timed out` means a firewall is dropping my SYNs.
7. **Does the application layer respond?** `curl -I https://host` (or `curl -v` to watch the TLS handshake). A 200 proves the whole stack works; a certificate error, a 5xx or a hang after `Client hello` tells me the problem is inside TLS or the application, not the network.

For the reverse problem, "my service is not reachable", I start at the other end: `lsof -nP -iTCP -sTCP:LISTEN` or `netstat -an | grep LISTEN` to confirm the process is actually listening, and on which address (`127.0.0.1` means local only, `*` means all interfaces), then `docker ps` if it lives in a container to confirm the port was published with `-p` rather than merely exposed.

## Summary

| Assignment task | What I did | Evidence |
|-----------------|------------|----------|
| Task 1: Practice the commands and repos shared in the devops-hero repo | Read the instructor's `ip.md` notes and applied the classful/CIDR/host-count method to my own `/21` network. Read the READMEs of all seven repos listed in `resources.md` via the GitHub API, summarised what each covers, and practised every command from the Network-Troubleshooting guide that runs on macOS (`ping`, `traceroute`, `netstat`, `nslookup`, `dig`, `curl`, `arp`), substituting `nc` for `telnet` and `ss -tuln` in a Linux container for `netstat -tuln`. Skipped `tcpdump` (needs root) and `systemctl` (Linux-only) and said so. | "Task 1 - Resources practised" section above; commands 2, 3, 4, 5, 6, 8, 9, 11, 12, 13, 15, 16. |
| Task 2: Create an empty .md file, execute the networking commands, add output and a short explanation of each | Created this `README.md` and ran 15 required command groups plus one extra (DHCP/DNS config), each with the real captured output, a description of what it does, and a "What I understood" paragraph tied to the OSI layer it belongs to. Raw, untrimmed captures saved one file per command. | Sections 1-16 above; `outputs/01-hostname.txt` through `outputs/16-dhcp-lease-and-dns-config.txt`. |

### Files in this folder

| File | Owner | Purpose |
|------|-------|---------|
| `ip.md` | Instructor | Class notes on IP addressing (unchanged) |
| `resources.md` | Instructor | Links to the reference repos (unchanged) |
| `README.md` | Me | This write-up |
| `outputs/NN-<command>.txt` | Me | Raw capture of each command, including the exact command line that produced it |
