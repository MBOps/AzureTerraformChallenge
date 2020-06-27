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

###### Challenge4 ##########

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
    node_count = 2
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

###### Challenge5 ##########


# static IP

resource "azurerm_public_ip" "staticIP" {
  name                = "${var.resource_prefix}-staticIP"
  resource_group_name = azurerm_kubernetes_cluster.AKS.node_resource_group
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}


provider "kubernetes" {
  load_config_file       = "false"
    host = azurerm_kubernetes_cluster.AKS.kube_config.0.host

    client_certificate     = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.cluster_ca_certificate)
}

# resource "kubernetes_namespace" "example" {
#   metadata {
#     name = "my-first-namespace"
#   }
# }

# kubernetes secret with consul-federation.yaml

resource "kubernetes_secret" "consul-connect-secret" {
  metadata {
    name = "consul-connect-auth"
  }

  data = {
    caCert = LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM3akNDQXBTZ0F3SUJBZ0lSQU9MWE9YNThIbFcwRmNRdlArakYycHd3Q2dZSUtvWkl6ajBFQXdJd2dia3gKQ3pBSkJnTlZCQVlUQWxWVE1Rc3dDUVlEVlFRSUV3SkRRVEVXTUJRR0ExVUVCeE1OVTJGdUlFWnlZVzVqYVhOagpiekVhTUJnR0ExVUVDUk1STVRBeElGTmxZMjl1WkNCVGRISmxaWFF4RGpBTUJnTlZCQkVUQlRrME1UQTFNUmN3CkZRWURWUVFLRXc1SVlYTm9hVU52Y25BZ1NXNWpMakZBTUQ0R0ExVUVBeE0zUTI5dWMzVnNJRUZuWlc1MElFTkIKSURNd01UVXlNekF6TmprNU1EUTRORFkzTXpnM05EUTRNemM0T1RJeU1EUTBOREl6TWpNME9EQWVGdzB5TURBMgpNalV3T1RJek1EZGFGdzB5TlRBMk1qUXdPVEl6TURkYU1JRzVNUXN3Q1FZRFZRUUdFd0pWVXpFTE1Ba0dBMVVFCkNCTUNRMEV4RmpBVUJnTlZCQWNURFZOaGJpQkdjbUZ1WTJselkyOHhHakFZQmdOVkJBa1RFVEV3TVNCVFpXTnYKYm1RZ1UzUnlaV1YwTVE0d0RBWURWUVFSRXdVNU5ERXdOVEVYTUJVR0ExVUVDaE1PU0dGemFHbERiM0p3SUVsdQpZeTR4UURBK0JnTlZCQU1UTjBOdmJuTjFiQ0JCWjJWdWRDQkRRU0F6TURFMU1qTXdNelk1T1RBME9EUTJOek00Ck56UTBPRE0zT0RreU1qQTBORFF5TXpJek5EZ3dXVEFUQmdjcWhrak9QUUlCQmdncWhrak9QUU1CQndOQ0FBUmoKYkI1QUlERGJKcUljZ2xSZnhWTGxpVDA5b3pHUnkrY3o4Y2RWaFFFaXJBRjBPWUtoUXJmUjJodHZGYjJlcWhvSApZcVBQanBLRi90cWhsNmxteHdMSm8zc3dlVEFPQmdOVkhROEJBZjhFQkFNQ0FZWXdEd1lEVlIwVEFRSC9CQVV3CkF3RUIvekFwQmdOVkhRNEVJZ1FncW1mNkkxbHg1ZVFYV0t5RkZvL2dVRWxFZnYzMmE1SUowN2gvMUZmeHNDSXcKS3dZRFZSMGpCQ1F3SW9BZ3FtZjZJMWx4NWVRWFdLeUZGby9nVUVsRWZ2MzJhNUlKMDdoLzFGZnhzQ0l3Q2dZSQpLb1pJemowRUF3SURTQUF3UlFJZ0tieTdBOVE4elhTaTFTak9mdit5eFFEK3RZbHpHZnhBOFBLVkhneTQ4YUVDCklRRFl2bk45ZmVvZkplRUhES0VaTmdFa1VuRHJpZnMyeGsxNnlFUmF0V0Uwd1E9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
    caKey = LS0tLS1CRUdJTiBFQyBQUklWQVRFIEtFWS0tLS0tCk1IY0NBUUVFSUlkcGQ0WUJqZTFPaXE0YzBYaFU0VWxRcmpOVHF5enFLQ2UxUTVNRGxHZHpvQW9HQ0NxR1NNNDkKQXdFSG9VUURRZ0FFWTJ3ZVFDQXcyeWFpSElKVVg4VlM1WWs5UGFNeGtjdm5NL0hIVllVQklxd0JkRG1Db1VLMwowZG9iYnhXOW5xb2FCMktqejQ2U2hmN2FvWmVwWnNjQ3lRPT0KLS0tLS1FTkQgRUMgUFJJVkFURSBLRVktLS0tLQo=
    gossipEncryptionKey = eGNJR0NVVXJvWHNsVUs0dUwrUHI2eUFVYU5uS1ZKekhPdXVyeFUrTkN1TT0=
    replicationToken = NzliZmViMjgtNDM1ZS1hMGE1LTEwNWEtY2Q5OWVkYWNkZmVh
    serverConfigJSON = eyJwcmltYXJ5X2RhdGFjZW50ZXIiOiJkYzEiLCJwcmltYXJ5X2dhdGV3YXlzIjpbIjUxLjEzNy4yMTQuMjQ2OjQ0MyJdfQ==
  }
}

# kubernetes service points at selectors app=consul and component=mesh-gateway

resource "kubernetes_service" "consul" {
  metadata {
    name = "consul-connect-service"
  }
  spec {
    selector = {
      app = "consul"
      component = "mesh-gateway"
    }
    load_balancer_ip = azurerm_public_ip.staticIP.ip_address
    port {
      port        = 8302
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

# helm > kubeconfig ?? 

provider "helm" {
  kubernetes {
    load_config_file       = "false"
    host = azurerm_kubernetes_cluster.AKS.kube_config.0.host

    client_certificate     = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.AKS.kube_config.0.cluster_ca_certificate)
  }
}


resource "helm_release" "consul" {
  name       = "azure-eats-aks-consul"
  repository = "https://helm.releases.hashicorp.com" 
  chart      = "consul"

  values = [
    "${file("values.yaml")}"
  ]

}

## catalog syncing between K8s and Consul??? 
#
#/ # consul catalog services
#consul
#mesh-gateway


##Could be used for service account that needed to be added manually?
# resource "kubernetes_service_account" "example" {
#   metadata {
#     name = "terraform-example"
#   }
#   secret {
#     name = "${kubernetes_secret.example.metadata.0.name}"
#   }
# }