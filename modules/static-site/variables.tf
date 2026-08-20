variable "project_name" {
  description = "Prefix for resource names, e.g. bucket = <project_name>-game-<environment>."
  type        = string
}
variable "environment" {
    description = "Environment name rg \"dev\" or \"prod\" . used to name and tag resources"
    type        = string
}

variable "enable_cdn" { 
    description  = "false= dev (public s3 website ,http). true = prod (cloudfront + locked bucket + https)"
    type         = bool
    default      = false          # default false for now since only dev env is being set up NO Prod
}

variable "cloudfront_price_class" {
  description = "CloudFront edge coverage vs cost. Only used when enable_cdn = true."
  type        = string
  default     = "PriceClass_100"
}
