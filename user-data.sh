#!/bin/bash
yum update -y
yum install -y docker git

# Start Docker service
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install kubectl
curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.1/2023-04-19/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Clone application repository
cd /home/ec2-user
git clone https://github.com/${github_owner}/${github_repo}.git
chown -R ec2-user:ec2-user /home/ec2-user/${github_repo}

# Create a simple web application
mkdir -p /home/ec2-user/app
cat > /home/ec2-user/app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>DevSecOps Demo</title>
</head>
<body>
    <h1>Welcome to DevSecOps Integration Demo</h1>
    <p>This application is deployed using GitOps with security scanning integration.</p>
    <p>Server: $(hostname)</p>
</body>
</html>
EOF

# Create Dockerfile
cat > /home/ec2-user/app/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

chown -R ec2-user:ec2-user /home/ec2-user/app
