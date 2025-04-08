# Configure the Azure provider
terraform {
  backend "azurerm" {
    resource_group_name  = "serena-tf-rg"
    storage_account_name = "serenatfstorage0207"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}


#Azure logic app Standard

resource "azurerm_resource_group" "rg" {
  name     = "myTFResourceGroup"
  location = "eastus2"

  tags = {
    Environment = "Terraform Getting Started"
    Team = "DevOps"
  }
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "myTFVnet"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus2"
  resource_group_name = azurerm_resource_group.rg.name
}

#Create a subnet

resource "azurerm_subnet" "LA" {
  name                 = "LASubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action"]
    }
  }
}



resource "azurerm_storage_account" "example" {
  name                     = "serenatest0208serena"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}



resource "azurerm_service_plan" "example" {
  name                = "azure-functions-test-service-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type            = "Windows"
  sku_name = "WS1"
}

#Create logic app application insights


resource "azurerm_log_analytics_workspace" "mytftest" {
  name                = "mytf-test"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 90
}

resource "azurerm_application_insights" "mytfappinsights" {
  name                = "my-tf-test-appinsights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.mytftest.id
  application_type    = "web"
}

output "instrumentation_key" {
  value = azurerm_application_insights.mytfappinsights.instrumentation_key
  sensitive = true
}

output "app_id" {
  value = azurerm_application_insights.mytfappinsights.app_id
  sensitive = true
}


resource "azurerm_logic_app_standard" "example" {
  name                       = "myTFlogicapp-test0112-serena"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_service_plan.example.id
  storage_account_name       = azurerm_storage_account.example.name
  storage_account_access_key = azurerm_storage_account.example.primary_access_key
  virtual_network_subnet_id = azurerm_subnet.LA.id
  version = "~4"

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.mytfappinsights.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.mytfappinsights.connection_string
    }
}

#Create Private Endpoint

#blob

resource "azurerm_subnet" "storage" {
  name                 = "storage_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

#blob 
resource "azurerm_private_endpoint" "blob" {
  depends_on = [azurerm_logic_app_standard.example]
  name                = "blob-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage.id

  private_service_connection {
    name                           = "blob-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.example.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

#file 
resource "azurerm_private_endpoint" "file" {
  depends_on = [azurerm_logic_app_standard.example]
  name                = "file-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage.id

  private_service_connection {
    name                           = "file-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.example.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "file-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.file.id]
  }
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "file-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}


#queue 
resource "azurerm_private_endpoint" "queue" {
  depends_on = [azurerm_logic_app_standard.example]
  name                = "queue-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage.id

  private_service_connection {
    name                           = "queue-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.example.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "queue-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.queue.id]
  }
}

resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  name                  = "queue-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

#table 
resource "azurerm_private_endpoint" "table" {
  depends_on = [azurerm_logic_app_standard.example]
  name                = "table-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage.id

  private_service_connection {
    name                           = "table-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.example.id
    subresource_names              = ["table"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "table-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.table.id]
  }
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "table-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}











