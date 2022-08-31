variable "region" {
  description = "AWS Deployment region.."
  default     = "us-east-1"
}

variable "bucket_name" {}

variable "name" {
  description = "Name tag, e.g stack"
  default     = "stack"
}

variable "acl_value" {
  description = "Value of ACL"
  default     = "public-read-write"
}

variable "environment" {
  description = "The Deployment environment"
}

//Networking
variable "vpc_cidr" {
  description = "The CIDR block of the vpc"
}

variable "public_subnets_cidr" {
  type        = list(any)
  description = "The CIDR block for the public subnet"
}

variable "private_subnets_cidr" {
  type        = list(any)
  description = "The CIDR block for the private subnet"
}

variable "availability_zones" {
  type        = list(any)
  description = "The CIDR block for the private subnet"
}

variable "db_password" {
  description = "RDS root user password"
  type        = string
  sensitive   = true
}
