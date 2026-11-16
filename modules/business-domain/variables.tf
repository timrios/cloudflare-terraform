variable "zone_id" {
  description = "Cloudflare zone ID of the domain (dashboard: domain Overview, right-hand column)."
  type        = string

  # Zone IDs are 32 hex characters; catching a typo here beats a confusing API error later.
  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be 32 lowercase hex characters."
  }
}

variable "domain" {
  description = "The domain this module manages, e.g. example.com. Used to build every record name."
  type        = string

  # Lowercase labels separated by dots; stops a stray https:// or trailing dot reaching the API.
  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain))
    error_message = "domain must look like example.com: lowercase, no https://, no trailing dot."
  }
}

variable "email_provider" {
  description = "Who handles this domain's email: icloud, google, microsoft, or none. Sets the MX and SPF records."
  type        = string

  # No default on purpose: a forgotten value must be an error, not a silent switch to "none"
  # that would delete the MX records and stop the domain's email.
  validation {
    condition     = contains(["none", "icloud", "google", "microsoft"], var.email_provider)
    error_message = "email_provider must be one of: none, icloud, google, microsoft."
  }
}

variable "dkim_records" {
  description = "DKIM records from the mail provider, keyed by host part (e.g. \"sig1._domainkey\"). Each domain gets its own key."
  type = map(object({
    type    = string
    content = string
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.dkim_records : contains(["CNAME", "TXT"], r.type)])
    error_message = "Each DKIM record's type must be CNAME or TXT."
  }
}

variable "extra_records" {
  description = "Any other TXT, CNAME, MX or CAA records this domain needs (verification proofs, a mail-sending service, which certificate authorities may issue), keyed by a label you choose. name is the host part: \"send.mail\" or \"@\" for the bare domain. MX records also need a priority (lower is tried first). CAA records need a tag (issue, issuewild or iodef), with the authority or address as content."
  type = map(object({
    name     = string
    type     = string
    content  = string
    ttl      = optional(number, 3600)
    priority = optional(number)
    tag      = optional(string)
  }))
  default = {}

  # Keyed by label, not name, because several records can share a name (e.g. three TXT proofs at "@").
  validation {
    condition     = alltrue([for r in var.extra_records : contains(["CNAME", "TXT", "MX", "CAA"], r.type)])
    error_message = "Each extra record's type must be CNAME, TXT, MX or CAA."
  }

  # A CAA tag says what the record controls: issue (who may issue certificates), issuewild
  # (the same for wildcard certificates) or iodef (where to report violations). A typo would
  # only fail at apply time. The ternary keeps contains() from receiving null when tag is unset.
  validation {
    condition     = alltrue([for r in var.extra_records : r.type != "CAA" || contains(["issue", "issuewild", "iodef"], r.tag == null ? "" : r.tag)])
    error_message = "Each CAA extra record needs a tag of issue, issuewild or iodef."
  }

  # Cloudflare rejects an MX record without a priority, but only at apply time; catching it here is faster.
  validation {
    condition     = alltrue([for r in var.extra_records : r.type != "MX" || r.priority != null])
    error_message = "Each MX extra record needs a priority, e.g. priority = 10."
  }
}

variable "dmarc_policy" {
  description = "What receivers do with mail that fails SPF and DKIM: none (only report), quarantine (send to spam) or reject (bounce)."
  type        = string

  # Defaulting to none is safe: it never affects delivery. Tightening to quarantine or reject
  # should be a deliberate choice once the reports show legitimate mail passing.
  default = "none"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy must be one of: none, quarantine, reject."
  }
}

variable "dmarc_report_email" {
  description = "Address that receives DMARC reports, e.g. hello@example.com."
  type        = string

  # Deliberately loose: it only has to look like an address; the mail provider does the real check.
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.dmarc_report_email))
    error_message = "dmarc_report_email must look like an email address, e.g. hello@example.com."
  }
}

variable "min_tls_version" {
  description = "Oldest TLS version visitors may use to connect. 1.2 is the safe default; 1.0 and 1.1 are obsolete."
  type        = string
  default     = "1.2"

  # The API takes these exact strings; anything else would fail at apply time.
  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.min_tls_version)
    error_message = "min_tls_version must be one of: 1.0, 1.1, 1.2, 1.3."
  }
}
