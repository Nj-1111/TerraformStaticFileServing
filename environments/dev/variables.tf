variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
}

variable "environment" {
  description = "Environment name (dev or prod)."
  type        = string
}

variable "enable_cdn" {
  description = "false = public S3 website (dev). true = locked bucket + CloudFront (prod)."
  type        = bool
}

variable "project_name" {
  description = "Prefix for resource names."
  type        = string
}