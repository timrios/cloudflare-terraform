# Cloudflare Terraform — instructions for Claude

The owner's own project: a reusable Terraform module that sets up a small business's domain on Cloudflare (DNS, email records, redirects, security settings). It will become a **public** GitHub repo shown to employers, so it has two goals:

1. A clean, working, well-documented infrastructure-as-code project.
2. **The owner learning Terraform well enough to explain every part of it in an interview.** This goal matters as much as the first.

## This is a teaching project

Work at a teaching pace, not a building pace:

- **Explain before writing.** Before each step, say in plain language what we're about to do, why, and which Terraform idea it uses. Then write the code.
- **Small pieces.** Add one resource or idea at a time and run `terraform plan` after each, so the owner sees cause and effect. Don't write a whole module in one go.
- **The owner runs the commands that matter.** For `init`, `plan`, `apply` and `import`, give the owner the command to run themselves with `!` and read the output together, rather than running it silently.
- **Check understanding.** At the end of each step, ask the owner to explain it back in a sentence or two, or ask one short interview-style question ("What would happen if you deleted the state file?"). Correct gently and fill gaps.
- **Record it.** When a step is finished, add the owner's own summary (their words, lightly tidied) and any interview questions to `LEARNING.md`.
- Use plain language, and define each new term the first time it comes up.
- Don't move on until the current step's ideas are understood, even if the code already works.

## Safety

- **Nothing personal or client-related goes in this repo.** It is public, so no real domain, account ID, zone ID, bucket name or token goes in it. The example uses `example.com`. Real domains, the owner's own included, use the module from a separate private repo, never from here.
- The Cloudflare API token lives only in a git-ignored file (`.env` or `terraform.tfvars`). Never paste it into the chat, a file that is tracked, or a command line that ends up in shell history.
- State files (`*.tfstate`) can hold sensitive values. They're git-ignored and are never committed.
- Real domains managed with this module are live, including their email. In a repo that applies it, never run `apply` unless `plan` shows only the changes we intended. Any plan that **destroys** or **replaces** a record means stop and explain first.

## Conventions

- Run `terraform fmt -recursive` and `terraform validate` before calling a change done, plus `tflint`.
- Pin the Terraform version and the Cloudflare provider version (`required_version`, `required_providers`). Check the provider's current major version and its docs before writing resources, since resource names changed between major versions.
- Variables get a `description` and, where it helps, a `validation` block with a clear error message.
- Comments explain **why**, not what.
- Tasks and "Pick up here" live in `README.md` → Status.
