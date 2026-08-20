output "bucket_name" {
    description = "name of the s3 bucket holding the game files(the game pipeline syncs here)"
    value       = aws_s3_bucket.site.bucket
}
output "endpoint" { 
    description = "url where the site is served form for dev this is the s3 website endpoint http"
    value       = var.enable_cdn ? "https://${aws_cloudfront_distribution.cdn[0].domain_name}" : "http://${aws_s3_bucket_website_configuration.site[0].website_endpoint}"
}