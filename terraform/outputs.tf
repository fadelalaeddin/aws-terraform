
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


# STORAGE / EVENT PIPELINE OUTPUTS


output "s3_bucket_name" {
  description = "Name of the S3 bucket that receives events."
  value       = aws_s3_bucket.events.bucket
}

output "lambda_function_name" {
  description = "Name of the Lambda function that processes S3 events."
  value       = aws_lambda_function.event_processor.function_name
}

output "lambda_cloudwatch_log_group" {
  description = "CloudWatch Log Group for the Lambda function."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "pipeline_queue_url" {
  description = "URL of the SQS queue that buffers S3 events before Lambda processes them."
  value       = aws_sqs_queue.pipeline.url
}

output "pipeline_queue_name" {
  description = "Name of the SQS pipeline queue."
  value       = aws_sqs_queue.pipeline.name
}

output "pipeline_dlq_url" {
  description = "URL of the dead-letter queue. Messages here mean processing failed repeatedly and need investigation."
  value       = aws_sqs_queue.pipeline_dlq.url
}

output "pipeline_dlq_name" {
  description = "Name of the dead-letter queue."
  value       = aws_sqs_queue.pipeline_dlq.name
}
