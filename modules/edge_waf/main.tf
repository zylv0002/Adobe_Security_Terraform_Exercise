#############################################
# Reusable AWS WAF v2 WebACL Module (edge_waf)
#############################################
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "name" { type = string }
variable "scope" {
  type = string
  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL (ALB/API GW) or CLOUDFRONT"
  }
}
# Association target: ALB ARN (REGIONAL) or CloudFront Distribution ID (CLOUDFRONT)
variable "front_door_assoc" { type = string }
variable "whitelist_ips" {
  type    = list(string)
  default = []
}

locals {
  managed = [
    { name = "AWSManagedRulesCommonRuleSet", vendor = "AWS", priority = 10 },
    { name = "AWSManagedRulesSQLiRuleSet", vendor = "AWS", priority = 20 }
  ]
}

resource "aws_wafv2_ip_set" "allowlist" {
  count              = length(var.whitelist_ips) > 0 ? 1 : 0
  name               = "${var.name}-allowlist"
  description        = "Allowlisted IPs"
  scope              = var.scope
  ip_address_version = "IPV4"
  addresses          = var.whitelist_ips
}

resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = "Reusable WebACL with managed groups + custom Juice Shop SQLi rule"
  scope       = var.scope

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.managed
    content {
      # Declare rule name for this WAF module
      name     = rule.value.name
      priority = rule.value.priority
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          # Declare vendor name and the managed rule group for Terraform plan
          name        = rule.value.name
          vendor_name = rule.value.vendor 
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${var.name}-${rule.value.name}"
      }
    }
  }

  # Custom rule: Block "' OR 1=1--" when path is /rest/products/search
  rule {
    name     = "JuiceShopSQLiOnSearchPath"
    priority = 30
    action {
      block {}
    }
    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match {
              uri_path {}
            }
            positional_constraint = "EXACTLY"
            search_string         = "/rest/products/search"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        statement {
          byte_match_statement {
            field_to_match {
              query_string {}
            }
            positional_constraint = "CONTAINS"
            search_string         = "' OR 1=1--"
            text_transformation {
              priority = 0
              type     = "URL_DECODE"
            }
            text_transformation {
              priority = 1
              type     = "COMPRESS_WHITE_SPACE"
            }
            text_transformation {
              priority = 2
              type     = "LOWERCASE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "${var.name}-custom-sqli"
    }
  }

  dynamic "rule" {
    for_each = length(var.whitelist_ips) > 0 ? [1] : []
    content {
      name     = "AllowlistIPs"
      priority = 5
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowlist[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        sampled_requests_enabled   = true
        metric_name                = "${var.name}-allow"
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "${var.name}-webacl"
  }
}




# Associate to ALB (REGIONAL). For CloudFront, set web_acl_id on the distribution in its resource.
resource "aws_wafv2_web_acl_association" "assoc" {
#If scope is REGIONAL → create 1 association (attach WebACL to the ALB).
#If scope is CLOUDFRONT → create 0 associations (skip; CloudFront handles it on the distribution).
  count        = var.scope == "REGIONAL" ? 1 : 0
  resource_arn = var.front_door_assoc
  web_acl_arn  = aws_wafv2_web_acl.this.arn
  # Ignore changes made to the variables outside of this .tf (change made in the AWS console). Only affect varaibles that mentioned in this association block.
  lifecycle { ignore_changes = all }
}

# output the webacl arn and id to teraform.tfstate after 'terraform apply'
output "web_acl_arn" { value = aws_wafv2_web_acl.this.arn }
output "web_acl_id" { value = aws_wafv2_web_acl.this.id }
