# A fake Cloudflare provider: tests never contact the real API, so they need no token
# and can't touch a live domain.
mock_provider "cloudflare" {}

# Inputs shared by every run block below. A run block can override any of them.
variables {
  zone_id            = "00000000000000000000000000000000"
  domain             = "example.com"
  email_provider     = "google"
  dmarc_report_email = "hello@example.com"
}

# command = plan: work out what would be created, without creating it.
run "google_has_five_mx_records" {
  command = plan

  assert {
    condition     = length(cloudflare_dns_record.mx) == 5
    error_message = "Google Workspace needs 5 MX records."
  }

  assert {
    condition     = cloudflare_dns_record.mx["aspmx.l.google.com"].priority == 1
    error_message = "Google's primary MX server must have priority 1."
  }

  assert {
    condition     = cloudflare_dns_record.spf[0].content == "\"v=spf1 include:_spf.google.com ~all\""
    error_message = "SPF should authorise Google, with the quotes Cloudflare stores."
  }
}

run "icloud_has_two_mx_records" {
  command = plan

  variables {
    email_provider = "icloud"
  }

  assert {
    condition     = length(cloudflare_dns_record.mx) == 2
    error_message = "iCloud needs 2 MX records."
  }

  assert {
    condition     = length(cloudflare_dns_record.spf) == 1
    error_message = "iCloud needs one SPF record."
  }
}

# Microsoft's MX host is built from the domain, so this checks the replace() in email.tf.
run "microsoft_mx_host_comes_from_the_domain" {
  command = plan

  variables {
    email_provider = "microsoft"
  }

  assert {
    condition     = contains(keys(cloudflare_dns_record.mx), "example-com.mail.protection.outlook.com")
    error_message = "Microsoft's MX host should be the domain with dots turned into dashes."
  }
}

# The dangerous one: "none" must create no mail records at all.
run "none_creates_no_mail_records" {
  command = plan

  variables {
    email_provider = "none"
  }

  assert {
    condition     = length(cloudflare_dns_record.mx) == 0 && length(cloudflare_dns_record.spf) == 0
    error_message = "email_provider = none must create no MX and no SPF records."
  }
}

run "dkim_records_are_named_from_their_key" {
  command = plan

  variables {
    dkim_records = {
      "sig1._domainkey" = { type = "CNAME", content = "sig1.dkim.example.net" }
    }
  }

  assert {
    condition     = cloudflare_dns_record.dkim["sig1._domainkey"].name == "sig1._domainkey.example.com"
    error_message = "A DKIM record's name should be its key plus the domain."
  }
}
