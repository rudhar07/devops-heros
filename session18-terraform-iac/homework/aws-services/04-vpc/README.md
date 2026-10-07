# VPC: Virtual Private Cloud

A VPC is my own isolated network inside an AWS region. I pick its private IP range, cut it into subnets, and decide the routes and firewalls. A VPC spans **all AZs of one region**, and each **subnet sits in exactly one AZ**.

## CIDR in one minute

`10.20.0.0/16` = the first **16 bits are fixed** (`10.20`) and the remaining 32 − 16 = **16 bits are free**, so 2^16 = 65,536 addresses.

| CIDR | Free bits | Addresses | Usable in an AWS subnet (−5) |
|---|---|---|---|
| /16 | 16 | 65,536 | (max VPC size) |
| /20 | 12 | 4,096 | 4,091 |
| /24 | 8 | 256 | 251 |
| /28 | 4 | 16 | 11 (smallest subnet) |

AWS reserves 5 addresses in every subnet: network, `.1` (VPC router), `.2` (DNS), `.3` (reserved), and the last (broadcast). I checked the maths with Python before building ([`12-vpc.txt`](../../outputs/12-vpc.txt)):

```text
10.30.0.0/16 -> 65536 addresses
/24 subnets that fit: 256 | first three: ['10.30.0.0/24', '10.30.1.0/24', '10.30.2.0/24']
10.30.1.0/24 -> 256 addresses, 251 usable in AWS (5 reserved)
AWS reserves: 10.30.1.0 10.30.1.1 10.30.1.2 10.30.1.3 10.30.1.255
```

LocalStack agreed: each new /24 subnet reported `"FreeIPs": 251`. Use private ranges (RFC 1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`), and don't overlap with networks you may peer or VPN to later.

## Components

| Component | Job |
|---|---|
| **Subnet** | A slice of the VPC CIDR in one AZ. Public or private depending on its route table |
| **Route table** | "Destination → target" rules for a subnet. Every table has the implicit `VPC-CIDR → local` route |
| **Internet Gateway (IGW)** | Attached to the VPC, it gives two-way internet for resources with public IPs. Free, scales by itself |
| **NAT Gateway** | Sits in a *public* subnet and lets *private* subnets reach out (updates, APIs) while blocking inbound connections. Billed per hour + per GB |
| **Security group** | Stateful firewall on an ENI/instance. **Allow rules only**, return traffic is allowed automatically |
| **Network ACL** | Stateless firewall on a **subnet**. Allow **and deny** rules, evaluated in number order, so return traffic (ephemeral ports) must be allowed explicitly |

### Public vs private subnet

The only difference is the route table:

| | Route for `0.0.0.0/0` | Inbound from internet | Outbound to internet | Typical tenants |
|---|---|---|---|---|
| Public subnet | → **IGW** | yes (with a public IP + SG rule) | yes | Load balancers, bastion, NAT GW |
| Private subnet | → **NAT GW** (or none) | no | via NAT only (or not at all) | App servers, databases |

### Security group vs NACL

| | Security group | NACL |
|---|---|---|
| Level | Instance / ENI | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow + deny, numbered |
| Default | Deny all in, allow all out | Default NACL allows all |
| Typical use | Main firewall: "port 443 from the ALB's SG" | Coarse guard rail: "block this bad CIDR" |

## Hands-on against LocalStack

Transcript: [`../../outputs/12-vpc.txt`](../../outputs/12-vpc.txt). I built a public and a private subnet by hand with the CLI, the same thing Terraform automates in session 19:

```text
$ aws ... ec2 create-vpc --cidr-block 10.30.0.0/16 ...
{ "VpcId": "vpc-d569147281d3df57c", "Cidr": "10.30.0.0/16", "State": "available" }
$ aws ... ec2 create-subnet ... --cidr-block 10.30.1.0/24 --availability-zone ap-south-1a ...   # hw18-public
$ aws ... ec2 create-subnet ... --cidr-block 10.30.2.0/24 --availability-zone ap-south-1b ...   # hw18-private
$ aws ... ec2 create-subnet --vpc-id vpc-d569147281d3df57c --cidr-block 10.99.1.0/24
aws: [ERROR]: An error occurred (InvalidSubnet.Range) ... The CIDR '10.99.1.0/24' is invalid.
```

A subnet outside the VPC range is rejected. Next came the IGW, a NAT gateway and two route tables:

```text
$ aws ... ec2 create-internet-gateway ...           igw-a9cf0721d92c6722a
$ aws ... ec2 attach-internet-gateway --internet-gateway-id igw-a9cf0721d92c6722a --vpc-id vpc-d569147281d3df57c
$ aws ... ec2 create-route --route-table-id rtb-eff45b741ea978ce5 --destination-cidr-block 0.0.0.0/0 --gateway-id igw-a9cf0721d92c6722a
$ aws ... ec2 allocate-address --domain vpc ...     eipalloc-dd99001498cb79993
$ aws ... ec2 create-nat-gateway --subnet-id subnet-ff41c3e9949b8a340 (public) --allocation-id eipalloc-dd99...
$ aws ... ec2 create-route --route-table-id rtb-5007b22b54f11b64d --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-7806b074e29a1d39c

$ aws ... ec2 describe-route-tables ... --output table
|  10.30.0.0/16-> local, 0.0.0.0/0-> igw-a9cf0721d92c6722a |  subnet-ff41c3e9949b8a340  |   <- public
|  10.30.0.0/16-> local, 0.0.0.0/0-> nat-7806b074e29a1d39c |  subnet-b17c248ddb720174d  |   <- private
```

The two tables differ only in that one target, IGW or NAT, and that one route is what makes a subnet "public" or "private". The default NACL that came with the VPC:

```text
| Action |    Cidr     | Egress  | Proto  |  Rule   |
|  allow |  0.0.0.0/0  |  True   |  -1    |  100    |
|  deny  |  0.0.0.0/0  |  True   |  -1    |  32767  |
|  allow |  0.0.0.0/0  |  False  |  -1    |  100    |
|  deny  |  0.0.0.0/0  |  False  |  -1    |  32767  |
```

Rule 100 allows everything and the final `32767` (shown as `*` in the console) denies whatever is left. Rules are checked lowest number first, so this NACL allows all.

LocalStack only emulates the API, so no packets actually flow. The NAT gateway's "public" IP came back as `127.100.10.174`, a LocalStack placeholder.
