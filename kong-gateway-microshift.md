# Install Gateway CP/DP on MicroShift
With MicroShift, we get a full OpenShift 4.9 Deployment on a single node. In this document we will deploy the Kong Gateway with the Control Plane and Data Plane in two distict namespaces on MicroShift to validate that it performs and works as expected. This document has been tested on `Fedora 35`. This document corresponds to the [Kong Gateway](https://github.com/RHEcosystemAppEng/kong-discovery/blob/main/gateway/README.md) doc.

**TOC**  
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Sample App](#deploy-sample-app)
- [Deploy Kong Gateway Control Plane](#deploy-kong-gateway-control-plane)
- [Deploy Kong Gateway Data Plane](#deploy-kong-gateway-data-plane)
- [Deploy Demo App](#deploy-demo-app)
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
sudo chmod 777 kubeconfig
```


**NOTE** - If you stop your work or want to continue later, stopping and restarting the MicroShift all-in-one container will bring some known issues with the CNI. It is recommended to `pause` and `unpause` the microshift container.
```
docker/podman pause microshift
docker/podman unpause microshift
```


Wait until all pods are in a running state, _it could take ~3 minutes for the pods to come up_
```bash
oc wait --for=condition=ready pod -l dns.operator.openshift.io/daemonset-dns=default -n openshift-dns --timeout=240s

oc get po -A
```
output
```text
NAMESPACE                       NAME                                  READY   STATUS    RESTARTS   AGE
kube-system                     kube-flannel-ds-tc7h8                 1/1     Running   0          2m33s
kubevirt-hostpath-provisioner   kubevirt-hostpath-provisioner-gzgl7   1/1     Running   0          116s
openshift-dns                   dns-default-rpbxm                     2/2     Running   0          2m33s
openshift-dns                   node-resolver-24sts                   1/1     Running   0          2m33s
openshift-ingress               router-default-6c96f6bc66-gs8gd       1/1     Running   0          2m34s
openshift-service-ca            service-ca-7bffb6f6bf-482ff           1/1     Running   0          2m37s
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
oc wait --for=condition=ready pod -l app.kubernetes.io/component=app -n kong --timeout=180s
```


Expose the Control Plane Services for `admin` and `manager`
```bash
oc expose svc/kong-kong-admin --port=kong-admin --hostname=kong-admin.microshift.io -n kong 

oc create route passthrough kong-kong-admin-tls --port=kong-admin-tls --hostname=kong-admin-tls.microshift.io --service=kong-kong-admin -n kong 

oc expose svc/kong-kong-manager --port=kong-manager --hostname=kong-manager.microshift.io -n kong

oc create route passthrough kong-kong-manager-tls --port=kong-manager-tls --hostname=kong-manager-tls.microshift.io --service=kong-kong-manager -n kong 
```

Since we are running Kubernetes in a container, we need to explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  "echo $IP kong-manager.microshift.io kong-manager-tls.microshift.io kong-admin.microshift.io kong-admin-tls.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see kong-manager, kong-manager-tls, kong-admin and kong-admin-tls
```bash
tail -1 /etc/hosts
```
output
```text
10.88.0.4 kong-manager.microshift.io kong-manager-tls.microshift.io kong-admin.microshift.io kong-admin-tls.microshift.io
```

Validate the installed version
```bash
http $(oc get route kong-kong-admin -ojsonpath='{.spec.host}' -n kong) | jq -r .version
```

output
```text
2.8.1
```

## Deploy Kong Gateway Data Plane
Similarly to the Control Plane, let's create the namespace with the secret containing the license

```bash
oc new-project kong-dp
oc create secret generic kong-enterprise-license -n kong-dp --from-file=license=license.json
```

Now, lets re-use the generated certificates to create a secret in the Data Plane namespace

```bash
kubectl create secret tls kong-cluster-cert --cert=cluster.crt --key=cluster.key -n kong-dp
```

In order for the Data Plane to be part of the Mesh we have to annotate the Namespace and add the service account to the `anyuid` scc.
```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kong-dp
oc annotate namespace kong-dp kuma.io/sidecar-injection=enabled
```

Deploy the Data Plane from the Helm Chart
```yaml
cat <<EOF> values.yaml
ingressController:
  enabled: false
env:
  database: "off"
  role: data_plane
  cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
  cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
  lua_ssl_trusted_certificate: /etc/secrets/kong-cluster-cert/tls.crt
  cluster_control_plane: kong-kong-cluster.kong.svc.cluster.local:8005
  cluster_telemetry_endpoint: kong-kong-clustertelemetry.kong.svc.cluster.local:8006
  status_listen: 0.0.0.0:8100
proxy:
  enabled: true
  type: ClusterIP
secretVolumes: 
  - kong-cluster-cert
enterprise:
  enabled: true
  license_secret: kong-enterprise-license
  portal:
    enabled: false
  rbac:
    enabled: false
  smtp:
    enabled: false
admin:
  enabled: false
manager:
  enabled: false
portal:
  enabled: false
portalapi:
  enabled: false  
EOF
helm install kong -n kong-dp kong/kong -f values.yaml
```

Wait for the data plane pod to be ready
```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/component=app -n kong-dp --timeout=180s
```
Expose the Proxy Service
```bash
oc expose svc/kong-kong-proxy -n kong-dp --port=kong-proxy --hostname=kong-proxy.microshift.io

oc create route passthrough kong-kong-proxy-tls --port=kong-proxy-tls --hostname=kong-proxy-tls.microshift.io --service=kong-kong-proxy -n kong-dp
```

Since we are running Kubernetes in a container, we need to explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  "echo $IP kong-proxy.microshift.io kong-proxy-tls.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see kong-manager, kong-manager-tls, kong-admin and kong-admin-tls
```bash
tail -1 /etc/hosts
```
output
```text
10.88.0.4 kong-proxy.microshift.io kong-proxy-tls.microshift.io
```

Check the Data Plane from the Control Plane to make sure the Data Plane is part of the cluster:
```bash
http `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/clustering/status
```

output
```text
HTTP/1.1 200 OK
access-control-allow-origin: *
cache-control: private
content-length: 170
content-type: application/json; charset=utf-8
date: Wed, 01 Jun 2022 13:57:06 GMT
deprecation: true
server: kong/2.8.1
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=5bd1a33699c17cb7a92c693484aa8ad8; path=/; HttpOnly
x-kong-admin-latency: 5

{
    "b53487b3-752b-4ac5-8a64-f75e3592ca7c": {
        "config_hash": "569818cb13aa3a90b1d72ca8225cd0cf",
        "hostname": "kong-kong-77594db78-tkmz8",
        "ip": "10.42.0.1",
        "last_seen": 1654091809
    }
}
```

Check the Data Plane Proxy to ensure that it is working:
```bash
http `oc get route -n kong-dp kong-kong-proxy --template='{{ .spec.host }}'`/
```

output
```
HTTP/1.1 404 Not Found
cache-control: private
content-length: 48
content-type: application/json; charset=utf-8
date: Wed, 01 Jun 2022 13:59:14 GMT
server: kong/2.8.1
set-cookie: 7439e381b0d6fc4efb69077feca119cd=479354089fd040bb701b8f071fefdb6c; path=/; HttpOnly
x-kong-response-latency: 0

{
    "message": "no Route matched with those values"
}
```

## Deploy Demo App


## Clean Up
<details>
  <summary>Linux</summary>
  Remove files created during demo

  ```bash
  rm values.yaml kubeconfig cluster.key cluster.crt
  ```
  Restore /etc/hosts:

  ```bash
  sudo sh -c "sed -s '/^${IP}/d' /etc/hosts" > temp_hosts
  sudo mv temp_hosts /etc/hosts
  ```
  Remove Containers, Images and Volumes for MicroShift:

  ```bash
  sudo podman rm -f microshift
  sudo podman rmi -f quay.io/microshift/microshift-aio
  sudo podman volume rm microshift-data
  ```
  
</details>

<details>
  <summary>Mac</summary>
  Remove files created during demo

  ```bash
  rm values.yaml kubeconfig cluster.key cluster.crt
  ```
  Restore /etc/hosts:

  ```bash
  sudo sh -c "sed -s '/^${IP}/d' /etc/hosts" > temp_hosts
  sudo mv temp_hosts /etc/hosts
  ```

  Remove Containers, Images and Volumes for MicroShift:

  ```bash
  sudo docker rm -f microshift
  sudo docker rmi -f quay.io/microshift/microshift-aio
  sudo docker volume rm microshift-data
  ```
</details>

## Resources
- [Kong Gateway Doc](https://github.com/RHEcosystemAppEng/kong-discovery/blob/main/gateway/README.md)