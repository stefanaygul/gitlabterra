output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnets" {
  value = aws_subnet.public_subnet.*.id
}

output "private_subnets" {
  value = aws_subnet.private_subnet.*.id
}

output "security_group" {
  value = aws_security_group.default.id
}

output "elb-dns-name" {
  value = aws_elb.terra-elb.dns_name
}

output "rds_hostname" {
  description = "RDS instance hostname"
  value       = aws_db_instance.gitlab_instance.address
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.gitlab_instance.port
  sensitive   = true
}

output "rds_username" {
  description = "RDS instance root username"
  value       = aws_db_instance.gitlab_instance.username
  sensitive   = true
}