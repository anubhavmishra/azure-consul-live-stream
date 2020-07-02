## Private key for the kubernetes cluster ##
resource "tls_private_key" "key" {
  algorithm = "RSA"
}

## Save the private key in the local workspace ##
resource "null_resource" "save-key" {
  triggers = {
    key = tls_private_key.key.private_key_pem
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ${path.module}/.ssh
      echo "${tls_private_key.key.private_key_pem}" > ${path.module}/.ssh/id_rsa
      chmod 0600 ${path.module}/.ssh/id_rsa
EOF
  }
}

## AKS Cluster in US East ## 
module "aks-us-east" {
  source = "./cluster"

  ssh_public_key = "${trimspace(tls_private_key.key.public_key_openssh)}"
  client_id      = var.client_id
  client_secret  = var.client_secret

  resource_group_name = "aksdemoeast1"
  location            = "East US"
  cluster_name        = "aks-east-1"
  dns_prefix          = "akseast"
}

## AKS Cluster in US West ##
module "aks-us-west" {
  source = "./cluster"

  ssh_public_key = "${trimspace(tls_private_key.key.public_key_openssh)}"
  client_id      = var.client_id
  client_secret  = var.client_secret

  resource_group_name = "aksdemowest1"
  location            = "West US 2"
  cluster_name        = "aks-west-1"
  dns_prefix          = "akswest"
}

## Outputs ##

output "aks_us_east_1_cluster_config" {
  value = module.aks-us-east.kube_config
}

output "aks_us_west_1_cluster_config" {
  value = module.aks-us-west.kube_config
}