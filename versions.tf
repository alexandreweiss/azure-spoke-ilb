terraform {
  required_version = ">= 1.3"

  required_providers {
    aviatrix = {
      source  = "aviatrixsystems/aviatrix"
      version = "~> 8.2"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aviatrix" {
  controller_ip = "controller-prd.ananableu.fr"
  username      = "admin"
  password      = var.aviatrix_password
}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}
}
