locals {
  # One entry per supported mail provider: where mail is delivered (MX) and who may send
  # as the domain (SPF). Adding a provider means adding an entry here and its name to the
  # validation list in variables.tf.
  email_presets = {
    none = {
      mx  = []
      spf = null
    }
    icloud = {
      mx = [
        { host = "mx01.mail.icloud.com", priority = 10 },
        { host = "mx02.mail.icloud.com", priority = 10 },
      ]
      spf = "v=spf1 include:icloud.com ~all"
    }
    google = {
      mx = [
        { host = "aspmx.l.google.com", priority = 1 },
        { host = "alt1.aspmx.l.google.com", priority = 5 },
        { host = "alt2.aspmx.l.google.com", priority = 5 },
        { host = "alt3.aspmx.l.google.com", priority = 10 },
        { host = "alt4.aspmx.l.google.com", priority = 10 },
      ]
      spf = "v=spf1 include:_spf.google.com ~all"
    }
    microsoft = {
      # Microsoft's MX host is the domain with dots turned into dashes.
      mx = [
        { host = "${replace(var.domain, ".", "-")}.mail.protection.outlook.com", priority = 0 },
      ]
      spf = "v=spf1 include:spf.protection.outlook.com ~all"
    }
  }

  preset = local.email_presets[var.email_provider]
}

# for_each makes one record per mail server, keyed by hostname so the address stays
# the same if the list is reordered (a numbered list would shift every record).
resource "cloudflare_dns_record" "mx" {
  for_each = { for m in local.preset.mx : m.host => m }

  zone_id  = var.zone_id
  name     = var.domain
  type     = "MX"
  content  = each.value.host
  priority = each.value.priority
  ttl      = 3600
  proxied  = false
}

# SPF: which servers may send mail as this domain. count makes 0 or 1 record: "none" has
# no SPF text, so nothing is created. The quotes are part of the value Cloudflare stores.
resource "cloudflare_dns_record" "spf" {
  count = local.preset.spf == null ? 0 : 1

  zone_id = var.zone_id
  name    = var.domain
  type    = "TXT"
  content = "\"${local.preset.spf}\""
  ttl     = 3600
  proxied = false
}

# DKIM: the provider signs outgoing mail and receivers look the key up here. Each domain
# gets its own key, so the caller supplies it. The map key is the host part, e.g. "sig1._domainkey".
resource "cloudflare_dns_record" "dkim" {
  for_each = var.dkim_records

  zone_id = var.zone_id
  name    = "${each.key}.${var.domain}"
  type    = each.value.type
  content = each.value.content
  ttl     = 3600
  proxied = false
}

# These records used to be single resources; moved tells Terraform it's the same
# real record under a new address, so nothing is destroyed and recreated.
moved {
  from = cloudflare_dns_record.icloud_mx1
  to   = cloudflare_dns_record.mx["mx01.mail.icloud.com"]
}

moved {
  from = cloudflare_dns_record.icloud_mx2
  to   = cloudflare_dns_record.mx["mx02.mail.icloud.com"]
}

moved {
  from = cloudflare_dns_record.spf_txt
  to   = cloudflare_dns_record.spf[0]
}

moved {
  from = cloudflare_dns_record.icloud_dkim_cname
  to   = cloudflare_dns_record.dkim["sig1._domainkey"]
}
