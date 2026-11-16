variable "zone_id" {
  description = "Cloudflare zone ID of the domain (dashboard: domain Overview, right-hand column)."
  type        = string

  # Zone IDs are 32 hex characters; catching a typo here beats a confusing API error later.
  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be 32 lowercase hex characters."
  }
}
