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
| Anything else | Verification proofs, a mail-sending service's CNAMEs | `extra_records` |

Every input has a `description` and a `validation` block, so a typo fails at `plan` with a clear message instead of at `apply` with an API error.

## Layout

```
modules/business-domain/   the reusable module
examples/basic/            a fictional business (example.com) showing every input
.github/workflows/         format, validate and lint checks on every push
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
- **CI never touches state or the API token.** It runs `terraform fmt -check`, `validate` and `tflint` with `init -backend=false`. If CI could reach the state bucket, anyone who got code into a pull request could read or change real infrastructure.
- **Versions are pinned.** Terraform `~> 1.17` and the Cloudflare provider `~> 5.29`, with the lock file committed, so a different version can't quietly change a plan. Provider v5 renamed many resources compared with v4.
- **The API token is scoped to one zone** (DNS edit, zone settings edit, zone read, redirect edit) and lives in a git-ignored `.env`.

## Using it

You need Terraform 1.17 or newer, a Cloudflare account with the domain added, an API token limited to that zone, and an R2 bucket for state.

1. Copy `.env.example` to `.env` and fill in the Cloudflare token and the R2 access keys.
2. In `examples/basic/`, copy `terraform.tfvars.example` to `terraform.tfvars` (your zone ID) and `backend.hcl.example` to `backend.hcl` (your bucket and account ID). Both copies are git-ignored.
3. Edit `main.tf` for your domain (the example uses `example.com`), then run:

```
./tf init -backend-config=backend.hcl
./tf plan
./tf apply
```

`./tf` is a small wrapper that loads the token from `.env` and runs Terraform in the example folder, so the token never appears in shell history.

## Limits and next steps

- `terraform plan` doesn't run in CI yet. It needs a read-only token and state access, so I want to design that carefully, with a GitHub secret and no plans from forks.
- `extra_records` supports TXT and CNAME records only.
- The `www` and apex records point at a placeholder address (`100::`) and rely on Cloudflare's proxy to serve the site, which suits sites hosted on Cloudflare itself.
- One module call manages one domain.

## Status

### Pick up here

The module, the example, remote state and CI are built, published, and the first CI run is green. Next: tag `v0.1.0` so other repos can pin a version.

### Not started

- [ ] Tag `v0.1.0` so other repos can pin a version
- [ ] Later: `terraform plan` in CI with a read-only token as a GitHub secret

### Recently completed

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
