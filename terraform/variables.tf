
# GENERAL


variable "aws_region" {
  description = "AWS region to deploy all resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resource names (letters, numbers, hyphens)."
  type        = string
  default     = "ngs-webapp"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}


# NETWORKING


variable "vpc_cidr" {
  description = "CIDR block for the VPC. Subnets are carved out of this range."
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_http_cidr" {
  description = "CIDR block allowed to reach the ALB on port 80. Restrict this in production (e.g. an office/VPN range)."
  type        = string
  default     = "0.0.0.0/0"
}


# COMPUTE / AUTO SCALING


variable "instance_type" {
  description = "EC2 instance type used by the launch template."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 2
}

variable "asg_desired_size" {
  description = "Desired number of instances in the Auto Scaling Group."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 4
}

variable "cpu_target_value" {
  description = "Target average CPU utilization (%) for the ASG target-tracking scaling policy."
  type        = number
  default     = 50
}
