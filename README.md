# Terraform Static Site Platform (2048 on AWS)

A reusable, multi-environment static-website platform built entirely with Terraform. It provisions an S3 + CloudFront delivery stack with security-by-default, isolated `dev`/`prod` environments, remote locked state, an event-driven cache-invalidation Lambda, and a GitHub Actions CI/CD pipeline that deploys the site automatically on every push.

The site itself (the open-source 2048 game) is intentionally trivial — the value of this project is the **engineering around it**: how it is built, secured, isolated, versioned, and shipped. This README is written so that **someone starting from nothing** — no AWS account, no Terraform, no prior context — can stand up their **own** copy hosting **their own** static site, changing as little as possible.

---

## Table of contents

1. [What this builds](#1-what-this-builds)
2. [The one core idea](#2-the-one-core-idea)
3. [Repo tour — what lives where](#3-repo-tour--what-lives-where)
4. [Prerequisites — starting from zero](#4-prerequisites--starting-from-zero)
5. [One-time bootstrap: the state bucket](#5-one-time-bootstrap-the-state-bucket)
6. [Reuse guide: the only files you edit](#6-reuse-guide-the-only-files-you-edit)
7. [Deploy dev, then prod](#7-deploy-dev-then-prod)
8. [Pointing at YOUR site / YOUR game repo](#8-pointing-at-your-site--your-game-repo)
9. [The CI/CD pipeline (optional but recommended)](#9-the-cicd-pipeline-optional-but-recommended)
10. [Day-to-day: how you change things](#10-day-to-day-how-you-change-things)
11. [Design decisions (the "why")](#11-design-decisions-the-why)
12. [Teardown](#12-teardown)

---

## 1. What this builds

Two environments, from **one** reusable module, selected by a single boolean flag:

| | **dev** | **prod** |
|---|---|---|
| Bucket access | Public read | Fully locked (all public access blocked) |
| Served over | Plain HTTP (S3 website endpoint) | HTTPS (CloudFront) |
| CDN / edge cache | None | CloudFront with Origin Access Control (OAC) |
| Cache invalidation | N/A (no cache) | Automatic, via Lambda on file upload |
| Purpose | Fast, cheap iteration | Secure, cached, production delivery |
| Flag | `enable_cdn = false` | `enable_cdn = true` |

Both environments have **separate state**, so a mistake in one can never touch the other.

---

## 2. The one core idea

**Terraform owns the *stage*; it never owns the *content*.**

Terraform builds the empty infrastructure — buckets, CloudFront, OAC, Lambda, IAM. The website files are poured in **separately**, via a plain `aws s3 sync`. The files are **never** Terraform resources.

This single principle is why:

- A **content change** (new website files) can never break your infrastructure — the files aren't in Terraform state; a change is just a `sync`.
- An **infra change** (`terraform apply`) never touches the files sitting in the bucket.
- The two are *structurally* incapable of colliding, because they share no state file and no files on disk.

Keep this in your head throughout: **`terraform apply` builds empty buckets; `aws s3 sync` fills them.**

---

## 3. Repo tour — what lives where

```
TerraformStaticFileServing/                 # the INFRA repo (this repo)
│
├── README.md                               # this file
│
├── modules/
│   └── static-site/                        # THE REUSABLE BUILDING BLOCK ("the recipe")
│       ├── variables.tf                    #   module inputs: environment, enable_cdn, project_name, cloudfront_price_class
│       ├── outputs.tf                      #   module outputs: endpoint URL + bucket name
│       ├── s3.tf                           #   the bucket + dev(public) & prod(locked) policies/access-blocks
│       ├── cloudfront.tf                   #   OAC + CloudFront distribution (prod only)
│       ├── iam.tf                          #   IAM role + policy for the invalidation Lambda
│       ├── lambda.tf                       #   Lambda function + S3 event notification + invoke permission
│       └── lambda/
│           └── invalidation.py             #   the Python that calls CloudFront CreateInvalidation
│
└── environments/                           # THE CALLERS (one folder = one environment = one state)
    │
    ├── dev/                                 # DEV — public S3 website over HTTP
    │   ├── backend.tf                       #   empty `backend "s3" {}` block (partial config)
    │   ├── dev.s3.tfbackend                 #   <-- EDIT: state bucket/key/region for dev
    │   ├── provider.tf                      #   AWS provider, region = var.aws_region
    │   ├── variables.tf                     #   variable declarations
    │   ├── terraform.tfvars                 #   <-- EDIT: your dev values (region, project name)
    │   └── main.tf                          #   calls the module with enable_cdn = false
    │
    ├── prod/                                # PROD — locked bucket + CloudFront + Lambda over HTTPS
    │   ├── backend.tf                       #   empty `backend "s3" {}` block
    │   ├── prod.s3.tfbackend                #   <-- EDIT: state bucket/key/region for prod
    │   ├── provider.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars                 #   <-- EDIT: your prod values (enable_cdn = true)
    │   └── main.tf                          #   calls the module with enable_cdn = true
    │
    └── cicd/                                # CI/CD support — OIDC provider + IAM role for GitHub Actions
        ├── backend.tf
        ├── cicd.s3.tfbackend                #   <-- EDIT: state bucket/key/region for cicd
        ├── provider.tf
        ├── variables.tf
        ├── terraform.tfvars                 #   <-- EDIT: your region, project, and GitHub repo
        └── main.tf                          #   OIDC identity provider + deploy role (least-privilege)
```

Two things are **deliberately NOT in this repo**:

- **The state bucket** — created once, by hand (see §5). It stores Terraform's memory and can't be Terraform-managed (chicken-and-egg).
- **The website files** — those live in a **separate repo** (the "game repo") and are pushed via `aws s3 sync`, never through Terraform.

**Mental model:** `modules/static-site/` is the *recipe*. Each folder in `environments/` is a *cook* following that recipe with different ingredients. Same recipe → two separate results, because each cook has its own separate state.

---

## 4. Prerequisites — starting from zero

If you have none of the tools, do these in order.

### 4.1 Get an AWS account

1. Go to <https://aws.amazon.com/> → **Create an AWS Account**.
2. Complete signup (needs a card; this project stays within or near the free tier).
3. Create a non-root IAM user for daily use (recommended over the root account):
   - AWS Console → **IAM** → **Users** → **Create user**.
   - Attach a policy that lets you create S3/CloudFront/Lambda/IAM resources (for a personal learning project, `AdministratorAccess` is simplest; scope down later).
   - Under the user's **Security credentials**, create an **Access key** (choose "Command Line Interface"). Copy the **Access key ID** and **Secret access key** — you'll need them next.

### 4.2 Install the AWS CLI (v2)

- **macOS:** `brew install awscli`
- **Windows:** download the MSI from <https://aws.amazon.com/cli/>
- **Linux / WSL:**
  ```bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip && sudo ./aws/install
  ```
- Verify: `aws --version` (should print `aws-cli/2.x`).

### 4.3 Authenticate the CLI to AWS

```bash
aws configure
```

Enter, when prompted:

- **AWS Access Key ID** — from step 4.1
- **AWS Secret Access Key** — from step 4.1
- **Default region** — e.g. `ap-south-1` (Mumbai) or `us-east-1`. Pick the region closest to you.
- **Default output format** — `json`

Confirm it worked:

```bash
aws sts get-caller-identity
```

If it prints your account ID and user ARN, you're authenticated.

### 4.4 Install Terraform

- **macOS:** `brew tap hashicorp/tap && brew install hashicorp/tap/terraform`
- **Windows:** `choco install terraform` (or download from <https://developer.hashicorp.com/terraform/downloads>)
- **Linux / WSL:** follow the apt steps at <https://developer.hashicorp.com/terraform/install>
- Verify: `terraform version` (need **1.6+** for native S3 state locking and `terraform test`).

> **WSL note:** if you use WSL, clone and run the project from your Linux home (`~/`), **not** from `/mnt/c/...`. Running Terraform's provider binaries off the Windows-mounted drive can fail to launch the provider. Working from `~/` avoids that.

### 4.5 Clone this repo

```bash
git clone https://github.com/<your-username>/TerraformStaticFileServing.git
cd TerraformStaticFileServing
```

---

## 5. One-time bootstrap: the state bucket

Terraform stores its "memory" (state) in a remote **S3 bucket** so it isn't stuck on one laptop and so it can be safely locked against concurrent edits. That bucket must **exist before Terraform runs** — so you create it **once, by hand**. This is the only manual AWS step; everything else is Terraform.

Pick a **globally unique** name (S3 names are shared across all of AWS). Example: `myname-site-tfstate`.

```bash
# 1. Create the bucket
aws s3api create-bucket \
  --bucket myname-site-tfstate \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1

# 2. Versioning — so a corrupted state can be rolled back
aws s3api put-bucket-versioning \
  --bucket myname-site-tfstate \
  --versioning-configuration Status=Enabled

# 3. Encryption at rest — state can contain secrets
aws s3api put-bucket-encryption \
  --bucket myname-site-tfstate \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Block ALL public access — this bucket must never be public
aws s3api put-public-access-block \
  --bucket myname-site-tfstate \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

> **Region note:** in `us-east-1`, omit the `--create-bucket-configuration` line (that region rejects it). In every other region, include it.

You now have a **private, versioned, encrypted** state bucket. Remember its name — you'll put it in the `.tfbackend` files next.

---

## 6. Reuse guide: the only files you edit

This is the heart of reusability. To rehost with your own name/region/site, you edit a **small, fixed set of files** and touch **no module code**. There are three kinds of "knob," each configured differently — this matters, because Terraform treats them differently.

### Knob type A — normal values → `terraform.tfvars`

These are ordinary input variables. Edit one `terraform.tfvars` per environment:

**`environments/dev/terraform.tfvars`**
```hcl
aws_region   = "ap-south-1"     # your region
environment  = "dev"            # leave as "dev"
enable_cdn   = false            # dev = public HTTP, no CDN
project_name = "myname-site"    # <-- YOUR prefix; buckets become myname-site-game-dev
```

**`environments/prod/terraform.tfvars`**
```hcl
aws_region             = "ap-south-1"
environment            = "prod"           # leave as "prod"
enable_cdn             = true             # prod = locked bucket + CloudFront + HTTPS
project_name           = "myname-site"    # same prefix as dev
cloudfront_price_class = "PriceClass_200" # 100=US/EU, 200=+Asia/India, All=global
```

Changing `project_name` renames **every** resource automatically, because names are built as `"${project_name}-game-${environment}"` inside the module. You never edit the module.

### Knob type B — state location → `*.s3.tfbackend`

The backend config **cannot** use variables (Terraform resolves the backend before variables load). So the state bucket/key/region live in a separate `.tfbackend` file fed in at `init` time.

**`environments/dev/dev.s3.tfbackend`**
```hcl
bucket       = "myname-site-tfstate"      # <-- the state bucket you made in §5
key          = "dev/terraform.tfstate"    # dev's own state file
region       = "ap-south-1"
encrypt      = true
use_lockfile = true                       # native S3 state locking (no DynamoDB needed)
```

**`environments/prod/prod.s3.tfbackend`** — identical but `key = "prod/terraform.tfstate"`.
**`environments/cicd/cicd.s3.tfbackend`** — identical but `key = "cicd/terraform.tfstate"`.

The **different `key` per environment is what isolates their state.** Same bucket, three separate state files, zero overlap.

### Knob type C — your website files → NOT Terraform at all

The files you host are pushed with `aws s3 sync` (see §8). There is nothing to edit in Terraform for this — you just point the sync at your own folder. This is by design: the infra doesn't know or care what files land in the bucket, which is exactly why it's reusable for *any* static site.

### The full "make it mine" checklist

| Edit this file | Change |
|---|---|
| `environments/dev/terraform.tfvars` | `aws_region`, `project_name` |
| `environments/dev/dev.s3.tfbackend` | `bucket` (your state bucket), `region` |
| `environments/prod/terraform.tfvars` | `aws_region`, `project_name` |
| `environments/prod/prod.s3.tfbackend` | `bucket`, `region` |
| `environments/cicd/terraform.tfvars` | `aws_region`, `project_name`, `github_repo` |
| `environments/cicd/cicd.s3.tfbackend` | `bucket`, `region` |

Six small files. No module edits.

---

## 7. Deploy dev, then prod

Always build **dev first**, confirm it works, then prod. Each environment is initialized and applied independently.

### Deploy dev

```bash
cd environments/dev

# connect this env to its remote state
terraform init -backend-config=dev.s3.tfbackend

# sanity checks
terraform fmt
terraform validate
terraform plan            # expect ~4 resources to add

# build the (empty) dev bucket
terraform apply           # type: yes
```

At the end, Terraform prints outputs, including `site_endpoint` (an `http://...s3-website...` URL) and `site_bucket`. Opening the URL now shows a 404 — that's correct, the bucket is empty. Fill it in §8.

### Deploy prod

```bash
cd ../prod
terraform init -backend-config=prod.s3.tfbackend
terraform fmt
terraform validate
terraform plan            # expect ~9 resources to add (bucket, OAC, CloudFront, Lambda, IAM, policies)
terraform apply           # type: yes  --  CloudFront takes 5-15 min, this is normal
```

The `site_endpoint` output is now an `https://<id>.cloudfront.net` URL. It also 404s until you sync files.

---

## 8. Pointing at YOUR site / YOUR game repo

This is where you host **your own** content instead of 2048.

The website files live in a **separate repo/folder** — call it your "site repo." It can be literally any static site: a portfolio, a docs site, a landing page. All it needs is an `index.html` at its root (plus whatever CSS/JS/asset folders it references).

### Sync your files into a bucket

From inside your site repo folder:

```bash
# to DEV:
aws s3 sync . s3://myname-site-game-dev  --delete --exclude ".git/*" --exclude ".github/*"

# to PROD:
aws s3 sync . s3://myname-site-game-prod --delete --exclude ".git/*" --exclude ".github/*"
```

- `.` — the current folder (your site) as the source. **Swap this for any folder** to host a different site.
- `s3://...` — the destination bucket (matches your `project_name`).
- `--delete` — keeps the bucket an exact mirror of your folder (removes files no longer present).
- `--exclude` — skips git/CI internals so they don't end up in the bucket.

After syncing, open the environment's `site_endpoint` URL. Your site is live — HTTP for dev, HTTPS for prod.

> **`index.html` is the entry point.** The module sets `index.html` as both the index and the error document (so a single-page app resolves any path back to it). If your site's entry file is named differently, either rename it to `index.html` or change `index_document` / `default_root_object` in `modules/static-site/s3.tf` and `cloudfront.tf`.

### Hosting a completely different site, start to finish

1. Point your `.tfvars`/`.tfbackend` at your names (§6).
2. `terraform apply` dev and prod (§7) — builds empty buckets.
3. `aws s3 sync ./your-site s3://<your-bucket>` — fills them.
4. Done. The 2048 game is never involved; you swapped the *content*, and the *infrastructure* didn't change.

---

## 9. The CI/CD pipeline (optional but recommended)

Instead of running `aws s3 sync` by hand, a GitHub Actions workflow can deploy on every push. Authentication uses **OIDC** — GitHub proves its identity to AWS and receives **short-lived** credentials, so **no long-lived AWS keys are ever stored in GitHub**.

### 9.1 Create the OIDC provider + deploy role (in this repo)

```bash
cd environments/cicd
# edit terraform.tfvars first: set github_repo = "your-username/your-site-repo"
terraform init -backend-config=cicd.s3.tfbackend
terraform apply            # type: yes
terraform output github_actions_role_arn   # copy this ARN
```

> **GitHub immutable `sub` claim (important, recent):** repos created on/after 15 July 2026 emit an *immutable* OIDC subject claim that appends numeric IDs (e.g. `repo:owner@123/repo@456:...`). If your deploy fails with *"Not authorized to perform sts:AssumeRoleWithWebIdentity"* even though everything looks correct, widen the `sub` condition in `cicd/main.tf` to `repo:<owner>*/<repo>*:*`, or pin the exact immutable form. This project's `main.tf` already accounts for it.

### 9.2 Add the workflow (in your SITE repo)

Create `.github/workflows/deploy.yml` in your **site repo** (not this infra repo):

```yaml
name: Deploy site to S3
on:
  push:
    branches: [main]
permissions:
  id-token: write        # REQUIRED for OIDC — mints the identity token
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: <PASTE THE ARN FROM 9.1>
          aws-region: ap-south-1
      - name: Sync to prod bucket
        run: aws s3 sync . s3://myname-site-game-prod --delete --exclude ".git/*" --exclude ".github/*"
```

Push it. From now on, `git push` to `main` auto-deploys your site. Syncing to the **prod** bucket also fires the invalidation Lambda, so the CDN cache clears itself and users see the new version immediately.

---

## 10. Day-to-day: how you change things

Two completely independent loops — this independence is the whole point.

**Change the site (content):**
```
edit files → git push (site repo) → GitHub Actions runs `s3 sync`
           → (prod) S3 event fires Lambda → CloudFront cache invalidated → live
```
Terraform never runs. Infra state never moves.

**Change the infrastructure:**
```
edit .tf → open a PR (infra repo) → review the `terraform plan` → merge → apply
```
The site files are never touched.

Because the two loops share no state file and no files on disk, a change in one is *structurally* incapable of affecting the other.

---

## 11. Design decisions (the "why")

- **Files synced, not Terraform-managed.** Infrastructure and content are separated so neither can break the other. Cramming every asset into Terraform as `aws_s3_object` pollutes state and couples content to infra.
- **One module, two shapes, one flag.** `enable_cdn` branches the same module between a public dev site and a locked prod site (via `count = var.enable_cdn ? 1 : 0`). This is what makes the module genuinely reusable and publishable.
- **OAC over a public bucket (prod).** The prod bucket blocks all public access; only the CloudFront distribution can read it, via a signed OAC request. A direct request to the bucket URL is denied.
- **Separate state per environment.** Different backend `key` per env = isolated state = a botched dev apply can't touch prod.
- **State bucket bootstrapped by hand.** Chicken-and-egg: Terraform needs the state bucket to exist before it can run, so it can't manage its own backend.
- **No VPC — on purpose.** Everything is S3/CloudFront/Lambda (managed/edge services); none run inside a customer network, so a VPC would add cost (NAT gateway for the Lambda's CloudFront call) and isolate nothing. A VPC would only be justified by adding a network-isolated backend (e.g. a database), which is a separate, larger project.
- **OIDC over long-lived keys for CI.** Short-lived tokens scoped to one repo, so nothing permanent is stored in GitHub.
- **Invalidation fires per file — accepted tradeoff.** A large `sync` emits one `ObjectCreated` event per file, so each deploy creates several `/*` invalidations. This stays well within the free 1,000 invalidation-paths/month. A production refinement would batch events (SQS or a single-key event filter) to invalidate once per deploy.

---

## 12. Teardown

To remove everything Terraform created (does **not** touch the manually-made state bucket or your site repo):

```bash
# empty the buckets first (Terraform won't delete non-empty buckets)
aws s3 rm s3://myname-site-game-prod --recursive
aws s3 rm s3://myname-site-game-dev  --recursive

cd environments/prod && terraform destroy   # type: yes  (CloudFront removal also takes a few minutes)
cd ../dev  && terraform destroy             # type: yes
cd ../cicd && terraform destroy             # type: yes
```

The state bucket you created in §5 can be deleted manually from the S3 console once all environments are destroyed.

---

*Built as an infrastructure-as-code exercise: reproducible, secured, isolated, and shipped through a pipeline — the delivery is the point, not the game.*
