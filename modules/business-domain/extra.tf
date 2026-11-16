# Records that belong to one particular domain rather than to every domain: verification
# proofs, a mail-sending service's CNAMEs. The caller supplies them, so the module itself
# contains nothing specific to any business.
resource "cloudflare_dns_record" "extra" {
  for_each = var.extra_records

  zone_id = var.zone_id
  # "@" is DNS shorthand for the bare domain; anything else is a prefix of it.
  name = each.value.name == "@" ? var.domain : "${each.value.name}.${var.domain}"
  type = each.value.type
  # CAA is sent as structured data instead of a content string, so content is left unset for it.
  content = each.value.type == "CAA" ? null : each.value.content
  data    = each.value.type == "CAA" ? { flags = 0, tag = each.value.tag, value = each.value.content } : null
  # Null for TXT and CNAME, which the provider ignores; only MX uses it.
  priority = each.value.priority
  ttl      = each.value.ttl
  proxied  = false
}

# These six records used to be single resources in this module; they now come from the
# caller's extra_records. moved keeps the same real records instead of recreating them.
moved {
  from = cloudflare_dns_record.resend_send_cname
  to   = cloudflare_dns_record.extra["resend_send_cname"]
}

moved {
  from = cloudflare_dns_record.resend_rsend_cname
  to   = cloudflare_dns_record.extra["resend_rsend_cname"]
}

moved {
  from = cloudflare_dns_record.resend_dkim_txt
  to   = cloudflare_dns_record.extra["resend_dkim_txt"]
}

moved {
  from = cloudflare_dns_record.google_verification_txt
  to   = cloudflare_dns_record.extra["google_verification_txt"]
}

moved {
  from = cloudflare_dns_record.apple_verification_1_txt
  to   = cloudflare_dns_record.extra["apple_verification_1_txt"]
}

moved {
  from = cloudflare_dns_record.apple_verification_2_txt
  to   = cloudflare_dns_record.extra["apple_verification_2_txt"]
}
