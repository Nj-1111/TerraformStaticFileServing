module "site" {
  source       = "../../modules/static-site"
  environment  = var.environment
  enable_cdn   = var.enable_cdn
  project_name = var.project_name
}
output "site_endpoint" {
  value = module.site.endpoint
}

output "site_bucket" {
  value = module.site.bucket_name
}