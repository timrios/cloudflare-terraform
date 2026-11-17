terraform {
  # Partial configuration: a backend block can't read variables, so the parts that differ
  # per person are supplied from outside. The bucket name is passed at init time
  # (-backend-config="bucket=..."; ./tf does it from TF_STATE_BUCKET). The endpoint, which
  # contains the Cloudflare account ID, comes from AWS_ENDPOINT_URL_S3, and the access key and
  # secret from AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.
  backend "s3" {
    key = "example/terraform.tfstate"

    # R2 has no regions; "auto" is the value Cloudflare documents for S3 clients.
    region = "auto"

    # Locking: a lock file is written next to the state while a run is in progress,
    # so two runs at once can't overwrite each other.
    use_lockfile = true

    # These checks only make sense against real AWS (account lookup, region list, the
    # metadata service, AWS-specific checksums). R2 isn't AWS, so they have to be skipped.
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
