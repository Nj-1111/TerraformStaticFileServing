resource "aws_s3_bucket" "site" {
    bucket = "${var.project_name}-game-${var.environment}"

    tags = {
        Project        = var.project_name
        Environments   = var.environment
        ManagedBy      = "Terraform"
    }
}

resource "aws_s3_bucket_website_configuration" "site" {
    count  = var.enable_cdn ? 0 : 1
    bucket = aws_s3_bucket.site.id

    index_document {
        suffix = "index.html"
    }

    error_document {
        key = "error.html"
    }
}

resource "aws_s3_bucket_public_access_block" "site" {
    count  = var.enable_cdn ? 0 : 1
    bucket = aws_s3_bucket.site.id

    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
}




resource "aws_s3_bucket_policy" "site" {
    count  = var.enable_cdn ? 0 : 1
    bucket = aws_s3_bucket.site.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid = "PublicReadGetObject"
                Effect = "Allow"
                Principal = "*"
                Action = "s3:GetObject"
                Resource = "${aws_s3_bucket.site.arn}/*"
            }
        ]
    })
depends_on = [aws_s3_bucket_public_access_block.site[0]]
}



resource "aws_s3_bucket_public_access_block" "prod" {
  count  = var.enable_cdn ? 1 : 0
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  count                             = var.enable_cdn ? 1 : 0
  name                              = "${var.project_name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  count               = var.enable_cdn ? 1 : 0
  enabled             = true
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${var.project_name}-${var.environment}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac[0].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${var.project_name}-${var.environment}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "prod" {
  count  = var.enable_cdn ? 1 : 0
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn[0].arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.prod[0]]
}