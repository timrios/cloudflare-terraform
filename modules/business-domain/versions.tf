terraform {
  required_version = ">= 1.17"

  required_providers {
    cloudflare = {
      # Without this, Terraform guesses "hashicorp/cloudflare", which doesn't exist.
      source = "cloudflare/cloudflare"
      # A module states a compatible range; the root module's lock file picks the exact version.
      version = ">= 5.29, < 6.0"
    }
  }
}
