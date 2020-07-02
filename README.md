# Azure Consul Live Stream

This repository contains HashiCorp Terraform configuration and scripts used in the Azure Consul Live Stream.

## Prerequisites

* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) installed.
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed.
* HashiCorp [Terraform](https://terraform.io/downloads.html) installed.
* Terraform version: `0.12.x`
* [Azure Provider](https://www.terraform.io/docs/providers/azurerm/index.html) version: `1.36.1`

### Clone the Github repository

```bash
git clone https://github.com/anubhavmishra/azure-consul-live-stream.git
```

## Tutorial

Generate Azure client id and secret.

```bash
az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/YOUR_SUBSCRIPTION_ID"
```

Expected output:

```bash
{
  "appId": "00000000-0000-0000-0000-000000000000",
  "displayName": "azure-cli-2017-06-05-10-41-15",
  "name": "http://azure-cli-2017-06-05-10-41-15",
  "password": "0000-0000-0000-0000-000000000000",
  "tenant": "00000000-0000-0000-0000-000000000000"
}
```

`appId` - Client id.
`password` - Client secret.
`tenant` - Tenant id.

Export environment variables to configure the [Azure](https://www.terraform.io/docs/providers/azurerm/index.html) Terraform provider.

```bash
export AZURE_CLIENT_ID="CLIENT_ID"
export AZURE_TENANT_ID="TENANT_ID"
export AZURE_CLIENT_SECRET="CLIENT_SECRET"
export AZURE_SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID"
export TF_VAR_client_id=${AZURE_CLIENT_ID}
export TF_VAR_client_secret=${AZURE_CLIENT_SECRET}
```

### Export Kubernetes Config for the AKS clusters

Export the kubernetes config for the US East cluster

```bash
echo "$(terraform output aks_us_east_1_cluster_config)" > kubeconfig-us-east-1.yml
```

Export the kubernetes config for the US West cluster

```bash
echo "$(terraform output aks_us_west_1_cluster_config)" > kubeconfig-us-west-1.yml
```

Validate both Kubernetes clusters

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl cluster-info
```

Expected output

```bash
Kubernetes master is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443
CoreDNS is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy
```

```bash
KUBECONFIG="./kubeconfig-us-west-1.yml" kubectl cluster-info
```

Expected output

```bash
Kubernetes master is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443
CoreDNS is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy
```

### Kubernetes

Move the Kubernetes configuration files in the `consul/` folder

``bash
cd consul/
mv ../aks/kubeconfig-us-* .
```

Deploy frontend in US East.

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl apply -f kubernetes/frontend.yaml
```

Deploy api v1 in US East.

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl apply -f kubernetes/api-v1.yaml
```

Show intentions in Consul UI

Look at logs from front end

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl logs -f frontend-x
```

Intentions from frontend -> api

Now traffic splitting between api v1 and v2.


### Traffic Splitting

Copy consul config to consul server for easy access

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl cp config/ consul-server-0:/
```

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec consul-server-0 -- consul config write /config/api-defaults.hcl
```

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec consul-server-0 -- consul config write /config/api-resolver.hcl
```

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec consul-server-0 -- consul config write /config/api-splitter-50.hcl
```

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec consul-server-0 -- consul config write /config/api-splitter-100.hcl
```

### Multi-cluster

Uncomment federation from `helm-consul-us-east-1-values.yaml`

Run 

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" helm upgrade -f helm-consul-us-east-1-values.yaml consul hashicorp/consul --wait
```

This will create a secret called `consul-federation` and show the secret.

Save the secret so we can apply to the US West cluster

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl get secret consul-federation -o yaml > consul-federation-secret.yaml
```

Apply the secret to US West cluster.

```bash
KUBECONFIG="./kubeconfig-us-west-1.yml" kubectl apply -f consul-federation-secret.yaml
```

Install consul in US West cluster


```bash
KUBECONFIG="./kubeconfig-us-west-1.yml" helm install -f helm-consul-us-west-1-values.yaml hashicorp hashicorp/consul --wait
```

we are now verify the installation

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec statefulset/consul-server -- consul members -wan
```

Apply the api-v2 application to US West

````bash
KUBECONFIG="./kubeconfig-us-west-1.yml" kubectl apply -f kubernetes/api-v2-us-west-1.yaml 
```

Change frontend yaml config to include datacenter in the upstream service.

Show frontend logs that now point to US West.

Show service failover by creating new service resolver and then deleting api v1 and v2 deployments.

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl exec consul-server-0 -- consul config write /config/api-failover-resolver.hcl
```

Next delete api v1 and v2 

```bash
KUBECONFIG="./kubeconfig-us-east-1.yml" kubectl delete deployments api-v2 api-v1
```

## Live Stream Overview

- Talk about what the overall goal of the livestream is
  - Show one cluster Kubernetes app to app communication
  - intentions
  - Layer 7 features like traffic spilitting
  - Show two clusters Kubernetes app to app communication
  - Layer 7 features like traffic splitting and fail over.
  - Won't be talking about the ACL system. Please use that in production.
- Show Terraform config and the two clusters
  - They have overalaping CIDR range
- Helm install
- When doing the consul federation secret, show the `serverConfigJSON` to the users and explain the primary gateways address.

- What are the certificate options in Consul? How is the federation secret different from the client and server certificates.