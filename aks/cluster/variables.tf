## Azure config variables ##
variable "client_id" {}

variable "client_secret" {}

variable location {
  default = "Central US"
}

## Resource group variables ##
variable resource_group_name {
  default = "aksdemo"
}


## AKS kubernetes cluster variables ##
variable cluster_name {
  default = "aksdemo1"
}

variable "node_count" {
  default = 3
}

variable "dns_prefix" {
  default = "aksdemo"
}

variable "ssh_public_key" {
}

variable "admin_username" {
  default = "demo"
}
