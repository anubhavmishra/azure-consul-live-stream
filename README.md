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

This tutorial will be using the HashiCorp learn guide [Secure Service Mesh Communication Across Kubernetes Clusters](https://learn.hashicorp.com/consul/kubernetes/mesh-gateways)
for setting up multi-cluster communication between two Kubernetes clusters running in AKS.

### Generate Azure Credentials

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

### Create AKS clusters

Create two AKS clusters in US East and US West.

```bash
cd aks
terraform apply
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

### Setup Kubernetes Config

Move the Kubernetes configuration files in the `consul/` folder

```bash
cd consul/
mv ../aks/kubeconfig-us-* .
```

Merge Kubernetes configuration

```bash
touch kubeconfig-aks-clusters
```

```bash
export KUBECONFIG="kubeconfig-aks-clusters:kubeconfig-us-east-1.yml:kubeconfig-us-west-1.yml"
```

Validate both Kubernetes clusters

```bash
kubectl cluster-info --context="aks-east-1"
```

Expected output

```bash
Kubernetes master is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443
CoreDNS is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://akseast-2c0ce53f.hcp.eastus.azmk8s.io:443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy
```

```bash
kubectl cluster-info --context="aks-west-1"
```

Expected output

```bash
Kubernetes master is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443
CoreDNS is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://akswest-fef70750.hcp.westus2.azmk8s.io:443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy
```

### Deploy Consul

Deploy Consul in US East.

```bash
helm install -f helm-consul-us-east-1-values.yaml consul hashicorp/consul --kube-context="aks-east-1" --wait
```

Watch for pods being created by using the following command.

```bash
watch -n 1 "kubectl get pods --context='aks-east-1'"
```

Check Consul members in the cluster.

```bash
kubectl --context='aks-east-1' exec statefulset/consul-server -- consul members
```

> Note: Wait until the Consul service is ready. Use `kubectl get services consul-ui --context="aks-east-1"` to check if the `EXTERNAL-IP` is set.

View Consul UI

```bash
open https://$(kubectl get services consul-ui --context="aks-east-1" -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
```

### Deploy Services

Deploy frontend in US East.

```bash
kubectl apply -f kubernetes/frontend.yaml --context="aks-east-1"
```

Deploy api v1 in US East.

```bash
kubectl apply -f kubernetes/api-v1.yaml --context="aks-east-1"
```

Open another terminal window and call the frontend service.

```bash
kubectl get services frontend --context="aks-east-1"
```

See logs from frontend service.

```bash
kubectl --context="aks-east-1" logs -f frontend-x 
```

See intentions in Consul UI

Create an intentions from frontend -> api to deny traffic.

Now we will do traffic splitting between api v1 and v2.

### Traffic Splitting

Copy consul config to consul server for easy access

```bash
kubectl --context="aks-east-1" cp config/ consul-server-0:/
```

Create service defaults.

```bash
kubectl --context="aks-east-1" exec consul-server-0 -- consul config write /config/api-defaults.hcl
```

Deploy api v2 in US East.

```bash
kubectl apply -f kubernetes/api-v2.yaml --context="aks-east-1"
```

Create service resolver.

```bash
kubectl --context="aks-east-1" exec consul-server-0 -- consul config write /config/api-resolver.hcl
```

Create service splitter that splits traffic between v1 and v2.

```bash
kubectl --context="aks-east-1" exec consul-server-0 -- consul config write /config/api-splitter-50.hcl
```

Send the traffic to v2.

```bash
kubectl --context="aks-east-1" exec consul-server-0 -- consul config write /config/api-splitter-100.hcl
```

### Multi-cluster

Uncomment federation from `helm-consul-us-east-1-values.yaml`

```bash
vim helm-consul-us-east-1-values.yaml

global:
  name: consul
  image: consul:1.8.0
  imageK8S: hashicorp/consul-k8s:0.16.0
  datacenter: us-east-1
  federation:
    enabled: true
    createFederationSecret: true
  tls:
    enabled: true
meshGateway:
 enabled: true
connectInject:
 enabled: true
ui:
 enabled: true
 service:
    enabled: true
    type: "LoadBalancer"

```

Run `helm upgrade` to update the US East cluster.

```bash
helm upgrade -f helm-consul-us-east-1-values.yaml consul hashicorp/consul --wait --kube-context="aks-east-1"
```

> Note: This command takes about 3-5 mins to complete as we will need to restart all servers
but it won't distrupt our service mesh communication.

The command will create a secret called `consul-federation`. To view
the secret run the following command. 

```bash
kubectl get secret consul-federation -o yaml 
```

View the secret in the base64 encoded string 

```bash
echo "eyJwcmltYXJ5X2RhdGFjZW50ZXIiOiJ1cy1lYXN0LTEiLCJwcmltYXJ5X2dhdGV3YXlzIjpbIjUyLjE0Ni40Mi42MDo0NDMiXX0" | base64 -d
```

Save the secret so we can apply to the US West cluster

```bash
kubectl get secret consul-federation -o yaml > consul-federation-secret.yaml
```

Open a new terminal window with US West cluster.

Apply the secret to US West cluster.

```bash
kubectl apply -f consul-federation-secret.yaml --context="aks-west-1"
```

Open the `helm-consul-us-west-1-values.yaml` file to view the US West cluster configuration.

```bash
vim helm-consul-us-west-1-values.yaml

global:
  datacenter: us-west-1
  image: consul:1.8.0
  imageK8S: hashicorp/consul-k8s:0.16.0
  tls:
    enabled: true
    caCert:
      secretName: consul-federation
      secretKey: caCert
    caKey:
      secretName: consul-federation
      secretKey: caKey
  federation:
    enabled: true
  name: consul
server:
  extraVolumes:
  - type: secret
    name: consul-federation
    items:
      - key: serverConfigJSON
        path: config.json
    load: true
connectInject:
  enabled: true
meshGateway:
  enabled: true
```

Install consul in US West cluster

```bash
helm install -f helm-consul-us-west-1-values.yaml hashicorp hashicorp/consul --wait --kube-context="aks-west-1"
```

Verify the installation

```bash
kubectl --context="aks-west-1" exec statefulset/consul-server -- consul members -wan
```

Apply the api-v2 application to US West

```bash
kubectl --context="aks-west-1" apply -f kubernetes/api-v2-us-west-1.yaml 
```

Copy consul config to consul server since the servers restarted. 

```bash
kubectl --context="aks-east-1" cp config/ consul-server-0:/
```

Show service failover by creating new service resolver and then deleting api v1 and v2 deployments.

```bash
kubectl --context="aks-east-1" exec consul-server-0 -- consul config write /config/api-failover-resolver.hcl
```

Next delete api v1 and v2 

```bash
kubectl delete deployments api-v2 api-v1 --context="aks-east-1"
```

Show frontend logs that now point to US West.

```bash
kubectl --context="aks-east-1" logs -f frontend-x 
```

Change frontend yaml config to include datacenter in the upstream service.

```bash
vim kubernetes/frontend.yaml
```

Apply the frontend deployment file to update the service in US East.

```bash
kubectl apply -f kubernetes/frontend.yaml --context="aks-east-1"
```

Show frontend logs that now point to US West.

```bash
kubectl --context="aks-east-1" logs -f frontend-x 
```

Create api v1 and v2 services

```bash
kubectl apply -f kubernetes/api-v1.yaml --context="aks-east-1"
```

```bash
kubectl apply -f kubernetes/api-v2.yaml --context="aks-east-1"
```
