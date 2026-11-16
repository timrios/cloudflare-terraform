#!/usr/bin/env bash
# Runs terraform inside examples/basic with the Cloudflare token loaded from
# the git-ignored .env, so the token never sits in shell history or the code.
# Usage: ./tf plan   (anything you'd pass to terraform)
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
set -a
source "$root/.env"
set +a
cd "$root/examples/basic"
exec terraform "$@"
