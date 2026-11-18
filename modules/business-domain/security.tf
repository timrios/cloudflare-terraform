# Cloudflare creates every zone setting itself, so this resource doesn't create anything:
# it takes over an existing setting and keeps it at the value written here.
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = var.zone_id
  setting_id = "min_tls_version"
  value      = var.min_tls_version
}

# Always Use HTTPS redirects a plain-http request, but that first request can be intercepted.
# HSTS makes the browser switch to https itself, before anything leaves the device.
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = var.zone_id
  setting_id = "security_header"
  # The variable's field names match the API's, so it passes through whole.
  value = {
    strict_transport_security = var.hsts
  }
}
