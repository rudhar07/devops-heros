# S3: Simple Storage Service

S3 is object storage: you PUT and GET whole files (objects) over HTTPS by key. There are no disks to size and no servers. It is designed for 99.999999999% (11 nines) durability by storing copies across multiple AZs. Bucket names are **globally unique**, but each bucket lives in **one region**.

## Buckets and objects

| Term | Meaning |
|---|---|
| **Bucket** | Top-level container. Name 3-63 chars, lowercase, digits, `-`, `.`. Region, versioning, encryption and policy are set here |
| **Object** | The data (up to 5 TB) + metadata + a version ID |
| **Key** | The object's full name, e.g. `docs/report.txt`. The "folders" are just prefixes in the key; S3 has no real directories |
| **ARN** | `arn:aws:s3:::bucket` for the bucket, `arn:aws:s3:::bucket/key` for objects |

## Storage classes

| Class | For | Min. storage duration | Retrieval |
|---|---|---|---|
| S3 Standard | Hot data | none | ms |
| S3 Intelligent-Tiering | Unknown/changing access; moves objects between tiers automatically | none | ms (archive tiers optional) |
| Standard-IA | Read rarely but needed fast | 30 days | ms, with a retrieval fee |
| One Zone-IA | Re-creatable data, one AZ only | 30 days | ms |
| Glacier Instant Retrieval | Archive read about once a quarter | 90 days | ms |
| Glacier Flexible Retrieval | Archive | 90 days | minutes to hours |
| Glacier Deep Archive | Compliance archive | 180 days | up to 12 h |

Cheaper storage comes with dearer or slower retrieval.

## Versioning

Once enabled (it can only be suspended afterwards, never turned off), every overwrite creates a new version and a delete only adds a **delete marker**. You can restore any old version, which protects against `rm` mistakes and ransomware-style overwrites. Old versions cost storage, so pair versioning with a lifecycle rule.

## Lifecycle policies

Rules that move or delete objects automatically by age. My example, [`lifecycle.json`](lifecycle.json):

```json
{ "Rules": [ {
    "ID": "logs-tiering-and-expiry",
    "Status": "Enabled",
    "Filter": { "Prefix": "logs/" },
    "Transitions": [ { "Days": 30, "StorageClass": "STANDARD_IA" },
                     { "Days": 90, "StorageClass": "GLACIER" } ],
    "Expiration": { "Days": 365 },
    "NoncurrentVersionExpiration": { "NoncurrentDays": 30 } } ] }
```

For objects under `logs/`, this rule moves them to IA after 30 days and to Glacier after 90, and deletes them after a year. Overwritten (non-current) versions are removed 30 days after they stop being current.

## Encryption

| Option | Who holds the key | Notes |
|---|---|---|
| SSE-S3 (`AES256`) | AWS, fully managed | **On by default for all new buckets since Jan 2023** |
| SSE-KMS (`aws:kms`) | A KMS key you control | Key policy + CloudTrail audit of every decrypt, per-request KMS cost (Bucket Keys reduce it) |
| DSSE-KMS | KMS, two layers | Compliance use |
| SSE-C | You send the key with every request | AWS never stores it |
| Client-side | You, before upload | S3 only sees ciphertext |

In transit: use HTTPS. The bucket policy below enforces it.

## Bucket policies (and Block Public Access)

A bucket policy is a **resource-based** IAM policy on the bucket, so it has a `Principal`. My example, [`deny-insecure-transport-policy.json`](deny-insecure-transport-policy.json), refuses any plain-HTTP request:

```json
{ "Sid": "DenyPlainHTTP", "Effect": "Deny", "Principal": "*", "Action": "s3:*",
  "Resource": ["arn:aws:s3:::hw18-s3-lab-10143", "arn:aws:s3:::hw18-s3-lab-10143/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } } }
```

**Block Public Access** (4 switches, on by default for new buckets) overrides any policy or ACL that would make data public. Leave it on unless the bucket really is a public website.

## Use cases

Static website hosting (usually behind CloudFront), backups, data lakes (Athena/EMR query it in place), logs, ML datasets, artifact and Terraform state storage, and media for apps.

## Hands-on against LocalStack

Transcript: [`../../outputs/13-s3.txt`](../../outputs/13-s3.txt). Versioning, delete markers and restore:

```text
$ printf 'v1: draft\n' | aws ... s3 cp - s3://hw18-s3-lab-10143/docs/report.txt
$ printf 'v2: final\n' | aws ... s3 cp - s3://hw18-s3-lab-10143/docs/report.txt
$ aws ... s3api list-object-versions --bucket hw18-s3-lab-10143 --prefix docs/ ... --output table
|  True    |  10   |  AaEXLsqfPs4uxPEcypt1CsrFP0.V3gtk   |
|  False   |  10   |  AaEXLsqeD5p9FuyrNr0IjGUm6C011ai0   |

$ aws ... s3 rm s3://hw18-s3-lab-10143/docs/report.txt
$ aws ... s3 ls s3://hw18-s3-lab-10143/docs/; echo "ls exit code: $?"
ls exit code: 1                                   <- looks gone
$ aws ... s3api list-object-versions ...
"Versions": [ "AaEXLsqf...", "AaEXLsqe..." ],
"DeleteMarkers": [ { "VersionId": "AaEXLsqg0eApPXSx1SNh.nFOdl7rieq_", "IsLatest": true } ]

$ aws ... s3api get-object ... --version-id AaEXLsqeD5p9FuyrNr0IjGUm6C011ai0 /dev/stdout
v1: draft                                         <- the old version is still readable
$ aws ... s3api delete-object ... --version-id AaEXLsqg0eApPXSx1SNh.nFOdl7rieq_   # remove the delete marker
$ aws ... s3 cp s3://hw18-s3-lab-10143/docs/report.txt -
v2: final                                         <- "undeleted"
```

(The comments on the right are mine.)

The lifecycle rule above went in with `put-bucket-lifecycle-configuration` and read back identical. An upload with `--storage-class STANDARD_IA` showed up as `STANDARD_IA` in `list-objects-v2`.

Cleanup taught me something:

```text
$ aws ... s3 rb s3://hw18-s3-lab-10143 --force
delete: s3://hw18-s3-lab-10143/docs/report.txt
delete: s3://hw18-s3-lab-10143/logs/old.log
remove_bucket failed: ... BucketNotEmpty ... You must delete all versions in the bucket.
$ aws ... s3api list-object-versions ... --query '{Versions:length(...),DeleteMarkers:length(...)}'
{ "Versions": 3, "DeleteMarkers": 2 }
```

`rb --force` only removes the *current* objects, so on a versioned bucket it just adds delete markers. I had to delete all 5 versions and markers explicitly, and then `rb` worked. This is the same reason the Terraform demo needs `force_destroy = true`.

**LocalStack limitation:** it accepted and stored the deny-HTTP bucket policy, yet happily served all my requests over plain `http://localhost:4566`. LocalStack community doesn't enforce bucket policies (or IAM in general), and real S3 would have rejected them.
