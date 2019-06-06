provider "google" {
  # export GOOGLE_CREDENTIALS as env var
  project     = "cf-bosh-core"
  region      = "us-central1"
  version     = "~> 2.7.0"
}
