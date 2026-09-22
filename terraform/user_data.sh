#!/bin/bash
set -euo pipefail

# Install and start nginx
dnf install -y nginx

INSTANCE_ID=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" | \
  xargs -I{} curl -s -H "X-aws-ec2-metadata-token: {}" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" | \
  xargs -I{} curl -s -H "X-aws-ec2-metadata-token: {}" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>AWS Auto Scaling Demo</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 10%;">
  <h1>It works!</h1>
  <p>Served by instance: <strong>${INSTANCE_ID}</strong></p>
  <p>Availability zone: <strong>${AZ}</strong></p>
</body>
</html>
EOF

systemctl enable nginx
systemctl start nginx
