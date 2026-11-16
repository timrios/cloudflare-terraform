# A zone can have only one ruleset per phase, so this single resource holds all of the
# zone's redirect rules; add more rules to the list rather than creating a second ruleset.
resource "cloudflare_ruleset" "redirects" {
  zone_id     = var.zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    action      = "redirect"
    description = "www to apex"
    # Matches https://www.<anything>, so the rule needs no domain name and works for any client.
    expression = "(http.request.full_uri wildcard r\"https://www.*\")"
    enabled    = true

    action_parameters = {
      from_value = {
        status_code           = 301
        preserve_query_string = true
        target_url = {
          # ${1} is whatever the * matched, so www.example.com/about becomes example.com/about.
          # The doubled $$ stops Terraform reading ${1} as its own interpolation.
          expression = "wildcard_replace(http.request.full_uri, r\"https://www.*\", r\"https://$${1}\")"
        }
      }
    }
  }]
}
