variable "resource_prefix" {
  description = "The prefix used for all resources in this example"
  default     = "Azure-Eats"
}

variable "location" {
  description = "The Azure location where all resources in this example should be created"
  default     = "northeurope"
}

variable "subscription_id" {
  description = "Azure Subscription ID to be used for billing"
}

variable "mssql_user" {
  description = "Username for Admin of MSSQL Server"
  default = "mssqladmin"
}

variable "mssql_password" {
  description = "Password for Admin of MSSQL Server"
}

variable "mongodb_user" {
  description = "Username for Admin of MongoDB"
  default = "mongodbadmin"
}

variable "mongodb_password" {
  description = "Password for Admin of MongoDB"
}

variable  "branch" {
  description = "Github Branch used for deployment"
  default = "main"
}

variable "repo_url" {
  description = "Github Repo for WebApp deployment"
  default = "https://github.com/microsoft/TailwindTraders-Website"
}
}