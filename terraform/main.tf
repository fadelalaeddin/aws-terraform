# DATA SOURCES


data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


# LOCALS


locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "AWS Infrastructure Portfolio Project"
  }

  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )
}


# VPC


resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}


# INTERNET GATEWAY


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}


# PUBLIC SUBNETS


resource "aws_subnet" "public" {
  count = 2

  vpc_id = aws_vpc.main.id

  cidr_block = cidrsubnet(
    var.vpc_cidr,
    8,
    count.index + 10
  )

  availability_zone = local.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  })
}


# PRIVATE SUBNETS


resource "aws_subnet" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  cidr_block = cidrsubnet(
    var.vpc_cidr,
    8,
    count.index + 20
  )

  availability_zone = local.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  })
}


# PUBLIC ROUTE TABLE


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}


# PUBLIC ROUTE TABLE ASSOCIATIONS


resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


# NAT GATEWAY ELASTIC IPs


resource "aws_eip" "nat" {
  count = 2

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}


# NAT GATEWAYS


resource "aws_nat_gateway" "main" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  })
}


# PRIVATE ROUTE TABLES


resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}


# PRIVATE ROUTE TABLE ASSOCIATIONS


resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}


# ALB SECURITY GROUP


resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-sg-"
  description = "Security group for the Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from allowed CIDR"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}


# APPLICATION SECURITY GROUP


resource "aws_security_group" "application" {
  name_prefix = "${local.name_prefix}-app-sg-"
  description = "Security group for private EC2 application instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from Application Load Balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-application-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}


# EC2 IAM ROLE


resource "aws_iam_role" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-role"
  })
}


# EC2 SSM IAM POLICY


resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# EC2 INSTANCE PROFILE


resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2.name
}


# LAMBDA IAM ROLE


resource "aws_iam_role" "lambda" {
  name_prefix = "${local.name_prefix}-lambda-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-role"
  })
}


# LAMBDA CLOUDWATCH LOGS IAM POLICY


resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# LAMBDA S3 READ-ONLY POLICY (scoped to this bucket only)


