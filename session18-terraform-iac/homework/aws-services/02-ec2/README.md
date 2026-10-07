# EC2: Elastic Compute Cloud

EC2 rents virtual machines (**instances**) by the second. It's IaaS: AWS runs the hardware and hypervisor, and I own everything from the OS up (patches, software, firewall rules on the instance). An instance lives in one **subnet**, so in one Availability Zone.

## Key pieces

| Piece | What it is |
|---|---|
| **AMI** (Amazon Machine Image) | The template disk: OS + preinstalled software + launch settings. Regional, with a different ID per region. Examples: Amazon Linux 2023, Ubuntu 24.04, or your own "golden image" |
| **Instance type** | Size and family of the VM: vCPU, RAM, network, sometimes local disk or GPU |
| **Key pair** | SSH public key placed on the instance at launch. AWS keeps the public half and you keep the `.pem` private half. AWS can't recover it |
| **Security group** | Stateful virtual firewall attached to the instance's network interface. Allow rules only |
| **EBS volume** | Network block storage (the "disk"). Survives stop/start, can be snapshotted, and is tied to one AZ |
| **Instance store** | Physically attached disk on some types. Fast, but **wiped on stop/terminate** |
| **User data** | Script run once at first boot (install packages, pull config) |
| **IAM instance profile** | Gives the instance a role, so apps get temporary credentials and no keys are stored on disk |

### Instance type naming

`m7g.large` = family **m** (general purpose), generation **7**, attribute **g** (Graviton/ARM), size **large**.

| Family | Optimised for | Typical use |
|---|---|---|
| `t` (t3, t4g) | Burstable CPU (credits) | Dev boxes, small sites |
| `m` | Balanced CPU:RAM (1:4) | App servers |
| `c` | Compute (1:2) | Batch, encoding, CPU-bound APIs |
| `r`, `x` | Memory (1:8 and up) | Caches, in-memory DBs |
| `i`, `d` | Local NVMe storage | High-IOPS databases |
| `p`, `g`, `inf` | GPU / accelerators | ML, graphics |

### EBS volume types (short)

| Type | Kind | Use |
|---|---|---|
| `gp3` | SSD, baseline 3000 IOPS, tunable | Default for almost everything |
| `io2` | SSD, provisioned IOPS | Large databases |
| `st1` / `sc1` | HDD throughput / cold | Logs, big sequential data |

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| From | The subnet CIDR | AWS's pool, if the subnet/launch asks for it | Allocated to your account |
| Reachable from | Inside the VPC (and peered/VPN networks) | The internet, if the route table and SG allow it | The internet |
| On stop/start | Kept | **Changes** | Kept until you release it |

The instance OS only ever sees its private IP. The Internet Gateway does the 1:1 translation to the public IP.

## Instance lifecycle

```text
          launch
            |
            v
        pending --> running --stop--> stopping --> stopped --start--> pending
                       |  ^                                            |
                       |  +---------------- reboot (stays running) ----+
                       |
                   terminate --> shutting-down --> terminated (gone, EBS root deleted by default)
```

| State | Billed for compute? | Notes |
|---|---|---|
| running | yes | |
| stopped | no (EBS still billed) | RAM is lost and the public IP is released. EBS data is kept |
| terminated | no | Irreversible |
| hibernated | no | RAM is saved to EBS. Must be enabled at launch |

## Use cases

Web/app servers behind a load balancer, self-managed databases, CI runners, batch jobs on Spot instances (up to ~90% cheaper, can be reclaimed), and lifting legacy apps "as is" into the cloud.

## Hands-on against LocalStack

Transcript: [`../../outputs/11-ec2.txt`](../../outputs/11-ec2.txt). **LocalStack's EC2 is emulated:** the API records the instance and moves it through states, but no VM boots and nothing runs inside it.

```text
$ aws ... ec2 describe-availability-zones ... --output table
|  available |  ap-south-1a  |
|  available |  ap-south-1b  |
|  available |  ap-south-1c  |

$ aws ... ec2 describe-instance-types --instance-types t3.micro t3.large m5.large c5.large r5.large ...
| MemMiB |   Type     | vCPU   |
|  4096  |  c5.large  |  2     |      <- compute family: 2 GiB per vCPU
|  8192  |  m5.large  |  2     |      <- general: 4 GiB per vCPU
|  16384 |  r5.large  |  2     |      <- memory: 8 GiB per vCPU
|  8192  |  t3.large  |  2     |
|  1024  |  t3.micro  |  2     |

$ aws ... ec2 create-key-pair --key-name hw18-key --query '{KeyName:KeyName,Fingerprint:KeyFingerprint}'
{ "KeyName": "hw18-key", "Fingerprint": "72:59:89:55:7f:b0:31:fe:b4:da:ac:6b:41:c4:4a:33:e1:a8:bb:ab" }

$ aws ... ec2 authorize-security-group-ingress --group-id sg-a71f81cfbe1118cfa --protocol tcp --port 80 --cidr 0.0.0.0/0
$ aws ... ec2 authorize-security-group-ingress --group-id sg-a71f81cfbe1118cfa --protocol tcp --port 22 --cidr 203.0.113.10/32

$ aws ... ec2 run-instances --image-id ami-03cf127a --instance-type t3.micro --key-name hw18-key ... \
      --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=8,VolumeType=gp3}'
{ "Id": "i-77be17123b544599e", "State": "pending", "Type": "t3.micro", "PrivateIp": "10.186.201.15" }

$ aws ... ec2 describe-instances --instance-ids i-77be17123b544599e ...
{ "State": "running", "PrivateIp": "10.186.201.15", "PublicIp": "54.214.107.163", "Key": "hw18-key", "AZ": "ap-south-1a" }

$ aws ... ec2 stop-instances ...       { "From": "running", "To": "stopping" }
$ aws ... ec2 start-instances ...      { "From": "stopped", "To": "pending" }
$ aws ... ec2 terminate-instances ...  { "From": "running", "To": "shutting-down" }
```

(Output trimmed and JSON put on one line; the comments on the right are mine.)

What I saw: the lifecycle transitions match the diagram above. I printed only the key's fingerprint. LocalStack also returns a generated private key, which I didn't save. Two emulation quirks: the private IP `10.186.x.x` isn't inside the default VPC's `172.31.0.0/16` (on real AWS it would be), and LocalStack let me delete the security group while the instance was still shutting down, which real AWS would refuse.
