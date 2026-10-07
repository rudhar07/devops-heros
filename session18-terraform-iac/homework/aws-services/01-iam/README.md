# IAM: Identity and Access Management

IAM decides **who** (a principal) can do **what** (actions) on **which resources**, and under **which conditions**. It's global (not tied to a region) and free. Every AWS API call is checked against it. By default everything is **denied** until a policy allows it.

## Building blocks

| Thing | What it is | Example |
|---|---|---|
| **Root user** | The email that created the account. Can do everything, including closing the account | Lock it away with MFA and don't use it day to day |
| **User** | A long-lived identity for one person or app. Signs in with a password (console) and/or access keys (CLI) | `hw18-alice` |
| **Group** | A set of users. Policies attached to the group apply to every member. A group can't be a principal in a policy | `hw18-developers` |
| **Role** | An identity with **no long-term credentials**. Someone or something *assumes* it and gets temporary keys from STS | An EC2 instance role, a CI pipeline role, a cross-account role |
| **Policy** | A JSON document of permissions | `hw18-s3-reports-readonly` |
| **Permission** | One `Allow`/`Deny` of an action on a resource inside a policy | `s3:GetObject` on `arn:aws:s3:::hw18-reports/*` |

Policy types worth knowing:

| Type | Attached to | Notes |
|---|---|---|
| AWS managed | user/group/role | Written by AWS, e.g. `ReadOnlyAccess`. Convenient but often broader than needed |
| Customer managed | user/group/role | Your own reusable policy, versioned (`v1`, `v2`, ...) |
| Inline | one identity | Embedded in a single user/role. It is deleted with that identity |
| Trust policy | a role | Says **who may assume** the role |
| Resource-based | a resource | e.g. an S3 bucket policy. Has a `Principal` field |
| Permissions boundary / SCP | identity / AWS Org | Caps the *maximum* permissions. They never grant anything themselves |

## How a policy reads

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "ListTheReportsBucket", "Effect": "Allow",
      "Action": "s3:ListBucket",  "Resource": "arn:aws:s3:::hw18-reports" },
    { "Sid": "ReadObjectsInIt",      "Effect": "Allow",
      "Action": "s3:GetObject",   "Resource": "arn:aws:s3:::hw18-reports/*" }
  ]
}
```

This is [`s3-readonly-policy.json`](s3-readonly-policy.json). Listing applies to the **bucket** ARN and reading to the **objects** (`/*`), so both are needed. Anything not listed, like `s3:DeleteObject` or any other bucket, is denied implicitly.

Evaluation order: an **explicit `Deny` always wins**, then any `Allow` grants, and otherwise the default is deny.

A role's **trust policy** ([`ec2-trust-policy.json`](ec2-trust-policy.json)) lets the EC2 service assume it:

```json
{ "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }
```

## Least privilege and best practices

- **Least privilege**: grant only the actions and resources the job needs, then widen if something breaks. Don't start from `*` and narrow down later.
- Don't use root. Turn on MFA for root and for every human user.
- Humans get access through **groups** (or SSO / Identity Center), not policies attached user by user.
- Workloads (EC2, Lambda, CI) use **roles**, never access keys copied onto a server or into Git.
- Rotate or remove unused access keys. The credential report and Access Analyzer show what's unused.
- Use conditions to narrow further (`aws:SourceIp`, `aws:MultiFactorAuthPresent`, `aws:SecureTransport`).
- Use CloudTrail to see who called what.

## Common use cases

| Need | IAM answer |
|---|---|
| A team of developers needs the same access | Group + customer-managed policy |
| An app on EC2 must read S3 | Role + instance profile (the session 19 project does exactly this) |
| A GitHub Actions deploy | Role assumed through OIDC, no stored keys |
| Another AWS account needs to read a bucket | Cross-account role, or a bucket policy naming that account |
| Limit what a whole account can ever do | SCP in AWS Organizations |

## Hands-on against LocalStack

Transcript: [`../../outputs/10-iam.txt`](../../outputs/10-iam.txt). I created a user, a group, a customer-managed policy and a role, then wired them together:

```text
$ aws --endpoint-url http://localhost:4566 iam create-group --group-name hw18-developers ...
{ "Name": "hw18-developers", "Arn": "arn:aws:iam::000000000000:group/hw18-developers" }
$ aws ... iam create-user --user-name hw18-alice --tags Key=Team,Value=dev ...
{ "Name": "hw18-alice", "Arn": "arn:aws:iam::000000000000:user/hw18-alice" }
$ aws ... iam add-user-to-group --group-name hw18-developers --user-name hw18-alice
$ aws ... iam create-policy --policy-name hw18-s3-reports-readonly --policy-document file://s3-readonly-policy.json ...
{ "Name": "hw18-s3-reports-readonly", "Arn": "arn:aws:iam::000000000000:policy/hw18-s3-reports-readonly", "Version": "v1" }
$ aws ... iam attach-group-policy --group-name hw18-developers --policy-arn arn:aws:iam::000000000000:policy/hw18-s3-reports-readonly
$ aws ... iam get-group --group-name hw18-developers --query '{Group:Group.GroupName,Users:Users[].UserName}'
{ "Group": "hw18-developers", "Users": [ "hw18-alice" ] }
$ aws ... iam create-role --role-name hw18-ec2-app-role --assume-role-policy-document file://ec2-trust-policy.json ...
{ "Name": "hw18-ec2-app-role", "Arn": "arn:aws:iam::000000000000:role/hw18-ec2-app-role" }
$ aws ... iam list-attached-role-policies --role-name hw18-ec2-app-role
"PolicyName": "hw18-s3-reports-readonly"
```

(JSON compressed onto one line)

**What didn't work, and why:** I wanted to show the allow/deny decision with `simulate-principal-policy`. On real AWS I'd expect `s3:GetObject` → `allowed` and `s3:DeleteObject` → `implicitDeny`. LocalStack community answered `explicitDeny` for both, even after I attached the policy straight to the user, and `simulate-custom-policy` returned *"has not been implemented"*. LocalStack community **stores** IAM objects but doesn't **evaluate or enforce** policies. So the objects and their wiring above are real, but the permission check itself stays conceptual here.

`000000000000` is LocalStack's fake account ID.
