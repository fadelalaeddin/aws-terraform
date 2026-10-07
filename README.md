# AWS Auto-Scaling Web App with Event-Driven Processing (Terraform)

Terraform project that builds an HA web tier behind a load balancer. I put this together to have a self-contained example: ASG + target tracking, least privilege IAM, no SSH keys anywhere.

There's no real application behind it, just an nginx placeholder because the point of the repo is the infrastructure not the app.


### Compute / traffic path

Traffic hits an ALB in two public subnets, which forwards to a target group
of EC2 instances sitting in private subnets (no public IPs), managed by an
ASG. Each private subnet gets its own NAT Gateway so instances can still
reach the internet for updates etc. without being reachable from the internet.

The ASG scales on a target-tracking policy against average CPU, and does
rolling instance refreshes whenever the launch template changes. There's a
CloudWatch alarm on sustained high CPU too, mostly as a signal for a human
to look at rather than anything that takes action on its own.

### Security

- EC2 instances only have an IAM instance profile with
  `AmazonSSMManagedInstanceCore`. Access is via SSM Session Manager, no SSH
  keys, no open port 22, no bastion.
- Security groups are locked down so the app SG only accepts traffic from
  the ALB's SG.
- IMDSv2 is enforced (`http_tokens = "required"`) on every instance.

## PS

Take a look at `allowed_http_cidr` before you apply. It defaults to
`0.0.0.0/0`, which is fine for messing around but you'll want to tighten it
for anything real.

Apply takes about 3–5 minutes, mostly waiting on the NAT Gateways and ALB.


## License

MIT. Use it as a template for whatever.
