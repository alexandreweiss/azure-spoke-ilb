# Azure Aviatrix Spoke with Internal Load Balancer

## Use Case

This reference architecture covers third-party / different-tenant partner onboarding into an Aviatrix-managed network — typical scenarios include SAP Rise, managed service providers, or any external partner that runs their own Azure tenant/subscription and needs routed connectivity through an Aviatrix-controlled transit.

The partner VNet is peered to the Aviatrix spoke VNet but exists outside of Aviatrix management. Traffic from the partner is steered into the Aviatrix data plane via a UDR pointing `0.0.0.0/0` to an Azure Internal Load Balancer fronting both spoke gateway NICs. The spoke then advertises the partner CIDR upstream to the transit, making it reachable across the full Aviatrix fabric.

```
Partner VNet (10.101.0.0/24)          Aviatrix Spoke VNet (10.100.0.0/23)
  VM (10.101.0.4)                        GW Primary (10.100.0.4)
  UDR: 0/0 → 10.100.1.244  ──────────▶  Azure ILB (10.100.1.244)
  VNet Peering                           GW HA     (10.100.0.36)
                                         Custom CIDR adv: 10.101.0.0/24
                                                 │
                                                 ▼
                                         Aviatrix Transit / Fabric
                                                 │
                                                 ▼
                                         Internet (optional egress)
```

## Architecture Notes

### Azure Internal Load Balancer

The ILB is created **outside of Aviatrix** — Aviatrix has no awareness of it. Key configuration requirements:

- **SKU**: Standard
- **Backend pool**: both spoke gateway primary and HA private IPs (IP-based, no NIC association required)
- **Health probe**: TCP port 443 targeting both gateways
- **Load balancing rule**: HAPort rule (`protocol = All`, `frontend_port = 0`, `backend_port = 0`) with **Floating IP enabled**
- Floating IP is mandatory — it preserves the destination IP of the original packet so the gateway processes it correctly

### VNet Peering

The peering between the partner VNet and the Aviatrix spoke VNet is created **outside of Aviatrix**. Aviatrix cannot manage peerings to VNets in a different Azure tenant, or in subscriptions where no Aviatrix cloud account has been onboarded. Both peering directions must be configured manually (or via the partner's own IaC) — Aviatrix only sees the spoke VNet side.

### Custom CIDR Advertisement

The spoke gateway is configured with `included_advertised_spoke_routes` set to the partner VNet CIDR (`10.101.0.0/24`). This replaces the default spoke advertisement and ensures the partner prefix is propagated to the transit and beyond. Without this, the partner VNet is invisible to the rest of the fabric.

### Partner UDR Requirement

The partner VNet **must** have a UDR on its subnets with:

```
Destination: 0.0.0.0/0
Next hop type: Virtual Appliance
Next hop IP: <ILB frontend IP>
```

This steers partner traffic into the Aviatrix data plane. The ILB then load-balances across the active spoke gateway.

---

## Prerequisites

| Requirement | Value |
|---|---|
| Aviatrix Controller | `controller-prd.ananableu.fr` |
| Controller version | 8.2 |
| Controller username | `admin` |
| Controller password | See your secrets store |
| Aviatrix Azure account | your Aviatrix cloud account name for Azure |
| Azure subscription ID | your Azure subscription ID |
| Azure CLI | Authenticated (`az login`) |
| Terraform | >= 1.3 |

### Terraform providers

| Provider | Version |
|---|---|
| `aviatrixsystems/aviatrix` | `~> 8.2` |
| `hashicorp/azurerm` | `~> 4.0` |
| `hashicorp/random` | `~> 3.0` |
| `hashicorp/tls` | `~> 4.0` |

---

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set aviatrix_password at minimum

terraform init
terraform apply
```

### Variables

| Variable | Default | Description |
|---|---|---|
| `aviatrix_password` | — | Aviatrix controller password (sensitive) |
| `azure_subscription_id` | — | Azure subscription ID |
| `aviatrix_azure_account` | — | Aviatrix cloud account name for Azure |
| `region` | `France Central` | Azure region |
| `spoke_gw_size` | `Standard_B2s_v2` | Spoke gateway VM size |
| `spoke_vnet_cidr` | `10.100.0.0/23` | Spoke VNet CIDR |
| `thirdparty_vnet_cidr` | `10.101.0.0/24` | Partner VNet CIDR |
| `thirdparty_vm_admin_username` | `admin-lab` | Partner VM SSH username |

### Outputs

| Output | Description |
|---|---|
| `suffix` | 6-digit random suffix used in all resource names |
| `spoke_vnet_name` | Aviatrix spoke VNet name |
| `spoke_gw_primary` | Primary spoke gateway name |
| `spoke_gw_ha_name` | HA spoke gateway name |
| `spoke_gw_primary_private_ip` | Primary gateway private IP |
| `spoke_gw_ha_private_ip` | HA gateway private IP |
| `ilb_frontend_ip` | ILB frontend static IP |
| `thirdparty_vm_private_ip` | Partner test VM private IP |
| `gatus_url` | Gatus dashboard URL (reachable from within the partner VNet) |
| `thirdparty_vm_private_key_pem` | SSH private key for partner VM (sensitive) |

### SSH to partner VM

```bash
terraform output -raw thirdparty_vm_private_key_pem > /tmp/3p-vm.pem
chmod 600 /tmp/3p-vm.pem
# SSH via a bastion or jump host with access to 10.101.0.0/24
ssh -i /tmp/3p-vm.pem admin-lab@$(terraform output -raw thirdparty_vm_private_ip)
```

### Gatus dashboard (optional — requires internet egress)

The partner VM runs Gatus in Docker, probing `https://api.ipify.org` every 5 seconds. This endpoint returns the public IP of the caller — when egress is active, Gatus will show a green status and the public egress IP, confirming that:

1. Partner VM traffic is flowing through the ILB into the Aviatrix spoke
2. The spoke is providing internet egress via single-IP SNAT

> **Note:** In this architecture, internet egress is provided directly by the spoke gateway (`single_ip_snat = true`), not by a centralized transit FireNet. The spoke gateway holds a public IP and SNATs outbound traffic on behalf of the partner VM. An alternative architecture would disable SNAT on the spoke and rely on a transit with centralized egress instead — both are valid, but this repo uses spoke-level egress.

If `single_ip_snat` is disabled or the spoke has no public IP, Gatus will show red — this is expected.

Access the dashboard at:

```
http://<thirdparty_vm_private_ip>:8080
```

---

## Cleanup

```bash
terraform destroy
```

This removes all resources: both resource groups (spoke and partner), the Aviatrix spoke VNet and gateways, the ILB, the partner VNet, VM, UDR, and peerings. The Aviatrix VPC is deleted from the controller as well.

> **Note:** If the spoke is attached to a transit gateway, detach it first (`aviatrix_spoke_transit_attachment`) before running destroy, or add the attachment resource to this configuration.

---

## AI-Assisted Deployment

This repository includes a `CLAUDE.md` file at the project root with context for Claude Code (Anthropic's AI coding assistant). It documents provider version constraints, resource naming conventions, and known Aviatrix Terraform provider gotchas so that AI-assisted modifications stay consistent with the architecture.

To use Claude Code with this repo:

```bash
# Install Claude Code
npm install -g @anthropic/claude-code

# Run in this directory
claude
```

Claude will automatically load `CLAUDE.md` and apply the documented constraints when suggesting or generating Terraform changes.
