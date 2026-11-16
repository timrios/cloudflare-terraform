mock_provider "cloudflare" {}

variables {
  zone_id            = "00000000000000000000000000000000"
  domain             = "example.com"
  email_provider     = "none"
  dmarc_report_email = "hello@example.com"
}

# The default must be the safe one: none only reports and never affects delivery.
run "dmarc_defaults_to_report_only" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.dmarc_txt.content == "\"v=DMARC1; p=none; rua=mailto:hello@example.com\""
    error_message = "DMARC should default to p=none and send reports to the given address."
  }
}

run "dmarc_policy_is_used" {
  command = plan

  variables {
    dmarc_policy = "reject"
  }

  assert {
    condition     = strcontains(cloudflare_dns_record.dmarc_txt.content, "p=reject")
    error_message = "dmarc_policy = reject should appear in the record."
  }
}

# "@" is DNS shorthand for the bare domain; anything else is a prefix of it.
run "extra_records_build_their_names" {
  command = plan

  variables {
    extra_records = {
      proof_one = { name = "@", type = "TXT", content = "proof-1" }
      proof_two = { name = "@", type = "TXT", content = "proof-2" }
      mailer    = { name = "send.mail", type = "CNAME", content = "mailer.example.net", ttl = 300 }
    }
  }

  assert {
    condition     = cloudflare_dns_record.extra["proof_one"].name == "example.com"
    error_message = "name = @ should become the bare domain."
  }

  assert {
    condition     = cloudflare_dns_record.extra["mailer"].name == "send.mail.example.com"
    error_message = "A host part should have the domain added."
  }

  assert {
    condition     = cloudflare_dns_record.extra["proof_one"].ttl == 3600 && cloudflare_dns_record.extra["mailer"].ttl == 300
    error_message = "ttl should default to 3600 and accept an override."
  }

  # Two records sharing a name is the reason extra_records is keyed by label.
  assert {
    condition     = length(cloudflare_dns_record.extra) == 3
    error_message = "Records that share a name must still each be created."
  }
}

# MX is the first type that needs more than name/content: the priority decides which server is tried first.
run "extra_mx_record_carries_its_priority" {
  command = plan

  variables {
    extra_records = {
      mail = { name = "@", type = "MX", content = "mail.example.net", priority = 10 }
    }
  }

  assert {
    condition     = cloudflare_dns_record.extra["mail"].type == "MX" && cloudflare_dns_record.extra["mail"].priority == 10
    error_message = "An MX extra record should keep its type and priority."
  }
}

# CAA is sent to Cloudflare as structured data, not as a content string, so the module has to build it.
run "extra_caa_record_is_built_as_data" {
  command = plan

  variables {
    extra_records = {
      caa = { name = "@", type = "CAA", content = "letsencrypt.org", tag = "issue" }
    }
  }

  assert {
    condition     = cloudflare_dns_record.extra["caa"].data.tag == "issue" && cloudflare_dns_record.extra["caa"].data.value == "letsencrypt.org"
    error_message = "A CAA record should send its tag and value as data."
  }

  assert {
    condition     = cloudflare_dns_record.extra["caa"].data.flags == 0
    error_message = "CAA flags should be 0, the normal value."
  }
}

run "security_settings_follow_the_inputs" {
  command = plan

  variables {
    min_tls_version = "1.3"
  }

  assert {
    condition     = cloudflare_zone_setting.min_tls_version.value == "1.3"
    error_message = "min_tls_version should be passed through to the zone setting."
  }

  assert {
    condition     = cloudflare_zone_setting.always_use_https.value == "on"
    error_message = "Always Use HTTPS must always be on."
  }
}

# The redirect rule is written without the domain, so it works for any client.
run "redirect_is_a_permanent_www_to_apex" {
  command = plan

  assert {
    condition     = cloudflare_ruleset.redirects.rules[0].action_parameters.from_value.status_code == 301
    error_message = "The www redirect must be permanent (301)."
  }
}

# outputs.tf de-duplicates names: with no email, the apex AAAA and DMARC give three names.
run "record_names_are_sorted_and_unique" {
  command = plan

  assert {
    # tolist(): sort() returns a list but a written-out [...] is a tuple, and == treats those as different.
    condition     = output.record_names == tolist(["_dmarc.example.com", "example.com", "www.example.com"])
    error_message = "record_names should list each name once, sorted."
  }
}
