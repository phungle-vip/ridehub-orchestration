output "protected_application_urls" {
  description = "URLs of applications protected by Cloudflare Zero Trust"
  value = {
    for k, v in cloudflare_zero_trust_access_application.apps : k => "https://${v.domain}"
  }
}
