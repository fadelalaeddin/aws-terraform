# AWS Auto-Scaling Web App with Event-Driven Processing (Terraform)

Terraform project that builds an HA web tier behind a load balancer plus a
small event driven pipeline (S3 → EventBridge → SQS → Lambda) for background
processing. I put this together to have a self-contained example: ASG + target tracking, decoupled
queue-based processing with a DLQ, least privilege IAM, no SSH keys anywhere.

There's no real application behind it, just an nginx placeholder and a small Lambda handler because the point of the repo is the infrastructure not the app.


### Compute / traffic path

Traffic hits an ALB in two public subnets, which forwards to a target group
of EC2 instances sitting in private subnets (no public IPs), managed by an
ASG. Each private subnet gets its own NAT Gateway so instances can still
reach the internet for updates etc. without being reachable from it.

The ASG scales on a target-tracking policy against average CPU, and does
rolling instance refreshes whenever the launch template changes. There's a
CloudWatch alarm on sustained high CPU too, mostly as a signal for a human
to look at rather than anything that takes action on its own.

### Event pipeline

An S3 bucket (versioned, encrypted, public access fully blocked) fires
EventBridge notifications on object creation. I send those to an SQS queue
instead of invoking Lambda directly. This smooths out bursts of incoming
files and means a Lambda outage or throttle doesn't just lose events.

Lambda pulls from the queue through an event source mapping (AWS polls SQS
and invokes the function in batches of up to 10). The handler reports
partial batch failures, so only the messages that actually failed get
retried instead of the whole batch. After `sqs_max_receive_count` failed
attempts (5 by default), SQS moves the message to a dead-letter queue on
its own, so there's no infinite retry loop, and nothing silently vanishes. A
CloudWatch alarm fires as soon as anything lands in the DLQ so a failed run
doesn't just sit there unnoticed.

Basically the same queue + DLQ shape you'd use for any real pipeline where
losing a message quietly is not an option.

### Security

- EC2 instances only have an IAM instance profile with
  `AmazonSSMManagedInstanceCore`. Access is via SSM Session Manager, no SSH
  keys, no open port 22, no bastion.
- Lambda's role is scoped to CloudWatch Logs and `s3:GetObject` on this one
  bucket, nothing wildcarded.
- Security groups are locked down so the app SG only accepts traffic from
  the ALB's SG.
- IMDSv2 is enforced (`http_tokens = "required"`) on every instance.

## Repo layout

.
├── terraform/
│   ├── main.tf                      # All resources (networking, compute, ASG, S3, Lambda, alarms)
│   ├── variables.tf                 # Input variables with defaults and validation
│   ├── outputs.tf                   # Useful outputs (ALB URL, bucket name, etc.)
│   ├── versions.tf                  # Terraform + provider version pins
│   ├── user_data.sh                 # EC2 bootstrap script (installs nginx, serves a health page)
│   └── terraform.tfvars.example     # Copy to terraform.tfvars and customize
├── lambda/
│   └── handler.py                   # Lambda function source (zipped by Terraform at apply time)
├── .gitignore
└── README.md


Take a look at `allowed_http_cidr` before you apply. It defaults to
`0.0.0.0/0`, which is fine for messing around but you'll want to tighten it
for anything real.

Apply takes about 3–5 minutes, mostly waiting on the NAT Gateways and ALB.


## License

MIT. Use it as a template for whatever.
