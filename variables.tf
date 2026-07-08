variable "aviatrix_password" {
  description = "Aviatrix controller admin password"
  type        = string
  sensitive   = true
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "aviatrix_azure_account" {
  description = "Aviatrix access account name for Azure"
  type        = string
}

variable "region" {
  description = "Azure region"
  type        = string
  default     = "France Central"
}

variable "spoke_gw_size" {
  description = "Aviatrix spoke gateway instance size"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "spoke_vnet_cidr" {
  description = "CIDR for the Aviatrix spoke VNet"
  type        = string
  default     = "10.100.0.0/23"
}

variable "thirdparty_vnet_cidr" {
  description = "CIDR for the third-party VNet"
  type        = string
  default     = "10.101.0.0/24"
}

variable "thirdparty_vm_admin_username" {
  description = "Admin username for the third-party VM"
  type        = string
  default     = "admin-lab"
}

variable "transit_gw_name" {
  description = "Name of the existing Aviatrix transit gateway to attach the spoke to (optional)"
  type        = string
  default     = ""
}
