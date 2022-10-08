output "IP" {
  value = data.aws_instances.test.public_ips[0]
}
output "RDS-Endpoint" {
  value = aws_db_instance.wordpressdb.endpoint
}
output "INFO" {
  value = "AWS Resources and Wordpress has been provisioned. Go to http://${data.aws_instances.test.public_ips[0]} "
}
output "elb_dns_name" {
  value = "${aws_elb.webserver-elb.dns_name}"
} 