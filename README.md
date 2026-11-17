# Cloudflare Terraform

A Terraform module that sets up a small business's domain on Cloudflare from one short config file: DNS records, email records (MX, SPF, DKIM, DMARC), a www-to-apex redirect, and HTTPS-only security settings. I use it for my own live domain, including its email, from a separate private repo.

```hcl
module "my_business" {
  source  = "./modules/business-domain"
  zone_id = var.zone_id
  domain  = "example.com"

  email_provider = "google"   # icloud | google | microsoft | none

  dmarc_policy       = "quarantine"
  dmarc_report_email = "hello@example.com"
}
```

`terraform plan` previews exactly what would change. `terraform apply` makes the change. If someone edits a record by hand in the dashboard, the next `plan` shows the difference.

## The problem

I move small businesses' domains and email onto Cloudflare. Done by hand in a dashboard, it is slow and easy to get wrong: one mistyped SPF record and a client's email starts landing in spam, and nobody can see afterwards what was changed or why. Here the whole setup is code that can be reviewed, repeated for the next domain, and rolled back.

I also built this to learn Terraform properly. I wrote it one piece at a time and explained each part back before moving on; those notes, with the interview questions I practised, are in [`LEARNING.md`](LEARNING.md).

## What the module manages

| Area | What it creates | Inputs |
| --- | --- | --- |
| Email | MX and SPF records for a preset provider | `email_provider` |
| Email signing | DKIM records from the provider | `dkim_records` |
| Email policy | A DMARC record | `dmarc_policy`, `dmarc_report_email` |
| Website | Proxied `www` and apex records, and a 301 redirect from `www` to the bare domain | none |
| Security | Always Use HTTPS, minimum TLS version | `min_tls_version` |
| Anything else | Verification proofs, a mail-sending service's CNAMEs, extra MX records, CAA (which certificate authorities may issue certificates) | `extra_records` |

Every input has a `description` and a `validation` block, so a typo fails at `plan` with a clear message instead of at `apply` with an API error.

## Layout

```
modules/business-domain/   the reusable module
modules/business-domain/tests/   21 unit tests (terraform test, fake provider)
examples/basic/            a fictional business (example.com) showing every input
tf, new-domain, records    helper scripts for running the module on several domains (see below)
tests/scripts.sh           tests for the helper scripts
domains/                   where new-domain puts your domains; git-ignored on purpose
.github/workflows/         format, validate, lint and test on every push
LEARNING.md                what each step taught me, in my own words
```

