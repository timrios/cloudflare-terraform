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

You need Terraform 1.17 or newer, a Cloudflare account with the domain added, an API token limited to that zone, and an R2 bucket for state.

1. Copy `.env.example` to `.env` and fill in the Cloudflare token and the R2 access keys.
2. In `examples/basic/`, copy `terraform.tfvars.example` to `terraform.tfvars` (your zone ID) and `backend.hcl.example` to `backend.hcl` (your bucket and account ID). Both copies are git-ignored.
3. Edit `main.tf` for your domain (the example uses `example.com`), then run:

```
./tf example init -backend-config=backend.hcl
./tf example plan
./tf example apply
```

`./tf <folder>` is a small wrapper that loads the token from `.env` and runs Terraform in that folder, so the token never appears in shell history. `example` is the folder in `examples/basic/`; folders made by `./new-domain` are named by their folder (`./tf acme-shop plan`), and `--dir <path>` points at a folder in your own private repo. It refuses to run when the folder name and the state key in `backend.tf` disagree, so two domains can never share one state.

## Limits and next steps

- `terraform plan` doesn't run in CI in this repo, on purpose: a plan needs a real zone, real state and a token, and this repo is public and holds none of them. It runs in the private repo that uses the module, on every pull request, with a read-only Cloudflare token and an Object Read only key for the state bucket, so CI can show a plan but can't change anything.
- `extra_records` supports TXT, CNAME, MX and CAA records only. The tests use a mock provider, so they prove the module builds the right CAA data but not that Cloudflare accepts it; the first real CAA record is the live check.
- The `www` and apex records point at a placeholder address (`100::`) and rely on Cloudflare's proxy to serve the site, which suits sites hosted on Cloudflare itself.
- One module call manages one domain.

## Status

### Pick up here

The module, the example, remote state, unit tests and CI are built, published and green. Tagged `v0.1.0`; the next release is made when changes are ready (patch for a fix, minor for a feature, major for a breaking change). Plan-in-CI works in the private repo. Tagged `v0.2.0` (adds `MX` and `CAA` to `extra_records`, 26 tests); the private repo now uses it and its plan shows no changes. The second domain is set up in the private repo (its own folder, applied 2026-11-16 to 17; SPF, DKIM and DMARC pass). Apple's iCloud setup changed four records behind Terraform's back, so they were refreshed out of the state and imported again; the plan shows no changes. The record lister (`./records`) and the new-domain script (`./new-domain`) are built. Next: put the project on timrios.dev (portfolio), then the remaining task below. Pushed and scrubbed of real domain names on 2026-11-17. Terraform is for Tim's own domains; client domains use the launch checklist, not this module, unless the timing and the client's needs justify it (decided 2026-11-16).

### In progress

**Public versions of the helper scripts** (decided 2026-11-17), so a newcomer who finds this repo gets the whole workflow and not just the module. Design:

- No personal values. `new-domain` copies from `examples/basic/` (the fictional `example.com` folder), not a real domain's folder.
- A choice of module source: the relative path `../../modules/business-domain` by default, or a `--module-source` option for the GitHub URL and tag form the private repo uses.
- `records` and `tf` hold nothing personal, so they need generalising (folder per domain, not just `examples/basic`) plus docs and a matching `.env.example`.
- Safety: real domains must not end up committed in this public repo. `.gitignore` already blocks `tfvars`, `.env` and state; the script also warns, or creates the folder outside the repo, and the docs say real domains go in your own private repo.
- Quality bar: `shellcheck` in CI, plus a test that runs `new-domain` in a temp folder and checks the state key is set and that a bad name, an existing folder and an unknown email provider are refused.
- One true copy: this repo becomes the canonical version; the private repo's scripts later point at it (decide how when we get there).

Order: `new-domain` first (most to generalise), then `tf`, then `records`, then the tests and CI, then the README section.

- [x] Public `new-domain` (from `examples/basic/`; folders go in the git-ignored `domains/`, or `--dir` with a required `--module-source`; generated config checked with `terraform validate`) (2026-11-17)
- [x] Public `tf` that takes a folder name (or `--dir`), loads `.env` files and refuses on a mismatched state key (2026-11-17)
- [x] Public `records` (same folder rules as `tf`, checks for `curl`/`jq`, a token and a zone ID; on a real zone its output was identical to the private script's) (2026-11-17)
- [x] `shellcheck` in CI and `tests/scripts.sh` (18 checks: new-domain good run and refusals, tf key check, generated config validates, nothing tracked under `domains/`) (2026-11-17)
- [ ] README section for newcomers: how to use the three scripts with your own domain
- [ ] Decide how the private repo uses the public scripts (one copy, not two)

### Not started

- [ ] Judge whether clients should get Terraform. The second domain was started the evening of 2026-11-16 and finished 2026-11-17, with the Apple detour (a real-world drift problem) taking a good part of it; no exact time was kept

### Recently completed

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
