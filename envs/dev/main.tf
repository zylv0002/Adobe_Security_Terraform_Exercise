#############################################
# Dev environment: VPC, ECS Fargate (Juice Shop), ALB, WAF, logging pipeline, Athena
#############################################
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.region
}

################ VPC + Networking ################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

data "aws_availability_zones" "available" {}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags                    = { Name = "${var.project}-public-${count.index}" }
}

resource "aws_route_table" "public" { vpc_id = aws_vpc.this.id }

resource "aws_route" "igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "a" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################ ECS Cluster ################
resource "aws_ecs_cluster" "this" { name = "${var.project}-cluster" }

resource "aws_iam_role" "task_exec" {
  name               = "${var.project}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "exec_attach" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_security_group" "svc" {
  name        = "${var.project}-svc-sg"
  description = "Service SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "juice" {
  family                   = "${var.project}-juice"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([
    {
      name         = "juice-shop",
      image        = var.juice_image,
      essential    = true,
      portMappings = [{ containerPort = 3000, protocol = "tcp" }],
      environment  = [{ name = "NODE_ENV", value = "production" }]
    }
  ])
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "tg" {
  name        = "${var.project}-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id
  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_ecs_service" "svc" {
  name            = "${var.project}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.juice.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    assign_public_ip = true
    security_groups  = [aws_security_group.svc.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "juice-shop"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.http]
}

# Output front door id for WAF association
output "front_door_id" { value = aws_lb.alb.arn }

#############################################
# WAF – Reusable module
#############################################
module "edge_waf" {
  source           = "../../modules/edge_waf"
  name             = "${var.project}-web-acl"
  scope            = var.waf_scope
  front_door_assoc = aws_lb.alb.arn
  whitelist_ips    = []
}

#############################################
# WAF Logging -> Firehose -> S3
#############################################
resource "random_id" "rand" { byte_length = 4 }

resource "aws_s3_bucket" "logs" {
  bucket        = "${var.project}-waf-logs-${random_id.rand.hex}"
  force_destroy = true
}

resource "aws_iam_role" "firehose" {
  name               = "${var.project}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project}-firehose-policy"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      #S3 Access
      { Effect = "Allow",
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
      Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"] },

      #CloudWatch Logs Access
      { Effect = "Allow", Action = ["logs:PutLogEvents"], Resource = "*" },

      #WAF Read Access
      { Effect = "Allow",
        Action = [
          "wafv2:GetWebACL",
          "wafv2:ListWebACLs"
        ],
        Resource = "*"
      },

      #Grant WAF write access only to WAF resources.
      {
        Effect = "Allow",
        Action = [
          "wafv2:CreateWebACL",
          "wafv2:UpdateWebACL", 
          "wafv2:DeleteWebACL"
        ],
        Resource = "arn:aws:wafv2:*:*:*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "waf" {
  name        = "${var.project}-waf-logs"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.logs.arn
    buffering_interval  = 60
    buffering_size      = 5
    compression_format  = "GZIP"
    prefix              = "waf/"
    error_output_prefix = "waf_errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
  }
}

# TODO: Enable WAF logging

resource "aws_wafv2_web_acl_logging_configuration" "waf_logs" {
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf.arn]
  resource_arn            = module.edge_waf.web_acl_arn

  depends_on = [
    aws_kinesis_firehose_delivery_stream.waf,
  ]
}



# TODO: Enable Athena catalog for WAF logs

#############################################
# Athena catalog for WAF logs
#############################################

resource "aws_athena_database" "waf" {
  name   = replace("${var.project}_waf_db", "-", "_")
  bucket = aws_s3_bucket.logs.bucket
}


resource "aws_glue_catalog_table" "waf_logs" {
  name          = "waf_logs"
  database_name = aws_athena_database.waf.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/waf/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    # Columns needed for KPI query
    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "terminatingruleid"
      type = "string"
    }
    columns {
      name = "terminatingruletype"
      type = "string"
    }
 
    columns {
      name = "rulegrouplist"
      type = "array<struct<rulegroupid:string>>"
    }
  }
}

# KPI query
resource "aws_athena_named_query" "waf_kpi_query" {
  name      = "waf_kpi_metrics"
  database  = aws_athena_database.waf.name
  workgroup = "primary"
  
  query = <<EOF
-- "total_requests, blocked_requests and percent_blocked"
WITH request_stats AS (
  SELECT
    COUNT(*) AS total_requests,
    COUNT_IF(action = 'BLOCK') AS blocked_requests,
    ROUND(COUNT_IF(action = 'BLOCK') * 100.0 / COUNT(*), 2) AS percent_blocked
  FROM waf_logs
  WHERE from_unixtime(timestamp/1000) >= current_date - INTERVAL '7' DAY
),
-- "top_5_attack_vectors"
attack_vectors AS (
  SELECT
    COALESCE(terminatingruleid, 'unknown') as rule_id,
    COUNT(*) as block_count
  FROM waf_logs
  WHERE action = 'BLOCK'
  GROUP BY terminatingruleid
  ORDER BY block_count DESC
  LIMIT 5
)
SELECT 
  total_requests,
  blocked_requests,
  percent_blocked,
  MAP_AGG(rule_id, block_count) as top_5_attack_vectors
FROM request_stats
CROSS JOIN attack_vectors
GROUP BY total_requests, blocked_requests, percent_blocked
EOF
}


output "alb_dns_name" { value = aws_lb.alb.dns_name }
output "waf_web_acl_arn" { value = module.edge_waf.web_acl_arn }
output "logs_bucket" { value = aws_s3_bucket.logs.bucket }
output "firehose_name" { value = aws_kinesis_firehose_delivery_stream.waf.name }
output "athena_database" { value = aws_athena_database.waf.name }
output "athena_table" { value = aws_glue_catalog_table.waf_logs.name }
