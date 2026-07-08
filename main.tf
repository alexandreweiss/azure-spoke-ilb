resource "random_integer" "suffix" {
  min = 100000
  max = 999999
}

locals {
  suffix          = tostring(random_integer.suffix.result)
  spoke_name      = "spoke-${local.suffix}"
  rg_spoke_name   = "spoke-ilb-avx-rg-${local.suffix}"
  rg_3p_name      = "spoke-ilb-3p-rg-${local.suffix}"
  ilb_frontend_ip = "10.100.1.244"
}

# ─── Resource groups ───────────────────────────────────────────────────────────

resource "azurerm_resource_group" "spoke" {
  name     = local.rg_spoke_name
  location = var.region
}

resource "azurerm_resource_group" "thirdparty" {
  name     = local.rg_3p_name
  location = var.region
}

# ─── Aviatrix spoke VNet ───────────────────────────────────────────────────────

resource "aviatrix_vpc" "spoke" {
  cloud_type           = 8 # Azure
  account_name         = var.aviatrix_azure_account
  region               = var.region
  name                 = local.spoke_name
  cidr                 = var.spoke_vnet_cidr
  resource_group       = azurerm_resource_group.spoke.name
  aviatrix_transit_vpc = false
  aviatrix_firenet_vpc = false
}

# ─── Aviatrix spoke gateway + HA ───────────────────────────────────────────────

resource "aviatrix_spoke_gateway" "spoke" {
  cloud_type   = 8
  account_name = var.aviatrix_azure_account
  gw_name      = "${local.spoke_name}-gw"
  vpc_id       = aviatrix_vpc.spoke.vpc_id
  vpc_reg      = var.region
  gw_size      = var.spoke_gw_size
  subnet       = aviatrix_vpc.spoke.public_subnets[0].cidr
  single_ip_snat                    = true
  included_advertised_spoke_routes  = var.thirdparty_vnet_cidr

  ha_subnet  = aviatrix_vpc.spoke.public_subnets[1].cidr
  ha_gw_size = var.spoke_gw_size

  depends_on = [azurerm_resource_group.spoke]
}

# ─── Data source: spoke VNet (created by aviatrix_vpc) ─────────────────────────

data "azurerm_virtual_network" "spoke" {
  name                = aviatrix_vpc.spoke.name
  resource_group_name = azurerm_resource_group.spoke.name

  depends_on = [aviatrix_vpc.spoke]
}

# ─── ILB subnet inside the spoke VNet ─────────────────────────────────────────

resource "azurerm_subnet" "ilb" {
  name                 = "snet-ilb-${local.suffix}"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = data.azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.100.1.240/28"]

  depends_on = [aviatrix_spoke_gateway.spoke]
}

# ─── Azure Internal Load Balancer ──────────────────────────────────────────────

resource "azurerm_lb" "spoke" {
  name                = "ilb-${local.suffix}"
  location            = var.region
  resource_group_name = azurerm_resource_group.spoke.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "frontend"
    subnet_id                     = azurerm_subnet.ilb.id
    private_ip_address            = local.ilb_frontend_ip
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_lb_backend_address_pool" "spoke" {
  name            = "gw-backend-pool"
  loadbalancer_id = azurerm_lb.spoke.id
}

resource "azurerm_lb_probe" "spoke" {
  name            = "probe-443"
  loadbalancer_id = azurerm_lb.spoke.id
  protocol        = "Tcp"
  port            = 443
}

resource "azurerm_lb_rule" "haports" {
  name                           = "ha-ports"
  loadbalancer_id                = azurerm_lb.spoke.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.spoke.id]
  probe_id                       = azurerm_lb_probe.spoke.id
  floating_ip_enabled            = true
  disable_outbound_snat          = true
}

# Backend pool members via private IP — no NIC data source needed.

resource "azurerm_lb_backend_address_pool_address" "gw_primary" {
  name                    = "gw-primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.spoke.id
  virtual_network_id      = data.azurerm_virtual_network.spoke.id
  ip_address              = aviatrix_spoke_gateway.spoke.private_ip
}

resource "azurerm_lb_backend_address_pool_address" "gw_ha" {
  name                    = "gw-ha"
  backend_address_pool_id = azurerm_lb_backend_address_pool.spoke.id
  virtual_network_id      = data.azurerm_virtual_network.spoke.id
  ip_address              = aviatrix_spoke_gateway.spoke.ha_private_ip
  depends_on              = [azurerm_lb_backend_address_pool_address.gw_primary]
}

# ─── Third-party VNet ──────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "thirdparty" {
  name                = "vnet-3p-${local.suffix}"
  location            = var.region
  resource_group_name = azurerm_resource_group.thirdparty.name
  address_space       = [var.thirdparty_vnet_cidr]
}

resource "azurerm_subnet" "thirdparty_vm" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.thirdparty.name
  virtual_network_name = azurerm_virtual_network.thirdparty.name
  address_prefixes     = ["10.101.0.0/25"]
}

# ─── VNet Peering (both directions) ────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "thirdparty_to_spoke" {
  name                      = "peer-3p-to-spoke"
  resource_group_name       = azurerm_resource_group.thirdparty.name
  virtual_network_name      = azurerm_virtual_network.thirdparty.name
  remote_virtual_network_id = data.azurerm_virtual_network.spoke.id
  allow_forwarded_traffic   = true
  use_remote_gateways       = false
}

resource "azurerm_virtual_network_peering" "spoke_to_thirdparty" {
  name                      = "peer-spoke-to-3p"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = data.azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.thirdparty.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
}

# ─── UDR: 0/0 → ILB frontend ──────────────────────────────────────────────────

resource "azurerm_route_table" "thirdparty" {
  name                          = "rt-3p-${local.suffix}"
  location                      = var.region
  resource_group_name           = azurerm_resource_group.thirdparty.name
  bgp_route_propagation_enabled = false
}

resource "azurerm_route" "default_to_ilb" {
  name                   = "default-via-ilb"
  resource_group_name    = azurerm_resource_group.thirdparty.name
  route_table_name       = azurerm_route_table.thirdparty.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.ilb_frontend_ip
}

resource "azurerm_subnet_route_table_association" "thirdparty_vm" {
  subnet_id      = azurerm_subnet.thirdparty_vm.id
  route_table_id = azurerm_route_table.thirdparty.id
}

# ─── SSH key for third-party VM ───────────────────────────────────────────────

resource "tls_private_key" "thirdparty_vm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ─── Third-party VM NIC ────────────────────────────────────────────────────────

resource "azurerm_network_interface" "thirdparty_vm" {
  name                = "nic-3p-vm-${local.suffix}"
  location            = var.region
  resource_group_name = azurerm_resource_group.thirdparty.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.thirdparty_vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ─── Third-party VM (Ubuntu 22.04) with Gatus dashboard ───────────────────────

resource "azurerm_linux_virtual_machine" "thirdparty" {
  name                            = "vm-3p-${local.suffix}"
  location                        = var.region
  resource_group_name             = azurerm_resource_group.thirdparty.name
  size                            = "Standard_B2s"
  admin_username                  = var.thirdparty_vm_admin_username
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.thirdparty_vm.id]

  admin_ssh_key {
    username   = var.thirdparty_vm_admin_username
    public_key = tls_private_key.thirdparty_vm.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(file("${path.module}/templates/cloud-init.yaml"))
}
