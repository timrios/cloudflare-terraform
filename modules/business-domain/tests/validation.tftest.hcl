# Each run breaks exactly one input and expects exactly that variable's validation to
# reject it. If a validation is ever weakened or deleted, its run stops failing and the
# test fails, so these guard the checks themselves.
mock_provider "cloudflare" {}

variables {
  zone_id            = "00000000000000000000000000000000"
  domain             = "example.com"
  email_provider     = "none"
  dmarc_report_email = "hello@example.com"
}

run "zone_id_must_be_32_hex_characters" {
  command = plan
  variables {
    zone_id = "not-a-zone-id"
  }
  expect_failures = [var.zone_id]
}

run "zone_id_rejects_uppercase" {
  command = plan
  variables {
    zone_id = "ABCDEF00000000000000000000000000"
  }
  expect_failures = [var.zone_id]
}

run "domain_rejects_a_url" {
  command = plan
  variables {
    domain = "https://example.com"
  }
  expect_failures = [var.domain]
}

run "domain_rejects_a_trailing_dot" {
  command = plan
  variables {
    domain = "example.com."
  }
  expect_failures = [var.domain]
}

run "email_provider_rejects_unknown_names" {
  command = plan
  variables {
    email_provider = "yahoo"
  }
  expect_failures = [var.email_provider]
}

run "dmarc_policy_rejects_unknown_values" {
  command = plan
  variables {
    dmarc_policy = "block"
  }
  expect_failures = [var.dmarc_policy]
}

run "dmarc_report_email_must_look_like_an_address" {
  command = plan
  variables {
    dmarc_report_email = "hello-at-example.com"
  }
  expect_failures = [var.dmarc_report_email]
}

run "min_tls_version_rejects_unknown_versions" {
  command = plan
  variables {
    min_tls_version = "2.0"
  }
  expect_failures = [var.min_tls_version]
}

run "dkim_records_reject_other_types" {
  command = plan
  variables {
    dkim_records = {
      "sig1._domainkey" = { type = "A", content = "1.2.3.4" }
    }
  }
  expect_failures = [var.dkim_records]
}

run "extra_records_reject_other_types" {
  command = plan
  variables {
    extra_records = {
      bad = { name = "@", type = "MX", content = "mail.example.net" }
    }
  }
  expect_failures = [var.extra_records]
}
