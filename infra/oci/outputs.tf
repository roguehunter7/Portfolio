output "instance_id" {
  description = "OCID of the portfolio-node instance"
  value       = oci_core_instance.portfolio_node.id
}

output "instance_public_ip" {
  description = "Ephemeral public IP (outbound only — NSG has zero ingress rules)"
  value       = oci_core_instance.portfolio_node.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the instance"
  value       = oci_core_instance.portfolio_node.private_ip
}
