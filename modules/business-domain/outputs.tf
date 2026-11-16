# Every record in one list, so outputs can loop over them instead of naming each one.
locals {
  records = concat(
    # for_each and count resources are collections, so they're flattened into plain lists first.
    values(cloudflare_dns_record.mx),
    cloudflare_dns_record.spf,
    values(cloudflare_dns_record.dkim),
    values(cloudflare_dns_record.extra),
    [
      cloudflare_dns_record.www_aaaa,
      cloudflare_dns_record.apex_aaaa,
      cloudflare_dns_record.dmarc_txt,
    ],
  )
}

output "domain" {
  description = "The domain this module manages."
  value       = var.domain
}

# The for expression builds a new list by taking .name from each record. Several records share a
# name (four TXT and two MX at the apex), so distinct() removes repeats and sort() keeps the
# order stable, which stops outputs from showing as changed for no reason.
output "record_names" {
  description = "Sorted, de-duplicated names of the DNS records this module manages."
  value       = sort(distinct([for r in local.records : r.name]))
}
