#!/usr/bin/env bash
# Runs terraform inside one domain's folder, with credentials loaded from git-ignored .env files
# so a token never sits in shell history or the code.
#
# Usage: ./tf [--dir PATH] <folder> <terraform command...>
#   ./tf example init -backend-config=backend.hcl     the fictional example in examples/basic
#   ./tf acme-shop plan                               a folder made by ./new-domain, in domains/
#   ./tf --dir ~/my-dns acme-shop plan                a folder in your own private repo
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
usage="Usage: ./tf [--dir PATH] <folder> <terraform command...>   e.g. ./tf example plan"

base="$root/domains"
if [ "${1:-}" = "--dir" ]; then
  base="${2:?--dir needs a path}"
  shift 2
fi

name="${1:?$usage}"
shift

# "example" is the fictional domain that ships with the repo. Its state key is example/..., so it
# follows the same folder-name-equals-key rule as every other folder.
if [ "$name" = "example" ] && [ "$base" = "$root/domains" ]; then
  dir="$root/examples/basic"
else
  dir="$base/$name"
fi

if [ ! -d "$dir" ]; then
  echo "No folder at $dir" >&2
  exit 1
fi

# Each domain needs its own state file. A copied folder that still points at another domain's
# key would plan to destroy that domain's records, so refuse to run instead.
if ! grep -q "key *= *\"$name/terraform.tfstate\"" "$dir/backend.tf"; then
  echo "backend.tf in $dir must set key = \"$name/terraform.tfstate\". Fix it before running Terraform." >&2
  exit 1
fi

set -a
# Shared values first (the R2 state keys), then the folder's own .env, which can override them.
# That lets each domain carry a Cloudflare token limited to its own zone.
if [ -f "$root/.env" ]; then
  # shellcheck source=/dev/null
  source "$root/.env"
fi
if [ -f "$dir/.env" ]; then
  # shellcheck source=/dev/null
  source "$dir/.env"
fi
set +a

cd "$dir"
exec terraform "$@"
