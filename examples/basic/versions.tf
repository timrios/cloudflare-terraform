terraform {
  # "~> 1.17" allows 1.17 and newer 1.x releases, but not 2.0. Pinning stops a
  # teammate's (or CI's) different Terraform version from changing the plan.
  required_version = "~> 1.17"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # v5 renamed many resources compared with v4, so we stay on 5.x on purpose.
      version = "~> 5.29"
    }
  }
}
