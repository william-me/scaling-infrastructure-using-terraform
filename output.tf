output "load_balancer_url" {
  value = aws_lb.mylb.dns_name
}