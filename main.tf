# Deploy sample app on Azure App Services in a standalone manner, no database required.
terraform {
  backend "azurerm" {
    resource_group_name  = "GitHubActions"
    storage_account_name = "githubactionsmbops"
    container_name       = "tfstate"
    key                  = "challenge.terraform.tfstate"
  }
}
# Configure the AzureRM provider (using v2.1)
provider "azurerm" {
    version         = "~>2.14.0"
    subscription_id = var.subscription_id
    features {}
}

# Provision a resource group to hold all Azure resources
resource "azurerm_resource_group" "rg" {
    name            = "${var.resource_prefix}-RG"
    location        = var.location
}

# Provision the App Service plan to host the App Service web app
resource "azurerm_app_service_plan" "asp" {
    name                = "${var.resource_prefix}-asp"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    kind                = "Windows"

    sku {
        tier = "Standard"
        size = "S1"
    }
}

# Provision the Azure App Service to host the main web site
resource "azurerm_app_service" "webapp" {
    name                = "${var.resource_prefix}-WebApp"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    app_service_plan_id = azurerm_app_service_plan.asp.id

    site_config {
        always_on           = true
        default_documents   = [
            "Default.htm",
            "Default.html",
            "hostingstart.html"
        ]
    }

    app_settings = {
        "WEBSITE_NODE_DEFAULT_VERSION"  = "10.15.2"
        "ApiUrl"                        = "/api/v1"
        "ApiUrlShoppingCart"            = "/api/v1"
        "MongoConnectionString"         = "mongodb://${var.mongodb_user}:${var.mongodb_password}@${azurerm_container_group.ACI.fqdn}:27017"
        "SqlConnectionString"           = "Server=tcp:${azurerm_sql_server.mssql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_sql_database.mssqldb.name};Persist Security Info=False;User ID=${var.mssql_user};Password=${var.mssql_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
        "productImagesUrl"              = "https://raw.githubusercontent.com/microsoft/TailwindTraders-Backend/master/Deploy/tailwindtraders-images/product-detail"
        "Personalizer__ApiKey"          = ""
        "Personalizer__Endpoint"        = ""
    }
}

# Azure SQL

resource "azurerm_storage_account" "storage" {
  name                     = replace(lower("${var.resource_prefix}-storage"), "-", "")
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_sql_server" "mssql" {
  name                         = lower("${var.resource_prefix}-SQL")
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  version                      = "12.0"
  administrator_login          = var.mssql_user
  administrator_login_password = var.mssql_password

  extended_auditing_policy {
    storage_endpoint                        = azurerm_storage_account.storage.primary_blob_endpoint
    storage_account_access_key              = azurerm_storage_account.storage.primary_access_key
    storage_account_access_key_is_secondary = true
    retention_in_days                       = 6
  }
}

resource "azurerm_sql_database" "mssqldb" {
  name                = "${var.resource_prefix}-DB"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  server_name         = azurerm_sql_server.mssql.name
}

resource "azurerm_sql_firewall_rule" "mssqlfirewall" {
  name                = "AzureAccess"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_sql_server.mssql.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Azure Container Instance : MongoDB

resource "azurerm_container_group" "ACI" {
  name                = "${var.resource_prefix}-ACI"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "public"
  dns_name_label      = "mongodb"
  os_type             = "Linux"
  
  container {
    name   = lower("${var.resource_prefix}-mongodb")
    image  = "mongo:latest"
    cpu    = "1"
    memory = "2"
    
    ports {
      port     = 27017
      protocol = "TCP"
    }

    environment_variables = {
      MONGODB_USERNAME = var.mongodb_user
      MONGODB_PASSWORD = var.mongodb_password
    }

  }

}

resource "azurerm_container_registry" "ACR" {
  name                = replace("${var.resource_prefix}-ACR", "-", "")
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
}

# Create a log analytics workspace
resource "azurerm_log_analytics_workspace" "logws" {
    name                = "${var.resource_prefix}-logws"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    sku                 = "PerGB2018"
}

# Create a log analytics solution to capture the logs from the containers on our cluster
resource "azurerm_log_analytics_solution" "logsol" {
    solution_name           = "ContainerInsights"
    location                = azurerm_resource_group.rg.location
    resource_group_name     = azurerm_resource_group.rg.name
    workspace_resource_id   = azurerm_log_analytics_workspace.logws.id
    workspace_name          = azurerm_log_analytics_workspace.logws.name

    plan {
        publisher = "Microsoft"
        product   = "OMSGallery/ContainerInsights"
    }
}


resource "azurerm_kubernetes_cluster" "AKS" {
  name                = "${var.resource_prefix}-AKS"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.resource_prefix}-aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.logws.id
      }
    }
  
  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }
}

# static IP

resource "azurerm_public_ip" "challenge5" {
  name                = "${var.resource_prefix}-staticIP"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}


# kubernetes secret with consul-federation.yaml
# helm > kubeconfig ?? 


resource "helm_release" "consul" {
  name       = "azure-eats-aks-consul"
  repository = "https://helm.releases.hashicorp.com" 
  chart      = "consul"

  values = [
    "${file("values.yaml")}"
  ]

}