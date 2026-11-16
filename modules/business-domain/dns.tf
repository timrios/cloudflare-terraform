# Placeholder address: the real site is served by Cloudflare's proxy, so visitors
# never reach 100::. It exists because a proxied record needs some address.
resource "cloudflare_dns_record" "www_aaaa" {
  zone_id = var.zone_id
  name    = "www.${var.domain}"
  type    = "AAAA"
  content = "100::"
  ttl     = 1 # 1 = "automatic"; the API requires it for proxied records
  proxied = true
}

resource "cloudflare_dns_record" "apex_aaaa" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "AAAA"
  content = "100::"
  ttl     = 1
  proxied = true
}

# DMARC: what receivers should do with mail that fails SPF/DKIM. none only reports,
# quarantine sends it to spam, reject bounces it. Reports go to the rua address.
resource "cloudflare_dns_record" "dmarc_txt" {
  zone_id = var.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  content = "\"v=DMARC1; p=${var.dmarc_policy}; rua=mailto:${var.dmarc_report_email}\""
  ttl     = 1
  proxied = false
}
