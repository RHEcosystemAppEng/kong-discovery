# Install Gateway CP/DP on MicroShift
With MicroShift, we get a full OpenShift 4.9 Deployment on a single node. In this document we will deploy the Kong Gateway with the Control Plane and Data Plane in two distict namespaces on MicroShift to validate that it performs and works as expected. This document has been tested on `Fedora 35`.

**TOC**  
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Sample App](#deploy-sample-app)
- [Deploy Kong Gateway Control Plane](#deploy-kong-gateway-control-plane)
- [Clean Up](#clean-up)
- [Resources](#resources)

## Prerequisites
Before starting, make sure you have at least:
- a supported 64-bit2 CPU architecture (amd64/x86_64, arm64, or riscv64)
- a supported OS (Linux, Mac, Windows)
- 2 CPU cores
- 2GB of RAM
- 1GB of free storage space for MicroShift 

## Install MicroShift
The [installation process](https://microshift.io/docs/getting-started/#using-microshift-for-application-development) for MicroShift varies across different Operating Systems, nevertheless, a container runtime is a requirement regardless of the underlying operating system.

<details>
  <summary>Linux</summary>
  Run MicroShift ephemerally using:

  ```bash
  command -v setsebool >/dev/null 2>&1 || sudo setsebool -P container_manage_cgroup true
  sudo podman run -d --rm --name microshift --privileged -v microshift-data:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
  ```

  Access the MicroShift environment on using the `oc` client installed on the host:

  ```bash
  sudo podman cp microshift:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig
  oc get all -A --kubeconfig ./kubeconfig
  ```
</details>

<details>
  <summary>Mac</summary>
  Run MicroShift ephemerally using:

  ```bash
  docker run -d --rm --name microshift --privileged -v microshift-data:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
  ```

  Access the MicroShift environment on using the `oc` client installed on the host:

  ```bash
  docker cp microshift:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig
  oc get all -A --kubeconfig ./kubeconfig
  ```
</details>

Set the active `kubeconfig` to the local kubeconfig
```
export KUBECONFIG=./kubeconfig
```


**NOTE** - If you stop your work or want to continue later, stopping and restarting the MicroShift all-in-one container will bring some known issues with the CNI. It is recommended to `pause` and `unpause` the microshift container.
```
docker/podman pause microshift
docker/podman unpause microshift
```

## Deploy Sample App
We start by deploying a sample app that we will use with Kong Gateway.
```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sample
  namespace: default
  labels:
    app: sample
spec:
  type: ClusterIP
  ports:
  - port: 5000
    name: http
  selector:
    app: sample
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sample
  template:
    metadata:
      labels:
        app: sample
        version: v1
    spec:
      containers:
      - name: sample
        image: claudioacquaviva/sampleapp
        ports:
        - containerPort: 5000
EOF
```
output
```
service/sample created
deployment.apps/sample created
```

wait for app to be ready
```
kubectl wait --for=condition=ready pod -l app=sample --timeout=120s
```
output
```
pod/sample-76db6bb547-klztz condition met
```

## Deploy Kong Gateway Control Plane
As usual, create the namespace and the secret with the license.

```bash
oc new-project kong
oc create secret generic kong-enterprise-license --from-file=license=license.json -n kong
```

Generate a certificate that will be used to expose the TLS. Use that certificate to create a secret

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong 
```

Deploy the Control Plane from the Helm Chart
```yaml
cat <<EOF> values.yaml
ingressController:
  enabled: true
  installCRDs: false
  image:
    tag: 2.3.1
image:
  tag: 2.8.0.0-alpine
env:
  database: postgres
  role: control_plane
  cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
  cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
cluster:
  enabled: true
  tls:
    enabled: true
    servicePort: 8005
    containerPort: 8005
clustertelemetry:
  enabled: true
  tls:
    enabled: true
    servicePort: 8006
    containerPort: 8006
proxy:
  enabled: true
  type: ClusterIP
secretVolumes: 
  - kong-cluster-cert
admin:
  enabled: true
  http:
    enabled: true
  type: ClusterIP
enterprise:
  enabled: true
  license_secret: kong-enterprise-license
  portal:
    enabled: false
  rbac:
    enabled: false
  smtp:
    enabled: false
manager:
  enabled: true
  type: ClusterIP
postgresql:
  enabled: true
  auth:
    username: kong
    password: kong
    database: kong
EOF
helm install kong -n kong kong/kong -f values.yaml
```

Wait for the control plane pod to be ready
```
oc wait --for=condition=ready --timeout=90s pod -l app=ingress-kong -n kong
```


Expose the Control Plane Services for `admin` and `manager`
```bash
oc expose svc/kong-kong-admin --port=kong-admin --hostname=kong-admin.microshift.io -n kong 
oc expose svc/kong-kong-manager --port=kong-manager --hostname=kong-manager.microshift.io -n kong
```

Since we are running Kubernetes in a container, we need to explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  'echo $IP kong-manager.microshift.io kong-admin.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see kong-manager and kong-admin
```bash
tail -1 /etc/hosts
```

Validate the installed version
```bash
http $(oc get route kong-kong-admin -ojsonpath='{.spec.host}')
```

output
```text

```

## Clean Up
<details>
  <summary>Linux</summary>
  Restore `/etc/hosts`:
  
  ```bash
  sudo sh -c "sed -s '/^${IP}/d' /etc/hosts" > temp_hosts
  sudo mv temp_hosts /etc/hosts
  ```
  Prune Docker if you don't have anything important running:

  ```bash
  sudo podman rm -f microshift
  sudo podman rmi -f quay.io/microshift/microshift-aio
  sudo podman volume rm microshift-data
  ```
</details>

<details>
  <summary>Mac</summary>
  Prune Docker if you don't have anything important running:

  ```bash
  sudo docker rm -f microshift
  sudo docker rmi -f quay.io/microshift/microshift-aio
  sudo docker volume rm microshift-data
  ```
</details>

## Resources
- [Kong Gateway Installation](https://docs.konghq.com/gateway/latest/install-and-run/kubernetes/)