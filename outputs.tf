output "suffix" {
  description = "6-digit random suffix used in all resource names"
  value       = local.suffix
}

output "spoke_vnet_name" {
  description = "Aviatrix spoke VNet name"
  value       = aviatrix_vpc.spoke.name
}

output "spoke_gw_primary" {
  description = "Primary spoke gateway name"
  value       = aviatrix_spoke_gateway.spoke.gw_name
}

output "spoke_gw_ha_name" {
  description = "HA spoke gateway name"
  value       = "${aviatrix_spoke_gateway.spoke.gw_name}-hagw"
}

output "spoke_gw_primary_private_ip" {
  description = "Primary spoke gateway private IP"
  value       = aviatrix_spoke_gateway.spoke.private_ip
}

output "spoke_gw_ha_private_ip" {
  description = "HA spoke gateway private IP"
  value       = aviatrix_spoke_gateway.spoke.ha_private_ip
}

output "ilb_frontend_ip" {
  description = "Azure ILB frontend private IP"
  value       = local.ilb_frontend_ip
}

output "ilb_id" {
  description = "Azure ILB resource ID"
  value       = azurerm_lb.spoke.id
}

output "thirdparty_vm_private_ip" {
  description = "Private IP of the third-party VM"
  value       = azurerm_network_interface.thirdparty_vm.private_ip_address
}

output "gatus_url" {
  description = "Gatus dashboard URL (accessible from within the third-party VNet)"
  value       = "http://${azurerm_network_interface.thirdparty_vm.private_ip_address}:8080"
}

output "thirdparty_vm_private_key_pem" {
  description = "Private key to SSH into the third-party VM"
  value       = tls_private_key.thirdparty_vm.private_key_pem
  sensitive   = true
}
