
# NETWORKING OUTPUTS


output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}


# LOAD BALANCER OUTPUT


output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. Open this in a browser to reach the app."
  value       = aws_lb.application.dns_name
}

output "alb_url" {
  description = "Convenience HTTP URL for the load balancer."
  value       = "http://${aws_lb.application.dns_name}"
}

# COMPUTE / AUTO SCALING OUTPUTS


output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.application.name
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the ASG."
  value       = aws_launch_template.application.id
}
