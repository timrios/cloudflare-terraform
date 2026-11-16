# What I learned

My own notes, one section per step, written after each step is understood, not before. Each section has:

- **What we did:** a sentence or two.
- **The idea, in my words:** how I'd explain it to an interviewer.
- **Questions an interviewer might ask:** with my answers.

This file is also my review sheet before an interview.

## Words to know

Added the first time each comes up.

| Term | Meaning |
|---|---|
| Infrastructure as code | Describing servers, DNS and settings in text files that can be reviewed, versioned and re-run, instead of setting them up by hand |
| Declarative | Describing the end result you want, not the steps. Terraform compares it with what exists and works out only the difference |
| Provider | A plugin that turns Terraform's resources into one service's API calls (here, Cloudflare's) |
| Tap (Homebrew) | An extra source of install recipes. HashiCorp's tap gives the official Terraform build |
| Least privilege | Giving a token or account only the access it needs, so a leak or a mistake can't reach further |
| Lock file (`.terraform.lock.hcl`) | Records the exact provider version and checksums `init` chose, so every machine gets an identical build. Committed to git |
| `.terraform/` folder | A cache of downloaded providers. Rebuilt by `init`, so git-ignored |
| State | Terraform's memory: a file pairing each resource label in the config with the real object's ID. Never committed |
| Import | Attaching an existing real object to a resource block, by writing the pairing into state without creating or changing anything |
| Drift | The real thing differing from what the config or state says, usually from a manual dashboard edit |
| Resource label | The name after the resource type (`icloud_mx1`). It is the resource's identity inside Terraform; the real object's ID lives in state |
| Refresh | The first part of `plan`: Terraform asks the provider about every object in state to see what is really there |
| Module | A folder of `.tf` files called from another folder, like a function. The calling folder is the root module |
| Input variable | A parameter the caller passes into a module |
| Address | A resource's identity in state, such as `module.my_domain.cloudflare_dns_record.spf_txt`. Moving code into a module changes it |
| `moved` block | Tells Terraform a resource only changed address, so it renames the state entry instead of destroying and recreating the real object |
| Saved plan | `plan -out=file`, then `apply file`: applies exactly the reviewed actions, with no prompt |
| `terraform test` | Runs `.tftest.hcl` files: each `run` block gives the module inputs and asserts claims about the result |
| `mock_provider` | A fake provider for tests, so they need no token and never contact the real API |
| `expect_failures` | In a test, says a run should fail on a named validation. The test passes only if it does |
| List vs tuple | A list holds one type; a tuple is a fixed sequence that can mix types. A written-out `[...]` is a tuple, and `==` between the two is false |

## Step 1 — Setup

**What we did:** Installed Terraform (v1.17.2) from HashiCorp's Homebrew tap. Made a Cloudflare API token limited to DNS edit, zone settings edit and zone read, for my live domain only. Stored it in a git-ignored `.env` as `CLOUDFLARE_API_TOKEN`. Pinned Terraform (`~> 1.17`) and the Cloudflare provider (`~> 5.29`) in `versions.tf`, then ran the first `terraform init`.

**The idea, in my words:**
- Using Terraform is like talking to an application's API in the backend, not clicking through a GUI as if I had eyes. I give it code describing what I want and it makes the same changes without the front end.
- It is declarative: if I run `apply` twice with no changes, nothing happens the second time, because what I declared matches what exists.
- Least privilege limits the potential for widespread error or harm from bad actors. A token scoped to one zone can only damage that zone.
- A git-ignored `.env` means the API key can't accidentally be shared publicly. The provider reads it from the environment, so no secret is in the code.
- The lock file is committed because it holds checksums that guarantee an identical build. `.terraform/` isn't a secret; it's a cache I can always recreate with `init`.

**Questions an interviewer might ask:**
- *What happens if you run `apply` twice in a row with no changes?* Nothing the second time. Terraform compares my files with the real setup, finds no difference and does nothing.
- *Why scope an API token to one zone?* Least privilege: it limits the blast radius of a leak or a mistake.
- *Why is the lock file committed but `.terraform/` not?* The lock file pins exact provider versions and checksums for identical builds. `.terraform/` is a rebuildable cache of downloaded binaries.
- *Why pin the provider version?* An unpinned provider could upgrade itself (v5 renamed many v4 resources) and change the plan without any code change.

## Step 2 — Import what already exists

**What we did:** Wrote a `cloudflare_dns_record` block for each of my live domain's 13 live records (website AAAA, iCloud MX/SPF/DKIM, Resend CNAMEs and DKIM, DMARC, Google and Apple verification) and an `import` block pairing each with its real record ID. Applied the imports in three small batches, checking each plan first. Result: `terraform plan` shows no changes.

**The idea, in my words:**
- Zone read finds information about the zone (its ID and status). DNS edit is what lets Terraform change the records inside it.
- Importing first matters because Terraform doesn't know a live record exists until it's in state. A plan that shows no changes proves the code matches reality before anything is allowed to change it.
- An import block needs both halves: the label (`to`, which resource block it belongs to) and the real record ID (`id`). Without a matching `resource` block, Terraform fails with an error rather than creating one.
- Records can look identical in the dashboard (same name, same type). In Terraform each has a unique label, and its real record ID is stored in state.
- If a record is deleted in the dashboard, the next `plan` shows it would be added back, and `apply` recreates it. `plan` never changes anything itself.
- If someone edits the dashboard on purpose, either `apply` reverts it, or I write the change into the `.tf` file too. The config is the source of truth, so changes should be made in Terraform, not the dashboard.

**Questions an interviewer might ask:**
- *Why import before changing anything?* Terraform doesn't know existing resources exist. Without import, `apply` would try to create duplicates. A "no changes" plan after import proves the config matches what's live.
- *What does the import block's `to` and `id` mean?* `to` is the resource address in the config; `id` identifies the real object (zone ID and record ID for a DNS record).
- *What happens if the `id` points at the wrong record?* It imports that record, and the plan shows a change or replace because it doesn't match the config. That's why you read the plan before applying.
- *What happens if a record is deleted in the dashboard?* Refresh notices it's gone, the plan shows one record to add, and `apply` recreates it with a new ID.
- *What if someone adds a record in the dashboard that isn't in the config?* Terraform doesn't see it. It only checks what it manages.
- *Why are the labels not just the record names?* Several records share a name (four TXT and two MX at the apex), so labels describe purpose.
- *Why are email records not proxied?* The Cloudflare proxy only handles web traffic, so mail records stay DNS-only.

## Step 3a — Move the records into a module

**What we did:** Deleted the 13 `import` blocks, copied the records into `modules/business-domain/` (with `zone_id` as an input variable), replaced `dns.tf` with a `module` call, and added 13 `moved` blocks. Plan showed 13 moves and nothing to add, change or destroy; applied it as a saved plan.

**The idea, in my words:**
- Once records are in state, the import blocks are no longer needed. Left behind, they would point at addresses that no longer exist.
- The `moved` blocks stay in `main.tf` as a record for anyone whose state hasn't been updated yet.
- Moving a resource into a module changes its address, so without `moved` Terraform would plan to destroy and recreate live records.

**Two things that went wrong, and what they taught:**
- `init` failed with "hashicorp/cloudflare does not exist". Each module needs its own `required_providers`; without a `source`, Terraform guesses `hashicorp/<name>`. A module states a version range, and the root's lock file picks the exact version.
- `apply` through `!` aborted with "error asking for approval: EOF", because there is no keyboard to type `yes`. Fix: `plan -out=file` then `apply file`.

**Questions an interviewer might ask:**
- *What happens if you move a resource into a module without a `moved` block?* The old address disappears from the config and the new one isn't in state, so Terraform plans to destroy the real object and create a new one.
- *`moved` block or `terraform state mv`?* Both rename the state entry. `moved` is declarative, reviewable in git and shown in `plan`; `state mv` is a one-off manual edit nobody else can see.
- *Why does a module use a version range while the root pins tightly?* The module only states what it works with; the root decides what actually runs.
- *Why apply a saved plan?* It guarantees the applied actions are exactly the ones that were reviewed.
- *When can `moved` blocks be deleted?* Once every state that uses the config has been applied. Keeping them is harmless.

## Step 3b — The domain becomes a variable

**What we did:** Added a `domain` input variable (with a `validation` block that rejects `https://`, capitals and trailing dots) to `modules/business-domain`. Every record name, plus the iCloud DKIM target, is now built with `"${var.domain}"`. the example's `main.tf` passes a `domain`. The plan showed no changes.

**The idea, in my words:**
- A variable is an input the caller passes in, so the same module can serve any domain. `"www.${var.domain}"` splices the variable into a string (interpolation).
- A refactor should give a "No changes" plan. Terraform compares the config to the state, and the built strings came out identical to the stored ones.
- A typo such as `wwww` would show as a changed record in the plan and would break the live `www` if applied. Reading the plan is what catches it.

**Questions an interviewer might ask:**
- *Why use a variable instead of hard-coding the domain?* The module becomes reusable: one copy of the code, a different `domain` per client.
- *What does a `validation` block do?* It checks an input before any API call and gives a clear error message instead of a confusing failure later.
- *You refactored and the plan shows one record changing. What do you do?* Stop, read which attribute differs, and fix the config. A pure refactor must plan to no changes.
- *Where do variable values come from?* The caller: a `module` argument, `terraform.tfvars`, `-var`, or `TF_VAR_` environment variables.

## Step 3c — Outputs

**What we did:** Added `modules/business-domain/outputs.tf` with a `locals` list of all 13 records and two outputs: `domain`, and `record_names` (`sort(distinct([for r in local.records : r.name]))`). The root re-exports `record_names`. The plan showed only `Changes to Outputs`; applied it as a saved plan, then `terraform output` printed 7 names.

**The idea, in my words:**
- An output is a value a module hands back to its caller. A root only prints outputs it declares itself, so a module's output has to be re-exported.
- A `for` expression builds a new list by taking one attribute from each item. `distinct` collapses repeats (13 records, 7 distinct names) and `sort` keeps the order stable, so reordering resources doesn't make the output look changed.
- Outputs are stored in state, so they appear only after an `apply`. Adding one changes no infrastructure.
- `terraform output` only reads state, so it needs no API token.

**Questions an interviewer might ask:**
- *What are outputs for?* Showing results after `apply`, and passing values from a module to its caller or to other configurations.
- *Why did the module's output not appear until the root declared one?* Module outputs are visible only to the parent; the root must re-export what it wants printed.
- *What is a `locals` block?* Named values computed inside a module, used to avoid repeating an expression.
- *Why `sort` on a list output?* Stable order, so the plan shows a change only when the content changes.

## Step 3d — Email presets

**What we did:** Added `modules/business-domain/email.tf`. A `locals` map of presets (`icloud`, `google`, `microsoft`, `none`) holds each provider's MX servers and SPF text, and a required `email_provider` variable picks one. MX records use `for_each` keyed by hostname, SPF uses `count` (0 or 1), and DKIM is an input map (`dkim_records`) since each domain has its own key. Four `moved` blocks carried the existing iCloud records to their new addresses; the plan showed 4 moves and 0 add, change or destroy, and I applied it as a saved plan.

**The idea, in my words:**
- `for_each` makes one resource per item in a map or set, and the key becomes part of the address. `count` makes N copies identified by position (0, 1, 2).
- `count` is for "0 or 1 of something". `for_each` is for a collection of distinct things.
- Inserting an item into the start of a `count` list shifts every position, so Terraform sees every existing record as changed. A `for_each` key like the hostname keeps the address stable.
- Changing a resource to `for_each` or `count` changes its address, so it needs `moved` blocks or Terraform would destroy and recreate live records.
- `email_provider` has no default on purpose, so a forgotten value is an error, not a silent switch to "none" that would delete the MX records.

**Questions an interviewer might ask:**
- *`count` or `for_each`?* `count` for an on/off switch (0 or 1). `for_each` for distinct items, because keys give stable addresses and `count` positions shift when the list changes.
- *Why does the plan show a record "has moved"?* Same real object (same ID), new address in config. State is renamed, nothing in the cloud changes.
- *Why no default on a variable?* A default can hide a mistake. Here a default of `none` could delete a client's MX records.
- *Why does a variable's validation use a hard-coded list rather than the presets map?* Validation conditions can only refer to the variable itself, not to locals.
- *Why is DKIM an input?* Each domain's provider generates its own key, so the module can't know it.

## Step 3e — DMARC with a policy input

**What we did:** The DMARC record's content is now built from two new variables: `dmarc_policy` (`none`, `quarantine` or `reject`, default `none`, checked with a `validation` block) and `dmarc_report_email` (no default, loose `regex` check). My live domain passed `none` and its own report address. The plan showed no changes and needed no apply. No string from my own domain remains inside the module.

**The idea, in my words:**
- Replacing a hard-coded value with a variable that holds the same value changes nothing in the plan. That's the proof that the refactor is safe.
- A default is fine when forgetting the variable can't cause harm (`none` only reports). A required variable is better when a wrong or missing value would hurt (the email provider, the report address).
- Before tightening DMARC, read the `rua` reports to see whether legitimate mail passes. Move in stages: `none`, `quarantine`, `reject`.
- Third-party senders need to pass SPF or DKIM aligned with the domain, or `reject` bounces their mail. The mail-sending service's records on a `mail.<domain>` subdomain need their own checks, and a subdomain inherits the parent's DMARC policy unless `sp=` overrides it.

**Questions an interviewer might ask:**
- *What does DMARC do?* It tells receivers what to do with mail that fails SPF and DKIM alignment, and where to send reports.
- *Why not set `reject` straight away?* Legitimate third-party senders that aren't aligned would start bouncing. Read the reports first.
- *Why does the module have a default for `dmarc_policy` but not for `dmarc_report_email`?* `none` is harmless; the module can't guess an inbox.
- *Why is there no apply after this change?* The plan showed no change, so state already matches.

## Step 3f (part 1) — Zone settings

**What we did:** Added `security.tf` to the module with two `cloudflare_zone_setting` resources: `always_use_https` set to `on`, and `min_tls_version` set from a new variable (default `1.2`, validated against the four values the API accepts). The plan showed 2 to add and nothing else, and after the apply `curl -I http://my live domain` returned a `301`.

**The idea, in my words:**
- A zone setting always exists on Cloudflare, so the resource doesn't create it. It takes over the setting and keeps it at the value in the code.
- Terraform can't destroy it. Deleting the resource from the code only makes Terraform stop managing it, and the setting stays at its last value. To turn it off, change `value` and apply.
- Checking the result from outside (`curl -I`) proves the change is live, beyond Terraform saying "apply complete".

**Questions an interviewer might ask:**
- *What happens if you delete a `cloudflare_zone_setting` from the code?* Terraform forgets it; the setting keeps its last value.
- *Why is `min_tls_version` a variable with a default?* Most sites want 1.2, but a client with an old device might need a different value, and a default of 1.2 is safe.
- *Why validate against a list?* The API only accepts exact strings, so a typo gets a clear error before `apply`.

## Step 3f (part 2) — The www redirect, by import

**What we did:** Wrote a `cloudflare_ruleset` for the redirect phase, but the plan warned that a zone ruleset already existed for that phase. A read-only API call showed a dashboard-made rule that already did the www to apex 301. So we imported it (`import` block with ID `zones/<zone_id>/<ruleset_id>`), rewrote the code to match it (a wildcard rule with no domain name in it), applied one description change, and removed the import block. `curl -I` proved the path and query string survive the redirect. The token needed the **Dynamic URL Redirects** permission, not Transform Rules.

**The idea, in my words:**
- A zone can hold only one ruleset per phase, so all redirect rules live in one list. A second ruleset would be refused.
- When the plan warns that something already exists, look at what is live before applying. Here the answer was to import, not create.
- The `import` block brings an existing object into state. Once it has done that, it's a finished one-time instruction and can be deleted.
- Inside a Terraform string, a literal dollar-brace has to be escaped by doubling the dollar sign, or Terraform tries to read it as its own interpolation.
- Bookkeeping fields (`id`, `ref`, `version`, `last_updated`) change on every update and aren't a worry.

**Questions an interviewer might ask:**
- *What do you do when a plan warns that the resource already exists?* Inspect the live object, then import it and align the code so the plan is clean.
- *Why one ruleset per phase?* Cloudflare's design: the ruleset is the container and rules are its entries.
- *How do you escape interpolation in Terraform?* Double the dollar sign.
- *Why least-privilege API tokens?* If the token leaks, it can only do what the module needs.

## Tightening DMARC to reject

**What we did:** Changed `dmarc_policy` for my live domain from `none` to `reject` in the example (the module was already built for this). The plan showed one in-place change to the `_dmarc` record's content and nothing else. After the apply, mail sent out, mail received and a test enquiry through the mail-sending service all worked.

**The idea, in my words:**
- Because the policy is a variable, a real-world policy change is a one-word edit, and the plan shows exactly that one line changing.
- `reject` is the strongest setting: receivers bounce mail that fails SPF and DKIM alignment, which stops others from spoofing the domain. The safe route is `none`, then `quarantine`, then `reject`, reading reports at each stage. Going straight to `reject` worked here because every sender was already aligned, and I proved it with tests afterwards.
- After a change that affects live email, test from outside: send, receive and run any app that sends mail.

**Questions an interviewer might ask:**
- *What risk comes with `p=reject`?* Legitimate mail that fails alignment (a forgotten third-party sender, some forwarding) is bounced, not just flagged.
- *How do you roll it back?* Change the variable back and apply; the record's TTL limits how fast receivers see it.
- *How did you know it was safe?* Reviewed which services send as the domain (iCloud, Resend), and tested each path after applying.

## Validation review

**What we did:** Went back over every `validation` block in the module and made two fail on purpose: `-var='zone_id=abc123'` at the root, and a typo (`"gogle"`) for `email_provider` in `main.tf`. Both stopped at once with my own error message, before any call to Cloudflare, and the error pointed at the exact rule.

**The idea, in my words:**
- A `validation` block checks a variable's value while Terraform reads the inputs, so a typo fails in a second with a clear sentence, not as an API error halfway through an `apply`.
- A default is fine only when it's the harmless choice (`dmarc_policy = "none"`, `min_tls_version = "1.2"`). When no value is a safe guess, leave the default off so the caller must choose.
- `email_provider` has no default: a real provider as the default would set up records for a service the domain doesn't use, and a default of `none` would plan to delete the live MX records and silently stop email.

**Questions an interviewer might ask:**
- *When should a variable have no default?* When any default could be wrong in a way that does damage or goes unnoticed.
- *When does validation run compared with the API?* Before it: during input evaluation, so nothing is sent to Cloudflare.
- *Can validation catch everything?* No. It checks the shape of a value (e.g. looks like an address), not whether it's true (the mailbox exists).

## Step 4 — Remote state in R2

**What we did:** Created a private R2 bucket and an R2 API token (its own S3-style key and secret, kept in `.env` as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`). Added an `s3` backend block with `use_lockfile = true` and the checks that only make sense on real AWS switched off. The bucket name and endpoint (which holds the Cloudflare account ID) live in a git-ignored `backend.hcl`, passed with `-backend-config`. `init -migrate-state` copied the state into the bucket, `plan` showed no changes, and I saw the state file (its key is set in the backend block) in the bucket. The old local state files went to the Trash.

**The idea, in my words:**
- State is Terraform's memory of what it manages. On one laptop, losing the laptop loses the memory. In a bucket, anyone with access (and CI) reads the same single copy.
- Locking: while a run is in progress a lock file sits in the bucket, so a second run refuses to start and two runs can't overwrite each other's state.
- A `backend` block can't read variables (Terraform needs it before it loads them), so per-person values go in a partial configuration file, `backend.hcl`, which stays out of git. The bucket and endpoint are separate settings: Terraform joins endpoint, bucket and key itself.
- State can hold sensitive values, so the bucket stays private and the keys never go in code.
- R2 isn't AWS, so the backend skips AWS-only checks (account lookup, region list, metadata service).

**Questions an interviewer might ask:**
- *Why keep state remotely?* One shared source of truth that survives a lost machine, plus locking for concurrent runs.
- *What does locking protect against?* Two runs writing state at once, where the last writer wins and the other's changes are lost.
- *Why can't a backend block use variables?* Terraform has to know where state lives before it can load anything else.
- *How do you keep secrets and account IDs out of a public repo?* Partial configuration with a git-ignored file, and credentials from environment variables.
- *How do you move existing local state to a new backend?* Add the backend block, then `terraform init -migrate-state`.

## Step 5 — Continuous integration

**What we did:** Installed `tflint` with `brew install --cask terraform-linters/tap/tflint` (it's in the project's own Homebrew tap, not the default list, so a plain `brew install tflint` finds nothing), added `.tflint.hcl` using the bundled `terraform` ruleset with the `recommended` preset, and wrote `.github/workflows/terraform.yml`. It runs `terraform fmt -check`, `terraform validate` (module and example) and `tflint` on every push and pull request. I ran the same commands locally first and all passed. The workflow hasn't run on GitHub yet because the repo doesn't exist until Step 6. The module's own `.terraform.lock.hcl` isn't committed: only the root configuration (`examples/basic`) keeps one.

**The idea, in my words:**
- CI is a robot that runs the checks on every push, so a bad change shows up as a failure and nobody has to remember to check.
- CI runs `terraform init -backend=false` so it doesn't use the real state or the token. A normal `init` would fail without them.
- `validate` checks that the config is consistent; the linter catches things like unused variables.

**Added after review:**
- Keeping CI away from state and token is a security decision: if CI could reach the state bucket, anyone who got code into a pull request could read or change real infrastructure.
- `validate` catches config that is *wrong* (misspelled argument, wrong type, reference to a resource that doesn't exist). `tflint` catches config that is *untidy or risky* (unused variables, missing version pins).
- A lock file belongs in the root configuration where `plan` and `apply` run, not in a reusable module; callers have their own.

**Questions an interviewer might ask:**
- *What does your CI check, and why those three things?* Formatting, correctness and lint: all cheap, safe, and need no credentials.
- *Why doesn't CI run `plan` yet?* It needs a token and state access; that's a security decision to make carefully (read-only token, GitHub secret, no plans from forks).
- *Should a module commit its lock file?* No, the root configuration does.
- *Why pin the Terraform version in CI?* So CI tests the same version used locally.

## Step 6a — Making the module truly generic (`extra_records`)

**What we did:** While checking the repo before publishing, we found the module still held records that belonged only to my live domain (Resend's CNAMEs and DKIM key, the Google and Apple verification tokens). Another business using the module would have received them. We added an `extra_records` variable (a map of label to name, type, content and optional ttl) and one `for_each` resource, moved the six records into the example's `main.tf`, and wrote six `moved` blocks. The plan showed 0 changes, and an apply updated only the state.

**The idea, in my words:**
- The module is for what every domain needs. Anything particular to one domain is passed in by the caller.
- `extra_records` is keyed by a label I choose, not by the record name, because several records share a name (three TXT proofs at the bare domain) and `for_each` keys must be unique.
- `moved` turns "delete the old record and create a new one" into "same record, new address". Without it Terraform sees old addresses in state with no config (destroy) and new addresses in config with no state (create).
- A `moved` block changes the state only when applied, so I apply it even though the plan shows no changes.
- `optional(number, 3600)` gives an object field a default, so callers can leave it out.

**Questions an interviewer might ask:**
- *Why key `for_each` by a label instead of the record name?* Names aren't unique in DNS; a duplicate key is an error.
- *What does `moved` do, and what happens without it?* It renames a resource in state. Without it Terraform destroys the old record and creates a new one.
- *You deleted a secret file in a later commit. Is the repo safe?* No: history keeps it. Revoke the credential first, then clean the history.
- *How would you check a module has no hard-coded values from one customer?* Search it for that customer's domain and tokens, and plan it against a second domain.

## Step 6b — Publishing: keeping real data out, and versioning

**What we did:** Before publishing, scanned every file and every commit for secrets and personal data. Moved my real domain's config out of this repo into a separate private repo (`dns-live`, one folder per domain), made the example here a fictional `example.com`, reset this repo to one clean commit so the old history (with my real records in it) never went public, added an MIT license, created the GitHub repo from the command line, watched the first CI run pass, and tagged `v0.1.0`. The private repo now reads the module from the tag.

**The idea, in my words:**
- Deleting a file in a later commit doesn't remove it. Anyone can read old commits, so history is what leaks. If a secret ever got committed, revoke it first, then clean the history.
- A module should stay clean: no real values. A domain's specifics come in through its inputs, so a second domain is a second caller of the module, kept in a private repo, not in the public `examples/` folder.
- One directory per domain, each with its own state, so a change to one can't accidentally touch another. This isolation is only as strong as one line, the state key in `backend.tf`, so the wrapper script refuses to run if the key doesn't match the folder name.
- Terraform matches code to real records by resource address and the state file (found through the R2 key), not by folder paths. That's why moving folders didn't change anything.
- A tag is a fixed name on one commit, and it never moves. Pinning `?ref=v0.1.0` means a change to the module can't alter live DNS until I bump the version on purpose, read the plan, and apply. Rolling back means setting the old tag again.
- Versions are `MAJOR.MINOR.PATCH`: patch for a fix, minor for a new feature that doesn't break anyone, major for a change that forces callers to edit their config. Below `1.0.0` means the inputs are still settling.

**Questions an interviewer might ask:**
- *Why is your repo's history only one commit?* The development history contained real records, so I published a clean copy and kept the full history in a private repo.
- *Why keep the live config in a separate repo from the module?* The module is reusable and public; the live config holds real values, state and credentials, and it has a different release rhythm.
- *Why pin a module version?* So upgrades are deliberate and reviewable, and rollback is one line.
- *What happens if two folders share a state key?* Each plan sees the other's resources as unmanaged and proposes destroying them.
- *What does a major version bump tell a user?* Their config must change before they can upgrade.

## Step 7 — Testing the module with `terraform test`

**What we did:** Added three test files in `modules/business-domain/tests/`: mail presets (provider by provider, SPF, DKIM), records (DMARC, `extra_records`, zone settings, the redirect, the `record_names` output) and validation (one bad input per validated variable). 21 tests in all. They run in CI.

**The idea, in my words:**
- The module is a shared recipe, and my live domain calls it from a private repo. A test runs against the recipe alone, with a fake provider, so it can't touch a real domain. Separately, the live domain pins a version tag, so a change to the module can't reach it until I bump the tag on purpose.
- At plan time Terraform knows what I wrote in config (counts, names, contents) but not what the API assigns (record IDs). So tests assert on things the module decides. The number of MX records comes from `email_provider`, not from Cloudflare.
- A `validation` block protects the infrastructure from bad input. An `expect_failures` test protects the validation: if someone weakens a check, the test fails.
- One run, one bad value, everything else valid, so a pass can only mean that one check fired.
- A test of mine failed for a real reason: `sort()` returns a list, my expected value was a tuple, and `==` treats them as different. The fix was `tolist()`. A failing test is either a wrong test or a wrong module, and it takes reading to tell which.

**Questions an interviewer might ask:**
- *How do you test Terraform without touching real infrastructure?* `mock_provider` with `command = plan`: nothing is created and no API is called.
- *What can't a plan-time test check?* Anything the API fills in, like IDs. Those are "known after apply".
- *What does `expect_failures` do, and why have it?* It asserts a validation rejects a bad value, so a weakened check gets caught.
- *Why did you run the tests in CI, and why is it safe?* They need no secrets and no state, so anyone's pull request can run them.
- *Why is `none` your most important preset test?* Choosing it must create no MX records. Wrongly deleting them would stop a domain's email.

## Step 8 — `terraform plan` in CI, safely

**What we did:** Added a workflow to the private repo that uses the module (not this public one, which has no real zone, state or token). On every pull request it runs `terraform plan` against the real state and shows the result on the run page. It uses a new read-only Cloudflare token and an R2 key with Object Read only on the state bucket. It never applies. First run: "No changes", in 15 seconds.

**The idea, in my words:**
- My laptop key can change things, and I use it on purpose. A key in CI runs automatically with nobody watching, so it gets read-only access: least privilege, so a leak or a mistake can't change anything.
- Nothing changes my domain when the module repo is updated. The two repos are connected only by the `?ref=` version line. CI in the private repo runs when I open a pull request there.
- If someone edited the workflow to run `apply`, the read-only credentials would reject the writes. What a job can do is limited by its credentials, not by what the workflow file says. A malicious workflow could still read the secrets, so a review rule before merging is a good second guard.
- Secrets are available to a job but unreadable afterwards, even to me. They can only be replaced.
- Cloudflare has two kinds of token. The DNS token comes from My Profile, API Tokens and shows one value. An R2 token (storage, for state) comes from R2, Manage API Tokens and shows three: a token value plus an Access Key ID and Secret. I first made the wrong kind, and the three values were the clue.
- For clients: they own the account, and I get invited as a member with a limited role and make my own tokens, so they can remove me in one click and never handle a secret. One token per client, limited to that zone.

**Questions an interviewer might ask:**
- *Why does CI use a different credential from your laptop?* Least privilege: CI runs unattended, so it can only read.
- *Why `plan -lock=false` in CI?* The read-only key can't write the lock file, and a plan changes nothing.
- *Why `pull_request` and not `pull_request_target`?* The second gives secrets to code from forks.
- *Why pass secrets through `env:` instead of into the script?* A secret's content then can't be interpreted as a shell command.
- *What stops a modified workflow from applying changes?* The credentials are read-only, so the API refuses.
- *How would you give a client's CI the same setup?* Each client has its own repo, token limited to their zone, and their own secrets.

**A limit I ran into:** GitHub enforces branch rules (require a pull request before merging) on private repos only on paid plans. On the free plan the rule saves but does nothing, so I deleted it rather than keep a false sense of safety. What protects the live domain is the credentials: CI's are read-only, and the read/write key never leaves my laptop. Two-factor on the GitHub account covers the remaining risk. *Interview line:* controls that depend on settings you can't enforce are weaker than limits built into the credentials.

## Step 9 — `MX` and `CAA` in `extra_records` (v0.2.0)

**What we did:** Let `extra_records` accept two more record types. MX got an optional `priority` field and a validation that requires it. CAA got an optional `tag` field (`issue`, `issuewild` or `iodef`) and a validation for it. For CAA the module builds the `data` block (`flags`, `tag`, `value`) and leaves `content` unset. We wrote the tests first each time and watched them fail before writing the code.

**The idea, in my words:**
- Tests came first so every check was proven to catch something before the code existed.
- CAA is sent to Cloudflare as structured data, not a content string, so it is handled differently from TXT, CNAME and MX.
- `optional` means a value may or may not be given. `computed` means the provider fills the value in when it isn't given. Setting `content = null` for CAA says "I'm not setting this", and the provider fills it in from `data`.

**Corrections and things worth remembering:**
- **A false green:** the two validation tests passed before the code existed, but only because MX and CAA were still blocked by the type check. A test that passes can pass for the wrong reason. Break the rule on purpose and watch the test fail to know it guards something.
- Terraform silently drops object attributes the type doesn't declare, so `priority = 10` did nothing until the field was declared.
- Terraform stops a test file at the first failing run and skips the rest, so one failure can hide others.
- The tests use a mock provider: they prove the module builds the right data, not that Cloudflare accepts it. The first real CAA record is the live check.
- Writing `r.type != "MX" || r.priority != null` makes a rule apply to one type only. Without the first half, every TXT and CNAME would fail.

**Questions an interviewer might ask:**
- *Why write the test before the code?* To see it fail for the right reason; a test you've never seen fail may not test anything.
- *A test passes the first time you run it. What do you check?* That it isn't passing for a different reason, by breaking the rule on purpose.
- *What do `optional` and `computed` mean on a provider attribute?* Optional: you may set it. Computed: the provider sets it when you don't. Both together mean "set it or let the provider decide".
- *Why does CAA need a `data` block when MX uses `content`?* The provider models CAA's parts (flags, tag, value) as structured data; MX is a hostname plus a separate priority.
- *Why a minor version (v0.2.0) and not a patch?* New inputs are a feature; existing callers are unaffected, so it isn't a breaking change.
