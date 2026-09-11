terraform {
  required_version = ">= 1.9.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.4"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.21"
    }
  }
}
