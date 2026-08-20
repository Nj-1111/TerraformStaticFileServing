variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "project_name" {
  description = "Prefix for resource names."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, format: owner/repo."
  type        = string
}