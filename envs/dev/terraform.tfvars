project        = "juice-waf-dev"
region         = "us-east-1"
vpc_cidr       = "10.42.0.0/16"
public_subnets = ["10.42.1.0/24", "10.42.2.0/24"]
juice_image    = "bkimminich/juice-shop:latest"
waf_scope      = "REGIONAL"
