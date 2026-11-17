#!/usr/bin/env bash
# Tests for the helper scripts (new-domain, tf). No Cloudflare token and no network calls to the
# API: it only creates folders, runs terraform validate offline, and checks what the scripts refuse.
# Usage: tests/scripts.sh        (run from anywhere; CI runs it on every push)
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
failures=0

# Remove only what this script made. domains/ci-test exists only while the validate test runs.
cleanup() {
  rm -r "${work:?}"
  rm -rf "${root:?}/domains/ci-test"
}
trap cleanup EXIT

pass() { echo "ok   - $1"; }
fail() {
  echo "FAIL - $1"
  failures=$((failures + 1))
}

# check "<what>" <command...>: the command must exit zero.
check() {
  local what="$1"
  shift
  if "$@" > /dev/null 2>&1; then pass "$what"; else fail "$what"; fi
}

# expect_refusal "<what>" <command...>: the command must exit non-zero.
expect_refusal() {
  local what="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    fail "$what (should have been refused)"
  else
    pass "$what"
  fi
}

mod="git::https://example.com/x.git//modules/business-domain?ref=v0.0.0"

# --- new-domain: a good run. ---
if "$root/new-domain" --dir "$work" --module-source "$mod" acme-shop acme.com google > /dev/null 2>&1; then
  pass "new-domain creates a folder"
else
  fail "new-domain creates a folder"
fi

d="$work/acme-shop"
check "state key is the folder name" grep -q 'key *= *"acme-shop/terraform.tfstate"' "$d/backend.tf"
check "main.tf has the domain" grep -q 'domain  = "acme.com"' "$d/main.tf"
check "main.tf has the email provider" grep -q 'email_provider = "google"' "$d/main.tf"
check "main.tf uses --module-source" grep -qF "$mod" "$d/main.tf"
# These hold a domain's zone ID and token; copying them is how one domain's data leaks into another.
if [ -e "$d/terraform.tfvars" ] || [ -e "$d/.env" ]; then
  fail "no terraform.tfvars or .env copied"
else
  pass "no terraform.tfvars or .env copied"
fi

# --- new-domain: refusals, and each must leave nothing behind. ---
expect_refusal "bad folder name" "$root/new-domain" --dir "$work" --module-source "$mod" Bad_Name acme.com none
expect_refusal "bad domain" "$root/new-domain" --dir "$work" --module-source "$mod" shop2 notadomain none
expect_refusal "unknown email provider" "$root/new-domain" --dir "$work" --module-source "$mod" shop3 acme.com gmail
expect_refusal "existing folder is never overwritten" "$root/new-domain" --dir "$work" --module-source "$mod" acme-shop acme.com none
expect_refusal "--dir without --module-source" "$root/new-domain" --dir "$work" shop4 acme.com none
expect_refusal "--dir that doesn't exist" "$root/new-domain" --dir "$work/nope" --module-source "$mod" shop5 acme.com none
expect_refusal "unknown option" "$root/new-domain" --bogus a b c
for n in Bad_Name shop2 shop3 shop4 shop5; do
  if [ -e "$work/$n" ]; then fail "a refused run left $n behind"; fi
done
if [ -e "$work/nope" ]; then fail "a refused run created the missing --dir"; else pass "refused runs leave nothing behind"; fi

# --- tf: refuses when the folder name and the state key disagree. ---
sed "s|acme-shop/terraform.tfstate|other/terraform.tfstate|" "$d/backend.tf" > "$d/backend.tf.new" && mv "$d/backend.tf.new" "$d/backend.tf"
expect_refusal "tf refuses a mismatched state key" "$root/tf" --dir "$work" acme-shop version
expect_refusal "tf refuses a missing folder" "$root/tf" --dir "$work" nope version

# --- The generated config is valid Terraform (this caught a missing required input once). ---
if command -v terraform > /dev/null; then
  if "$root/new-domain" ci-test ci-test.example.com none > /dev/null 2>&1 &&
    (cd "$root/domains/ci-test" && terraform init -backend=false -input=false > /dev/null 2>&1 && terraform validate > /dev/null 2>&1); then
    pass "generated config passes terraform validate"
  else
    fail "generated config passes terraform validate"
  fi
else
  echo "skip - terraform not installed, validate test skipped"
fi

# --- The second net behind .gitignore: nothing but the README may be tracked in domains/. ---
if git -C "$root" rev-parse --git-dir > /dev/null 2>&1; then
  tracked="$(git -C "$root" ls-files domains | grep -v '^domains/README.md$' || true)"
  if [ -n "$tracked" ]; then
    fail "files under domains/ are tracked by git: $tracked"
  else
    pass "nothing but the README is tracked under domains/"
  fi
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "All passed."
else
  echo "$failures failed."
  exit 1
fi
