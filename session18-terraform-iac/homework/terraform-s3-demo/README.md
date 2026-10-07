# Terraform S3 Demo (Session 18, Task 1)

**Name:** Rudhar Bajaj
**Environment:** macOS (Apple Silicon), Docker Desktop 29.6.1, Terraform 1.16.4, hashicorp/aws provider 6.67.0, AWS CLI 2.35.21, LocalStack community 4.14.0 standing in for AWS

Every output block below is real output from commands I ran on 2026-10-07. Full untrimmed transcripts
are in [`../outputs/`](../outputs/). Where I shortened a listing I say so.

## What this creates

One S3 bucket plus three companion resources, set up the way I'd want a real bucket:

| Resource | Why |
|---|---|
| `aws_s3_bucket.demo` | The bucket, with `Name/Environment/Project` tags (+ `ManagedBy/Owner` from the provider's `default_tags`) |
| `aws_s3_bucket_versioning.demo` | Overwrites and deletes keep the old version, so a bad upload can be undone |
| `aws_s3_bucket_server_side_encryption_configuration.demo` | Every object encrypted at rest with SSE-S3 (AES256) by default |
| `aws_s3_bucket_public_access_block.demo` | All four "block public access" switches on, so no ACL or policy can make it public by accident |

Since AWS provider v4 these settings are separate resources rather than blocks inside `aws_s3_bucket`, and that is why the plan shows 4 resources for "one bucket".

## Files

| File | Contents |
|---|---|
| `provider.tf` | `terraform {}` block (Terraform >= 1.6, `hashicorp/aws ~> 6.0`) and the `aws` provider. Points at LocalStack when `use_localstack = true` |
| `variables.tf` | `use_localstack`, `localstack_endpoint`, `aws_region`, `bucket_name` (with a naming-rule validation), `environment`, `enable_versioning` |
| `main.tf` | The 4 resources above |
| `outputs.tf` | `bucket_name`, `bucket_arn`, `bucket_region`, `versioning_status`, `target` |
| `terraform.tfvars` | My values. It has no secrets, so it is committed (the `homework/.gitignore` re-includes it) |
| `.terraform.lock.hcl` | Written by `terraform init`. It pins the provider version + checksums, and I commit it |

## LocalStack instead of a real AWS account

I don't have an AWS account, so I ran AWS locally with LocalStack:

```bash
docker run -d --name hw-localstack -p 127.0.0.1:4566:4566 \
  -e SERVICES=s3,ec2,iam,sts,dynamodb localstack/localstack:4.14.0
```

I pinned `4.14.0` because it was the last tag of the free community image (build date 2026-02-26). The
container's own start-up banner says *"We move towards a unified LocalStack for AWS image in March 2026"*,
and the newer `2026.x`/`latest` tags are that unified image, which needs an auth token.

The switch to LocalStack lives in `provider.tf` and is driven by one variable:

```hcl
provider "aws" {
  region     = var.aws_region
  access_key = var.use_localstack ? "test" : null   # fake LocalStack creds
  secret_key = var.use_localstack ? "test" : null
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  s3_use_path_style           = var.use_localstack

  dynamic "endpoints" {                              # deleting this = real AWS
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      s3 = endpoints.value, ec2 = ..., iam = ..., sts = ..., dynamodb = ...
    }
  }
}
```

(That is a condensed version of the block; `provider.tf` has the full one.) With `use_localstack = false` the same code goes to real AWS. I checked that the switch works: with
no credentials on this machine, the provider immediately looks for real ones
([`05-real-aws-toggle.txt`](../outputs/05-real-aws-toggle.txt)):

```text
$ terraform plan -no-color -var use_localstack=false
Error: No valid credential sources found
...
Error: failed to refresh cached credentials, no EC2 IMDS role found,
```

## The workflow, command by command

Transcript: [`01-terraform-workflow.txt`](../outputs/01-terraform-workflow.txt).

### 1. `terraform init`: prepare the folder

```text
$ terraform init -no-color
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 6.0"...
- Installing hashicorp/aws v6.67.0...
- Installed hashicorp/aws v6.67.0 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. ...
Terraform has been successfully initialized!
```

- **Backend**: where state is stored. I didn't configure one, so it's the default *local* backend (`terraform.tfstate` in this folder).
- **Provider plugins**: `~> 6.0` means "6.x, not 7". The newest matching version was 6.67.0. The binary goes into `.terraform/` (gitignored).
- **Lock file**: records 6.67.0 and its hashes, so a teammate's `init` gets exactly the same build. That's why it's committed.

### 2. `terraform fmt`: canonical formatting

```text
$ terraform fmt -recursive; echo "fmt exit code: $?"
fmt exit code: 0
$ terraform fmt -check -diff; echo "fmt -check exit code: $?"
fmt -check exit code: 0
```

`fmt` rewrites files to the standard style (aligned `=`, 2-space indent) and prints the names of the files it changed. It printed nothing, so my files were already formatted. `-check` is the CI version: it changes nothing and exits non-zero if something is unformatted.

### 3. `terraform validate`: is the code consistent?

```text
$ terraform validate -no-color
Success! The configuration is valid.
```

It checks syntax, types, required arguments and references (for example, that `aws_s3_bucket.demo` exists where it is referenced), without calling AWS. It does **not** check that the bucket name is free.

### 4. `terraform plan`: preview, nothing changes yet

```text
$ terraform plan -no-color -out=tfplan

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be created
  + resource "aws_s3_bucket" "demo" {
      + arn                         = (known after apply)
      + bucket                      = "rudhar-session18-tf-demo-10143"
      + force_destroy               = true
      + region                      = "ap-south-1"
      + tags                        = {
          + "Environment" = "dev"
          + "Name"        = "rudhar-session18-tf-demo-10143"
          + "Project"     = "Session18"
        }
      ...
  # aws_s3_bucket_public_access_block.demo will be created
  # aws_s3_bucket_server_side_encryption_configuration.demo will be created
  # aws_s3_bucket_versioning.demo will be created
      ...
Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_arn        = (known after apply)
  + bucket_name       = "rudhar-session18-tf-demo-10143"
  ...
Saved the plan to: tfplan
```

(trimmed; the full plan is in the transcript)

How to read it:

- The plan compares three things: the **config** (`.tf` + tfvars), the **state** (empty here), and the **real infrastructure** (refreshed from the API). Anything that differs becomes an action.
- `(known after apply)`: AWS only decides this value at creation time (the ARN, for example).
- `-out=tfplan` saves this exact plan. `terraform apply tfplan` then does exactly this and nothing else, without asking again. Without `-out` you get the "Note: You didn't use the -out option" warning.

The symbols. I produced each one for real (transcripts [`03`](../outputs/03-state-and-update.txt) and [`04`](../outputs/04-destroy.txt)):

| Symbol | Meaning | How I got it |
|---|---|---|
| `+` | create | first plan above |
| `~` | update in-place: same resource, some attributes change | `terraform plan -var environment=staging` |
| `-` | destroy | `terraform plan -destroy` |
| `-/+` | destroy then create a replacement: the attribute can't be changed in place | `terraform plan -var bucket_name=...renamed...` |

```text
$ terraform plan -no-color -var environment=staging
  ~ update in-place
  # aws_s3_bucket.demo will be updated in-place
      ~ tags                        = {
          ~ "Environment" = "dev" -> "staging"
Plan: 0 to add, 1 to change, 0 to destroy.

$ terraform plan ... -var bucket_name=rudhar-session18-renamed-10143
-/+ destroy and then create replacement
      ~ bucket = "rudhar-session18-tf-demo-10143" -> "rudhar-session18-renamed-10143" # forces replacement
Plan: 4 to add, 0 to change, 4 to destroy.
```

A bucket can't be renamed, so a new name means a new bucket. The three companion resources point at the bucket, so they get replaced too. A tag change is just an API call, so that one is `~`. Neither of these plans was applied.

### 5. `terraform apply`: make it real

```text
$ terraform apply -no-color tfplan
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 1s [id=rudhar-session18-tf-demo-10143]
aws_s3_bucket_public_access_block.demo: Creating...
aws_s3_bucket_versioning.demo: Creating...
aws_s3_bucket_server_side_encryption_configuration.demo: Creating...
...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::rudhar-session18-tf-demo-10143"
bucket_name = "rudhar-session18-tf-demo-10143"
bucket_region = "ap-south-1"
target = "LocalStack (http://localhost:4566)"
versioning_status = "Enabled"
```

The bucket was created first and the other three ran in parallel afterwards. They all use `aws_s3_bucket.demo.id`, which is an implicit dependency, so Terraform has to wait for the bucket. Without `tfplan`, `terraform apply` plans again and asks `Enter a value:`, and only `yes` continues.

After the apply there is a new file, `terraform.tfstate` (7239 bytes). This is the **state file**:

```text
$ python3 -c "...print version/serial/lineage and every resource in terraform.tfstate..."
version 4 | terraform_version 1.16.4 | serial 5
lineage 07fe7caf-cf24-2596-b3cc-7617b35b601b
  managed aws_s3_bucket.demo -> rudhar-session18-tf-demo-10143
  managed aws_s3_bucket_public_access_block.demo -> rudhar-session18-tf-demo-10143
  ...
```

State is Terraform's memory. It maps each address in my code (`aws_s3_bucket.demo`) to a real object ID (`rudhar-session18-tf-demo-10143`). Without it, Terraform wouldn't know the bucket is "its" bucket and would try to create a new one. `serial` goes up on every write, and `lineage` identifies this one state history. It's JSON with every attribute in plain text, so it never goes in Git (`*.tfstate*` is ignored).

Running `plan` again right after the apply proves that config, state and reality agree:

```text
$ terraform plan -no-color
aws_s3_bucket.demo: Refreshing state... [id=rudhar-session18-tf-demo-10143]
...
No changes. Your infrastructure matches the configuration.
```

### 6. `terraform show`: read the state in readable form

```text
$ terraform show -no-color
# aws_s3_bucket.demo:
resource "aws_s3_bucket" "demo" {
    arn                         = "arn:aws:s3:::rudhar-session18-tf-demo-10143"
    bucket                      = "rudhar-session18-tf-demo-10143"
    bucket_regional_domain_name = "rudhar-session18-tf-demo-10143.s3.ap-south-1.amazonaws.com"
    ...
# aws_s3_bucket_versioning.demo:
resource "aws_s3_bucket_versioning" "demo" {
    ...
    versioning_configuration {
        mfa_delete = "Disabled"
        status     = "Enabled"
    }
}
```

`show` prints everything in state, including values AWS filled in that I never wrote (the domain names, the hosted zone ID, and so on). `terraform state list` gives just the addresses:

```text
$ terraform state list
aws_s3_bucket.demo
aws_s3_bucket_public_access_block.demo
aws_s3_bucket_server_side_encryption_configuration.demo
aws_s3_bucket_versioning.demo
```

One detail I noticed: right after the apply, the read-only `versioning { enabled = false }` block inside `aws_s3_bucket.demo` was still false. The bucket was read *before* the separate versioning resource switched versioning on. On the next refresh (in the destroy plan) it showed `enabled = true`. It's a snapshot, not a live view.

### 7. `terraform output`: the values I chose to expose

```text
$ terraform output -no-color
bucket_arn = "arn:aws:s3:::rudhar-session18-tf-demo-10143"
bucket_name = "rudhar-session18-tf-demo-10143"
...
$ terraform output -raw bucket_name
rudhar-session18-tf-demo-10143
```

`-raw` prints a bare string, which is handy in scripts (`aws s3 cp x s3://$(terraform output -raw bucket_name)/`). `-json` gives all outputs with their types for other tools (in the transcript).

### 8. Proof the bucket really exists (instead of a console screenshot)

Transcript: [`02-aws-cli-verify.txt`](../outputs/02-aws-cli-verify.txt). I ran the AWS CLI with `AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test` and `--endpoint-url http://localhost:4566`:

```text
$ aws --endpoint-url http://localhost:4566 s3 ls
2026-10-07 21:54:47 rudhar-session18-tf-demo-10143

$ aws ... s3api get-bucket-versioning --bucket rudhar-session18-tf-demo-10143
{ "Status": "Enabled" }

$ aws ... s3api get-bucket-encryption --bucket rudhar-session18-tf-demo-10143
"ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }, "BucketKeyEnabled": false

$ aws ... s3api get-public-access-block --bucket rudhar-session18-tf-demo-10143
"BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": true, "RestrictPublicBuckets": true
```

(JSON compressed onto one line)

Then I uploaded the same key twice to watch versioning and encryption work:

```text
$ aws ... s3api list-object-versions --bucket rudhar-session18-tf-demo-10143 ... --output table
| IsLatest |    Key    | Size  |              VersionId              |
|  True    |  note.txt |  9    |  AaEXLsqdaPTHLsPHOq1ZJ8UiXPHDH3Oc   |
|  False   |  note.txt |  9    |  AaEXLsqcYW2fh7ieNOn4od._whUwCo7U   |

$ aws ... s3api head-object --bucket rudhar-session18-tf-demo-10143 --key note.txt ...
{ "SSE": "AES256", "VersionId": "AaEXLsqdaPTHLsPHOq1ZJ8UiXPHDH3Oc", "Length": 9 }
```

Two versions of `note.txt`, and the object was encrypted without me asking for it on upload. That came from the bucket default.

### 9. `terraform destroy`: clean up

```text
$ terraform plan -destroy -no-color
  - destroy
  # aws_s3_bucket.demo will be destroyed
  - resource "aws_s3_bucket" "demo" {
      - bucket = "rudhar-session18-tf-demo-10143" -> null
      ...
Plan: 0 to add, 0 to change, 4 to destroy.

$ terraform destroy -auto-approve -no-color
aws_s3_bucket_server_side_encryption_configuration.demo: Destroying...
aws_s3_bucket_public_access_block.demo: Destroying...
aws_s3_bucket_versioning.demo: Destroying...
...
aws_s3_bucket.demo: Destroying... [id=rudhar-session18-tf-demo-10143]
aws_s3_bucket.demo: Destruction complete after 0s

Destroy complete! Resources: 4 destroyed.

$ aws ... s3api head-bucket --bucket rudhar-session18-tf-demo-10143; echo "head-bucket exit code: $?"
aws: [ERROR]: An error occurred (404) when calling the HeadBucket operation: Not Found
head-bucket exit code: 254
```

- `-> null` on every attribute means the value goes away.
- Destroy runs in **reverse** dependency order: the three companions first, the bucket last.
- The bucket still held two versions of `note.txt`. S3 refuses to delete a non-empty bucket, and `force_destroy = true` is what let Terraform empty it first. I'd leave that off for real data.
- I used `-auto-approve` so the transcript doesn't stall at the `yes` prompt. I had already read the `plan -destroy` output.
- `terraform state list` is empty afterwards. The `terraform.tfstate` file still exists, but it tracks nothing. `terraform.tfstate.backup` holds the previous version.

## Run it yourself

```bash
docker run -d --name hw-localstack -p 127.0.0.1:4566:4566 localstack/localstack:4.14.0
terraform init && terraform fmt && terraform validate
terraform plan -out=tfplan && terraform apply tfplan
terraform show; terraform output
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-south-1 \
  aws --endpoint-url http://localhost:4566 s3api get-bucket-versioning --bucket rudhar-session18-tf-demo-10143
terraform destroy
docker rm -f hw-localstack
```

## Differences from the spec

- The AWS account is LocalStack, not real AWS (my choice, so there is no cost). The S3 API calls are the same ones real AWS would receive. Only the endpoint and the credentials differ.
- "Screenshots" are the text transcripts in `../outputs/`.
- I used `plan -out` + `apply tfplan` and `destroy -auto-approve` so the transcripts don't block on a prompt. The interactive `yes` prompt is the same thing done by hand.
