# Claude Code Context — azure-spoke-ilb

## Architecture

Azure Aviatrix spoke + HA with an Internal Load Balancer fronting both gateway NICs. A third-party VNet (simulating a different-tenant partner) is peered externally and steers traffic via UDR → ILB frontend. The spoke advertises the partner CIDR as a custom route upstream.

## Provider Versions

- `aviatrixsystems/aviatrix ~> 8.2`
- `hashicorp/azurerm ~> 4.0`
- `hashicorp/random ~> 3.0`
- `hashicorp/tls ~> 4.0`

## Aviatrix Resource Rules

- **Always use `aviatrix_spoke_gateway`** for spoke gateways — never `aviatrix_gateway` (that resource is for rare edge cases only)
- HA is managed inline on `aviatrix_spoke_gateway` via `ha_subnet` + `ha_gw_size` (not a separate resource)
- Single-IP SNAT = `single_ip_snat = true` (not `snat_mode = "primary"` — that is deprecated since R2.10)
- Custom CIDR advertisement = `included_advertised_spoke_routes` (comma-separated string)
- Transit attachment must use `aviatrix_spoke_transit_attachment` — `manage_transit_gateway_attachment` was removed in provider 8.x
- Spoke VNet created via `aviatrix_vpc` (cloud_type=8 for Azure); reference subnets via `public_subnets[N].cidr`

## Azure ILB Rules

- SKU must be Standard
- HAPort rule: `protocol = "All"`, `frontend_port = 0`, `backend_port = 0`, `floating_ip_enabled = true`
- Backend pool members use `azurerm_lb_backend_address_pool_address` with private IPs — no NIC resources needed for Aviatrix gateways
- Add `depends_on` between backend address resources to avoid 409 conflicts (Azure serializes pool mutations)
- Health probe: TCP 443

## Naming

All resources use a `random_integer` (100000–999999) suffix stored in `local.suffix`. Resource group names: `spoke-ilb-avx-rg-{suffix}` and `spoke-ilb-3p-rg-{suffix}`.

## ILB Subnet

`10.100.1.240/28` — created via `azurerm_subnet` after `aviatrix_spoke_gateway` completes (Aviatrix owns the VNet; subnets must be added after GW creation).

## Credentials — Ask the Deployer

Before making any changes, ask the deployer for:

- Aviatrix controller FQDN or IP
- Aviatrix controller username and password → goes in `var.aviatrix_password` (sensitive, never hardcode)
- Aviatrix Azure account name → `var.aviatrix_azure_account`
- Azure subscription ID → `var.azure_subscription_id`

Update `terraform.tfvars` (gitignored) with these values. Never commit credentials.
