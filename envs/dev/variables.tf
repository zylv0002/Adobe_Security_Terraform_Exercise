variable "project" { type = string }
variable "region" { type = string }
variable "vpc_cidr" { type = string }
variable "public_subnets" { type = list(string) }
variable "juice_image" { type = string }
variable "waf_scope" {
  type    = string
  default = "REGIONAL"
}
