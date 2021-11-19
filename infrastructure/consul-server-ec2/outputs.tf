output "consul_server_addresses" {
  value = length(aws_instance.consul_server) > 0 ? aws_instance.consul_server.*.private_dns : null
}

output "consul_server_address" {
  value = length(aws_instance.consul_server) > 0 ? aws_instance.consul_server.0.private_dns : null
}

output "consul_elb" {
  value = length(aws_elb.consul_elb) > 0 ? aws_elb.consul_elb.0.dns_name : null
}
