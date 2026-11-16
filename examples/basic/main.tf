# A fictional small business, used to show every input of the module. Nothing here is a
# real domain, so it can never touch anything; CI only validates it.
module "my_business" {
  source  = "../../modules/business-domain"
  zone_id = var.zone_id
  domain  = "example.com"

  email_provider = "icloud"

  dmarc_policy       = "quarantine"
  dmarc_report_email = "hello@example.com"

  # Each domain gets its own DKIM key from its mail provider.
  dkim_records = {
    "sig1._domainkey" = {
      type    = "CNAME"
      content = "sig1.dkim.example.com.at.icloudmailadmin.com"
    }
  }

  # Anything particular to this domain goes here, not in the module. Keyed by a label you
  # choose, because several records can share a name (here, two TXT proofs at "@").
  extra_records = {
    mail_service_cname = {
      name    = "send.mail"
      type    = "CNAME"
      content = "send.mail-service.example.net"
    }
    ownership_proof_one = {
      name    = "@"
      type    = "TXT"
      content = "\"site-verification=replace-with-your-token\""
    }
    ownership_proof_two = {
      name    = "@"
      type    = "TXT"
      content = "\"other-service=replace-with-your-token\""
    }
  }
}

output "record_names" {
  description = "Record names the module manages, passed up from the module."
  value       = module.my_business.record_names
}
