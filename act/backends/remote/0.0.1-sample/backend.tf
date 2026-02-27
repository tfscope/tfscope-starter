# v0-sample — reference only
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://tor1.digitaloceanspaces.com"
    }

    region = "us-east-1"
    # bucket via cli: -backend-config="bucket=..."
    # key via cli:    -backend-config="key=..."

    skip_credentials_validation = true # DO is not AWS, no credential validation
    skip_metadata_api_check     = true # no EC2 metadata API on DO
    skip_region_validation      = true # us-east-1 is a dummy region for S3 compat
    skip_requesting_account_id  = true # no AWS account ID on DO
    skip_s3_checksum            = true # DO Spaces does not support SHA256 checksum
  }
}
