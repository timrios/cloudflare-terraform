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
