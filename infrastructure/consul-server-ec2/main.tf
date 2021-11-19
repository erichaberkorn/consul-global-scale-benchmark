data "template_file" "consul_server" {
  count = var.consul_server_count

  template = <<EOF
${file("${path.module}/templates/consul-server.tpl")}
EOF
  vars = {
    primary_cluster_addr      = var.consul_primary_addr
    consul_server_count       = var.consul_server_count
    consul_version            = var.consul_version
    consul_datacenter         = var.consul_datacenter
    consul_primary_datacenter = var.consul_primary_datacenter
    consul_primary_gateway = var.consul_primary_gateway
    consul_log_level          = var.consul_log_level
    retry_join_tag            = var.retry_join_tag
    hostname                  = "${var.project}-consul-server-${var.region}-${count.index + 1}"
    datadog_api_key           = var.datadog_api_key
    enable_streaming          = var.enable_streaming
    consul_download_url       = var.consul_download_url
    gossip_encryption_key     = var.gossip_encryption_key
    bootstrap_token           = var.bootstrap_token
    mount_ssd_volume          = var.mount_ssd_volume
  }
}

data "template_cloudinit_config" "consul_server_config" {
  count = var.consul_server_count

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = <<EOT
#!/bin/bash

mkdir -p /etc/consul/tls
sudo tee /etc/consul/tls/ca_cert.pem > /dev/null <<EOC
${var.tls_ca_cert_pem}
EOC
sudo tee /etc/consul/tls/cert.pem > /dev/null <<EOC
${var.tls_server_cert_pem}
EOC
sudo tee /etc/consul/tls/key.pem > /dev/null <<EOC
${var.tls_server_key_pem}
EOC
EOT
  }

  part {
    content_type = "text/x-shellscript"
    content      = element(data.template_file.consul_server.*.rendered, count.index)
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Our consul security group to access
resource "aws_security_group" "consul" {
  name        = "consul"
  description = "Created using Terraform"
  vpc_id      = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_security_group" "consul-elb" {
  name        = "consul-ui-elb"
  description = "Allow ingress to access the Consul UI."
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks     = ["${var.lb_ingress_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "consul_server" {
  count = var.consul_server_count

  instance_type = var.instance_type

  ami = var.ami_id

  # The name of our SSH keypair we created above.
  key_name = var.key_name

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.consul.id]

  iam_instance_profile = var.iam_instance_profile

  subnet_id = element(var.private_subnets, count.index % length(var.private_subnets))

  user_data_base64 = element(data.template_cloudinit_config.consul_server_config.*.rendered, count.index)


  tags = {
    "Name"                  = "${var.project}-consul-server-${var.region}-${count.index + 1}"
    "${var.retry_join_tag}" = var.retry_join_tag
  }
}

resource "aws_elb" "consul_elb" {
  count = var.enable_ui_elb ? 1 : 0

  name            = "consul-ui-${var.project}-elb"
  subnets         = var.public_subnets
  security_groups = [aws_security_group.consul-elb.id]

  listener {
    instance_port     = 8500
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:8500"
    interval            = 10
  }

  instances                   = aws_instance.consul_server.*.id
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "consul-ui-${var.project}-elb"
  }
}