resource "aws_iam_role_policy" "lambda_s3_read" {
  name_prefix = "${local.name_prefix}-lambda-s3-read-"
  role        = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.events.arn}/*"
      }
    ]
  })
}


# APPLICATION LOAD BALANCER


resource "aws_lb" "application" {
  name = substr("${local.name_prefix}-alb", 0, 32)

  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]
  subnets         = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}


# ALB TARGET GROUP


resource "aws_lb_target_group" "application" {
  name = substr("${local.name_prefix}-tg", 0, 32)

  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-group"
  })
}


# ALB HTTP LISTENER


resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application.arn
  port               = 80
  protocol           = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}


# EC2 LAUNCH TEMPLATE


resource "aws_launch_template" "application" {
  name_prefix = "${local.name_prefix}-"

  image_id      = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.application.id]

  user_data = filebase64("${path.module}/user_data.sh")

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-instance"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}


# AUTO SCALING GROUP


resource "aws_autoscaling_group" "application" {
  name = "${local.name_prefix}-asg"

  min_size         = var.asg_min_size
  desired_capacity = var.asg_desired_size
  max_size         = var.asg_max_size

  vpc_zone_identifier = aws_subnet.private[*].id

  health_check_type         = "ELB"
  health_check_grace_period = 120

  target_group_arns = [aws_lb_target_group.application.arn]

  launch_template {
    id      = aws_launch_template.application.id
    version = aws_launch_template.application.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_lb_listener.http
  ]
}


# AUTO SCALING TARGET TRACKING POLICY


resource "aws_autoscaling_policy" "target_tracking" {
  name = "${local.name_prefix}-target-tracking"

  autoscaling_group_name = aws_autoscaling_group.application.name
  policy_type             = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }
}


# S3 BUCKET RANDOM SUFFIX


resource "random_id" "bucket_suffix" {
  byte_length = 4
}


# S3 EVENT BUCKET


resource "aws_s3_bucket" "events" {
  bucket = "${local.name_prefix}-events-${random_id.bucket_suffix.hex}"

  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-events"
  })
}


# S3 PUBLIC ACCESS BLOCK


resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# S3 VERSIONING


resource "aws_s3_bucket_versioning" "events" {
  bucket = aws_s3_bucket.events.id

  versioning_configuration {
    status = "Enabled"
  }
}


# S3 ENCRYPTION


resource "aws_s3_bucket_server_side_encryption_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


# S3 -> EVENTBRIDGE INTEGRATION


resource "aws_s3_bucket_notification" "events" {
  bucket      = aws_s3_bucket.events.id
  eventbridge = true
}


# SQS DEAD-LETTER QUEUE


resource "aws_sqs_queue" "pipeline_dlq" {
  name = "${local.name_prefix}-pipeline-dlq"

  message_retention_seconds = 1209600 # 14 days - max retention, gives time to investigate

  sqs_managed_sse_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-pipeline-dlq"
  })
}


# SQS MAIN PROCESSING QUEUE


resource "aws_sqs_queue" "pipeline" {
  name = "${local.name_prefix}-pipeline-queue"

  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.pipeline_dlq.arn
    maxReceiveCount      = var.sqs_max_receive_count
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-pipeline-queue"
  })
}


# SQS QUEUE POLICY


resource "aws_sqs_queue_policy" "pipeline" {
  queue_url = aws_sqs_queue.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeSendMessage"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.pipeline.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_object_created.arn
          }
        }
      }
    ]
  })
}


# EVENTBRIDGE S3 OBJECT CREATED RULE


resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${local.name_prefix}-s3-object-created"
  description = "Capture S3 Object Created events."

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.events.bucket]
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-event-rule"
  })
}


# LAMBDA PACKAGE


data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda_function.zip"
}


# LAMBDA FUNCTION


resource "aws_lambda_function" "event_processor" {
  function_name = "${local.name_prefix}-event-processor"

  role    = aws_iam_role.lambda.arn
  handler = "handler.lambda_handler"
  runtime = "python3.12"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-event-processor"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy.lambda_s3_read
  ]
}


# LAMBDA CLOUDWATCH LOG GROUP


resource "aws_cloudwatch_log_group" "lambda" {
  name = "/aws/lambda/${local.name_prefix}-event-processor"

  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}


# EVENTBRIDGE -> SQS TARGET


resource "aws_cloudwatch_event_target" "sqs" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "SQSTarget"
  arn       = aws_sqs_queue.pipeline.arn
}


# LAMBDA SQS CONSUME PERMISSIONS


resource "aws_iam_role_policy" "lambda_sqs" {
  name_prefix = "${local.name_prefix}-lambda-sqs-"
  role        = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.pipeline.arn
      }
    ]
  })
}


# SQS -> LAMBDA EVENT SOURCE MAPPING


resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.pipeline.arn
  function_name    = aws_lambda_function.event_processor.arn

  batch_size                        = 10
  maximum_batching_window_in_seconds = 5
  function_response_types           = ["ReportBatchItemFailures"]

  depends_on = [
    aws_iam_role_policy.lambda_sqs
  ]
}


# CLOUDWATCH ALARM - MESSAGES IN DEAD-LETTER QUEUE


resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name        = "${local.name_prefix}-dlq-messages-visible"
  alarm_description = "One or more messages have landed in the pipeline dead-letter queue and need investigation."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  metric_name = "ApproximateNumberOfMessagesVisible"
  namespace   = "AWS/SQS"
  period      = 300
  statistic   = "Maximum"
  threshold   = 0

  dimensions = {
    QueueName = aws_sqs_queue.pipeline_dlq.name
  }

  treat_missing_data = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dlq-alarm"
  })
}


# CLOUDWATCH HIGH CPU ALARM


resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name        = "${local.name_prefix}-high-cpu"
  alarm_description = "High CPU utilization across the application Auto Scaling Group."

  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2

  metric_name = "CPUUtilization"
  namespace   = "AWS/EC2"
  period      = 300
  statistic   = "Average"
  threshold   = 80

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.application.name
  }

  treat_missing_data = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-high-cpu-alarm"
  })
}