The module contains nothing specific to one business. Anything particular to a domain (a mail-sending service's records, ownership proofs) is passed in through `extra_records` by the caller; see [`examples/basic/main.tf`](examples/basic/main.tf). Real domains use the same module from separate private repos, so no real domain, account ID or token is ever in this one.

## Design decisions

- **Existing infrastructure was imported, not rebuilt.** My own domain was already live with working email, so I wrote config for all 13 of its records, imported them, and only accepted the result once `plan` showed no changes. Rebuilding would have meant downtime for my own mail.
- **`moved` blocks for every refactor.** Turning loose resources into a module, and later into `for_each`, changes their addresses. Without `moved`, Terraform would destroy the live records and create new ones. With it, the plan stayed at zero changes through every refactor.
- **`for_each` for lists of things, `count` for yes or no.** MX records and extra records use `for_each` keyed by a stable name, so reordering the list doesn't shift every record. SPF uses `count`, which is 0 or 1 depending on the provider.
- **`extra_records` is keyed by a label I choose, not the record name.** Several DNS records share a name (three TXT proofs at the bare domain), and `for_each` keys must be unique.
- **`email_provider` has no default, but `dmarc_policy` does.** A forgotten email provider silently becoming `none` would delete the MX records and stop the domain's mail, so it must be chosen. `dmarc_policy` defaults to `none`, which only reports and never affects delivery. Tightening it to `reject` is a deliberate step.
- **State lives in a private Cloudflare R2 bucket with locking.** One shared copy survives a lost laptop, and the lock stops two runs overwriting each other. Backend settings go in a git-ignored `backend.hcl`, since a backend block can't read variables.
- **The module has unit tests that can't reach Cloudflare.** `terraform test` runs against a mock provider: 11 tests check what the module builds (record counts per mail provider, names, DMARC content, the redirect), and 10 check that every bad input is rejected, so a weakened validation fails a test.
- **CI never touches state or the API token.** It runs `terraform fmt -check`, `validate`, `tflint` and the tests with `init -backend=false`. If CI could reach the state bucket, anyone who got code into a pull request could read or change real infrastructure.
- **Versions are pinned.** Terraform `~> 1.17` and the Cloudflare provider `~> 5.29`, with the lock file committed, so a different version can't quietly change a plan. Provider v5 renamed many resources compared with v4.
- **The API token is scoped to one zone** (DNS edit, zone settings edit, zone read, redirect edit) and lives in a git-ignored `.env`.

## Using it

Each domain you manage gets its own folder and its own state file (Terraform's record of what it created), so a change to one domain can't touch another. Three small scripts do the routine work: `./new-domain` makes a domain's folder, `./tf` runs Terraform in it with your credentials loaded, and `./records` shows what Cloudflare actually holds.

### What you need first

- Terraform 1.17 or newer. `curl` and `jq` are needed only for `./records`.
- A Cloudflare account with your domain added. Adding it creates the **zone** (Cloudflare's container for the domain's DNS records); the module doesn't create it for you.
- Three credentials from your Cloudflare dashboard, which the next section walks through. They go in a git-ignored `.env` file, and no one else ever needs to see them.

### Get your credentials

You need three values for `.env`, from two different places in the dashboard. They look alike and are easy to mix up, so the table lists which is which:

| `.env` variable | What it is | Where it comes from |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Lets Terraform edit your domain's DNS | An **API token** (below, A) |
| `AWS_ACCESS_KEY_ID` | The "username" for the state bucket | An **R2 API token** (below, B) |
| `AWS_SECRET_ACCESS_KEY` | The "password" for the state bucket | The same R2 API token, shown once |

The two `AWS_` names look odd for a Cloudflare setup. R2 speaks the same protocol as Amazon's storage service (S3), and Terraform's state backend reads those standard names, so the R2 keys go under them. They are **not** AWS credentials.

**A. The Cloudflare API token** (for DNS)

1. In the dashboard, go to **My Profile > API Tokens** and choose **Create Token**. Start from scratch with a custom token rather than a template, because the module needs more than DNS.
2. Add four permissions. Each row below is one permission in the dashboard's list, under the section named in the first column; tick the boxes shown:

   | Section | Permission | Tick |
   | --- | --- | --- |
   | DNS & Zones | DNS | Edit |
   | DNS & Zones | Zone | Read |
   | DNS & Zones | Zone Settings | Edit |
   | Rules & Configuration | Single Redirect | Read and Edit |

   Leave everything else unticked. Cloudflare may rename or move these over time, so match by what they do: edit DNS records, read the zone, edit its settings and edit its redirect rule.
3. Under **Zone Resources**, choose your specific domain. Limiting the token to one zone means a leaked token can't touch your other domains.
4. Create it and **copy the token now**. Cloudflare shows it once.

**B. The R2 bucket and its keys** (for state)

1. In the dashboard, open **R2 object storage** and create a bucket. Keep it private, which is the default. Note its name.
2. On the same R2 page, under **Account Details**, choose **Manage** next to **API Tokens**, then create an API token with **Object Read & Write** permission, limited to that bucket.
3. Copy the **Access Key ID** and the **Secret Access Key** now. The secret is shown once.
4. Also note your **account ID**, shown on the R2 page. It goes into `backend.hcl` in step 3, not into `.env`.

You'll also need your domain's **zone ID** in step 3. It's on the domain's Overview page, in the right-hand column.

### Step by step

**1. Clone the repo and fill in `.env`.**

```
git clone https://github.com/timrios/cloudflare-terraform.git
cd cloudflare-terraform
cp .env.example .env
```

Open `.env` and paste in the three values from the previous section, after the `=` on each line. `.env` is git-ignored, so none of them ever reaches git or your shell history. Never paste them into a chat, a commit or a command line.

**2. Make a folder for your domain.**

```
./new-domain acme-shop acme.com google
```

The three values are:

| Value | What it is | What it controls |
| --- | --- | --- |
| `acme-shop` | A name you choose for the folder | The folder's name, and the name of this domain's state file. Lowercase letters, digits and dashes only. |
| `acme.com` | Your real domain | The domain the records are created for. |
| `google` | Who handles this domain's email | Which **MX** and **SPF** records are created (table below). |

Email is what most often goes wrong when a domain moves, so `email_provider` is deliberately required, with no default. **MX records** say where incoming mail is delivered. **SPF** is a record that lists which servers may send mail as your domain. Pick the one that actually hosts your mail:

| `email_provider` | Use it when | The module creates |
| --- | --- | --- |
| `none` | The domain has no email, or you manage its email records yourself | No MX and no SPF |
| `icloud` | Mail is hosted by Apple (iCloud+ custom domain) | 2 MX records and an SPF record |
| `google` | Mail is hosted by Google Workspace | 5 MX records and an SPF record |
| `microsoft` | Mail is hosted by Microsoft 365 | 1 MX record (named from your domain) and an SPF record |

Whatever you pick, the module also creates a **DMARC** record, which tells receiving mail servers what to do with mail that claims to be from your domain but fails its checks. The default policy only reports and never affects delivery. **DKIM** is a signing key unique to your account, so your mail provider gives it to you and you add it yourself (step 4). If you're unsure, start with `none`: it creates no mail records, so it can't redirect your mail anywhere.

The script creates `domains/acme-shop/` with the boilerplate, a short `main.tf`, and the state key already set to `acme-shop/terraform.tfstate`. It prints the next steps. It refuses a bad name, an unknown provider or a folder that already exists, and it never copies a zone ID or token.

**3. Add your own values.** Two files in the new folder, both git-ignored:

- `terraform.tfvars`: copy `terraform.tfvars.example` and put in your **zone ID** (Cloudflare dashboard, your domain's Overview page, right-hand column).
- `backend.hcl`: copy `backend.hcl.example` and put in your R2 bucket name and Cloudflare account ID.

**4. Describe your domain in `main.tf`.** Change the placeholder `dmarc_report_email` to an address you read, since DMARC reports are sent there. Then add `dkim_records` (from your mail provider) and `extra_records` (verification TXT records, a mail-sending service's CNAMEs and so on). [`examples/basic/main.tf`](examples/basic/main.tf) shows every input.

**5. Connect to state and preview.**

```
./tf acme-shop init -backend-config=backend.hcl
./tf acme-shop plan
```

`init` downloads the provider and connects to the bucket. `plan` is a preview and changes nothing. Read it: if it shows anything **destroyed** or **replaced**, stop and work out why before going on. If your domain already has records in Cloudflare, read the next section before you apply.

**6. Apply, then check.**

```
./tf acme-shop apply
./records acme-shop
```

`./records` lists every record Cloudflare holds for the zone; each should be marked `managed`. Change the nameservers at your registrar last, once the records are right, and send a test email both ways.

### If your domain already has records

Cloudflare scans a new zone and copies in the records it finds, and a domain that already works has mail and website records. Terraform doesn't know about those records, so the first `plan` lists them as "create", and `apply` fails with "already exists". The fix is to **import** them: tell Terraform that the record already exists and which block of your config describes it.

1. Run `init` as in step 5, then `./records acme-shop`. With nothing imported yet, every record shows `NOT IN STATE`. Note each record's ID.
2. In the domain's folder, create `imports.tf` with one block per record. Each needs the record's address and its ID, written `<zone_id>/<record_id>`:

   ```
   import {
     to = module.acme_shop.cloudflare_dns_record.spf[0]
     id = "<zone_id>/<record_id>"
   }
   ```

   The module is named after the folder with dashes turned into underscores (`acme-shop` becomes `acme_shop`). The record's address goes after `module.acme_shop.`; these are the names inside the module:

   | Record | Address |
   | --- | --- |
   | An MX record | `cloudflare_dns_record.mx["<mail host>"]`, for example `["aspmx.l.google.com"]` |
   | SPF | `cloudflare_dns_record.spf[0]` |
   | DKIM | `cloudflare_dns_record.dkim["<key from dkim_records>"]` |
   | DMARC | `cloudflare_dns_record.dmarc_txt` |
   | One from `extra_records` | `cloudflare_dns_record.extra["<its label>"]` |

3. Run `plan`. Each import shows as "will be imported", and a record whose config matches the live one needs no change. If the plan wants to **update** an imported record, your config differs from what's live. Decide which is right before applying, especially for mail records.
4. Apply. Then run `./records` again: every record should now be `managed`. The `import` blocks can stay or be deleted; they do nothing once the record is in state.

The alternative is deleting the scanned record in the dashboard and letting Terraform recreate it, which leaves a short gap. Importing is safer for any record that carries live mail.

### Keeping real domains out of this repo

`./new-domain` writes to `domains/`, which `.gitignore` excludes, and a test fails if anything under it is committed. This repo is meant to stay generic. To keep your own domains under version control, use a private repo of your own and point the scripts at it:

```
./new-domain --dir ~/my-dns --module-source "git::https://github.com/<you>/cloudflare-terraform.git//modules/business-domain?ref=v0.2.0" acme-shop acme.com google
./tf --dir ~/my-dns acme-shop plan
```

`--module-source` is required with `--dir` because Terraform only accepts a relative module path that starts with `./` or `../`, and a folder outside this repo has no fixed path to the module.

### The scripts

- **`./new-domain [--dir PATH] [--module-source SOURCE] <folder> <domain> <email_provider>`** makes the folder, as above.
- **`./tf [--dir PATH] <folder> <terraform command>`** loads credentials from `.env`, then runs Terraform in that folder. A folder's own `.env` overrides the shared one, so each domain can have a token limited to its own zone. It refuses to run if the state key doesn't match the folder name, so two domains can never share one state.
- **`./records [--dir PATH] <folder>`** is read-only. It flags `NOT IN STATE` (a record Terraform doesn't know about, so a `plan` stays silent about it) and `IN STATE ONLY` (a record Terraform expects that is gone from Cloudflare).

`examples/basic/` is the fictional `example.com` the repo's tests and CI validate, and the template `./new-domain` copies from. It isn't meant to be applied as it is, because `example.com` isn't yours. `./tf example ...` runs Terraform in it if you want to experiment.

## Limits and next steps

- `terraform plan` doesn't run in CI in this repo, on purpose: a plan needs a real zone, real state and a token, and this repo is public and holds none of them. It runs in the private repo that uses the module, on every pull request, with a read-only Cloudflare token and an Object Read only key for the state bucket, so CI can show a plan but can't change anything.
- `extra_records` supports TXT, CNAME, MX and CAA records only. The tests use a mock provider, so they prove the module builds the right CAA data but not that Cloudflare accepts it; the first real CAA record is the live check.
- The `www` and apex records point at a placeholder address (`100::`) and rely on Cloudflare's proxy to serve the site, which suits sites hosted on Cloudflare itself.
- One module call manages one domain.

## Status

### Pick up here

The module, the example, remote state, unit tests and CI are built, published and green. Tagged `v0.1.0`; the next release is made when changes are ready (patch for a fix, minor for a feature, major for a breaking change). Plan-in-CI works in the private repo. Tagged `v0.2.0` (adds `MX` and `CAA` to `extra_records`, 26 tests); the private repo now uses it and its plan shows no changes. The second domain is set up in the private repo (its own folder, applied 2026-11-16 to 17; SPF, DKIM and DMARC pass). Apple's iCloud setup changed four records behind Terraform's back, so they were refreshed out of the state and imported again; the plan shows no changes. The record lister (`./records`) and the new-domain script (`./new-domain`) are built. The public helper scripts (`new-domain`, `tf`, `records`) are built, tested and in CI (2026-11-17); the commits after the scrub are local until pushed. Next: decide how the private repo uses the public scripts (one copy, not two), then put the project on timrios.dev (portfolio). Terraform is for Tim's own domains; client domains use the launch checklist, not this module, unless the timing and the client's needs justify it (decided 2026-11-16).

### In progress

**Public versions of the helper scripts** (decided 2026-11-17), so a newcomer who finds this repo gets the whole workflow and not just the module. Design:

- No personal values. `new-domain` copies from `examples/basic/` (the fictional `example.com` folder), not a real domain's folder.
- A choice of module source: the relative path `../../modules/business-domain` by default, or a `--module-source` option for the GitHub URL and tag form the private repo uses.
- `records` and `tf` hold nothing personal, so they need generalising (folder per domain, not just `examples/basic`) plus docs and a matching `.env.example`.
- Safety: real domains must not end up committed in this public repo. `.gitignore` already blocks `tfvars`, `.env` and state; the script also warns, or creates the folder outside the repo, and the docs say real domains go in your own private repo.
- Quality bar: `shellcheck` in CI, plus a test that runs `new-domain` in a temp folder and checks the state key is set and that a bad name, an existing folder and an unknown email provider are refused.
- One true copy: this repo becomes the canonical version; the private repo's scripts later point at it (decide how when we get there).

Order: `new-domain` first (most to generalise), then `tf`, then `records`, then the tests and CI, then the README section.

- [ ] Decide how the private repo uses the public scripts (one copy, not two)

### Not started

- [ ] Judge whether clients should get Terraform. The second domain was started the evening of 2026-11-16 and finished 2026-11-17, with the Apple detour (a real-world drift problem) taking a good part of it; no exact time was kept

### Recently completed

- [x] README "Using it" rewritten as one newcomer guide: what each `new-domain` argument controls (including what each `email_provider` creates), a "domain that already has records" section with `import` blocks (addresses checked with `terraform validate`), and `./records` fixed for a domain whose state is still empty (2026-11-17)
- [x] README section "Managing more than one domain": the three scripts, `--dir`, and keeping real domains out of this repo (2026-11-17)
- [x] `shellcheck` in CI and `tests/scripts.sh` (18 checks: new-domain good run and refusals, tf key check, generated config validates, nothing tracked under `domains/`) (2026-11-17)
- [x] Public `records` (same folder rules as `tf`, checks for `curl`/`jq`, a token and a zone ID; on a real zone its output was identical to the private script's) (2026-11-17)
- [x] Public `tf` that takes a folder name (or `--dir`), loads `.env` files and refuses on a mismatched state key (2026-11-17)
- [x] Public `new-domain` (from `examples/basic/`; folders go in the git-ignored `domains/`, or `--dir` with a required `--module-source`; generated config checked with `terraform validate`) (2026-11-17)
- [x] `./new-domain <folder> <domain> <email_provider>` in the private repo: makes a new domain's folder from the safe boilerplate, writes a minimal `main.tf`, sets the state key with `sed` and checks it; refuses bad names, existing folders and unknown providers (2026-11-17)
- [x] `./records <folder>` in the private repo: lists a zone's records with their IDs and flags any not in the state (and any in the state but gone from Cloudflare); read-only; the second domain shows all eight as managed (2026-11-17)

- [x] Second domain set up by hand in the private repo and applied; iCloud mail works (SPF, DKIM and DMARC pass); Apple's Cloudflare authorization replaced four records, fixed with `apply -refresh-only` and `import`; plan shows no changes (2026-11-17)
- [x] Tagged `v0.2.0`; the private repo's `ref` bumped and its plan showed no changes (2026-11-16)
- [x] `extra_records` accepts `MX` (with a required priority) and `CAA` (with a tag, sent as structured data), tests written first (2026-11-16)
- [x] `terraform plan` in CI, built in the private repo that uses the module: read-only Cloudflare token, Object Read only R2 key, `pull_request` trigger, never applies (2026-11-16)
- [x] `terraform test`: 21 tests with a mock provider (behaviour and validation), run in CI (2026-11-16)
- [x] Tagged `v0.1.0` so other repos can pin a version (2026-11-16)
- [x] Published on GitHub; first CI run passed (2026-11-16)
- [x] Real domain moved out: the live config now lives in a separate private repo that uses this module, and the example here is fictional (2026-11-16)
- [x] Module made fully generic: domain-specific records moved out into an `extra_records` input keyed by label, with `moved` blocks so the plan stayed at zero changes (2026-11-16)
- [x] README rewritten for a hiring manager (2026-11-16)
- [x] CI: `terraform fmt -check`, `validate` (module and example) and `tflint` on every push (2026-11-16)
- [x] Remote state in a private R2 bucket with locking, backend settings in a git-ignored partial config (2026-11-16)
- [x] `validation` review: every input has a check, and two were made to fail on purpose (2026-11-16)
- [x] Security settings (Always Use HTTPS, minimum TLS) and the www-to-apex redirect, the latter imported from an existing dashboard rule (2026-11-16)
- [x] Email presets (iCloud, Google Workspace, Microsoft 365, none) with `for_each`, `count`, DKIM and DMARC inputs (2026-11-16)
- [x] Module with `domain` variable and outputs; existing records imported and refactored with `moved` blocks (2026-11-15 to 2026-11-16)
