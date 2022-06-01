# Install Gateway CP/DP on MicroShift
With MicroShift, we get a full OpenShift 4.9 Deployment on a single node. In this document we will deploy the Kong Gateway with the Control Plane and Data Plane in two distict namespaces on MicroShift to validate that it performs and works as expected. This document has been tested on `Fedora 35`. This document corresponds to the [Kong Gateway](https://github.com/RHEcosystemAppEng/kong-discovery/blob/main/gateway/README.md) doc.

**TOC**  
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Kong Gateway Control Plane](#deploy-kong-gateway-control-plane)
- [Deploy Kong Gateway Data Plane](#deploy-kong-gateway-data-plane)
- [Deploy Demo App](#deploy-demo-app)
- [Configure App from Control Plane](#configure-app-from-control-plane)
- [Ingress Creation](#ingress-creation)
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
    repository: kong/kubernetes-ingress-controller
    tag: 2.3.1
image:
  repository: kong/kong-gateway
  tag: 2.8.0.0-alpine
  unifiedRepoTag: kong/kong-gateway:2.8.0.0-alpine
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
2.8.0.0-enterprise-edition
```

Configure Kong Manager Service
```bash
oc patch deploy -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"$(oc get route -n kong kong-kong-admin -ojsonpath='{.spec.host}')\" }]}]}}}}"
```

Log into Kong Manager in the browser
```
oc get routes -n kong kong-kong-manager -ojsonpath='{.spec.host}'
```

## Deploy Kong Gateway Data Plane
Similarly to the Control Plane, let's create the namespace with the secret containing the license

```bash
oc new-project kong-dp
oc create secret generic kong-enterprise-license -n kong-dp --from-file=license=license.json
```

Now, lets re-use the generated certificates to create a secret in the Data Plane namespace

```bash
oc create secret tls kong-cluster-cert --cert=cluster.crt --key=cluster.key -n kong-dp
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
image:
  repository: kong/kong-gateway
  tag: 2.8.0.0-alpine
  unifiedRepoTag: kong/kong-gateway:2.8.0.0-alpine
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

Validate `/etc/hosts` has been properly updated, expect to see kong-proxy, kong-proxy-tls
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

**NOTE** Notice that this part fails above 👆 (we should see the kong-dp-kong) this is an exploratory spike so lets just take note that it does not work as expected and move on.   


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
```bash
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

Wait for the app to be ready
```bash
oc wait --for=condition=ready pod -l app=sample -n default --timeout=240s
```

Expose the frontend service as an OpenShift route:
```bash
oc expose svc/sample -n default --port=http --hostname=sample.microshift.io
```

Since we are running Kubernetes in a container, we need to explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  "echo $IP sample.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see sample
```bash
tail -1 /etc/hosts
```

Validate the sample app deployment
```bash
http -h `oc get route sample -n default -ojson | jq -r .spec.host` 
```
output
```text
HTTP/1.0 200 OK
cache-control: private
connection: keep-alive
content-length: 17
content-type: text/html; charset=utf-8
date: Wed, 01 Jun 2022 19:15:34 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 9f28662b21dec84df02ebb0dbf99421a=d21d14562fc74578d6ec0c72e4900052; path=/; HttpOnly
```

## Configure App From Control Plane
Define a service from the Control Plane for the sample app
```bash
http `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/services name=sampleservice url='http://sample.default.svc.cluster.local:5000'
```
output
```
HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 397
content-type: application/json; charset=utf-8
date: Wed, 01 Jun 2022 19:02:48 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=3f200a7eb4664f634001ded36de03298; path=/; HttpOnly
x-kong-admin-latency: 10
x-kong-admin-request-id: pUInKj5QlBQS4nIzKDCmlE0LhbXv6IvT

{
    "ca_certificates": null,
    "client_certificate": null,
    "connect_timeout": 60000,
    "created_at": 1654110168,
    "enabled": true,
    "host": "sample.default.svc.cluster.local",
    "id": "51285acf-946a-4b50-98f1-46b954cb7e2f",
    "name": "sampleservice",
    "path": null,
    "port": 5000,
    "protocol": "http",
    "read_timeout": 60000,
    "retries": 5,
    "tags": null,
    "tls_verify": null,
    "tls_verify_depth": null,
    "updated_at": 1654110168,
    "write_timeout": 60000
}
```

Now define a route for the sample app from the Control Plane
```bash
http -v $(oc get route -n kong kong-kong-admin --template='{{ .spec.host }}')/services/sampleservice/routes name='httpbinroute' paths:='["/sample"]'
```
output
```shell
POST /services/sampleservice/routes HTTP/1.1
Accept: application/json, */*;q=0.5
Accept-Encoding: gzip, deflate
Connection: keep-alive
Content-Length: 46
Content-Type: application/json
Host: kong-admin.microshift.io
User-Agent: HTTPie/3.1.0

{
    "name": "httpbinroute",
    "paths": [
        "/sample"
    ]
}


HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 486
content-type: application/json; charset=utf-8
date: Wed, 01 Jun 2022 19:08:35 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=3f200a7eb4664f634001ded36de03298; path=/; HttpOnly
x-kong-admin-latency: 19
x-kong-admin-request-id: oRgYHkfqzLPgC1tG4K0A7UACG9ssIswT

{
    "created_at": 1654110515,
    "destinations": null,
    "headers": null,
    "hosts": null,
    "https_redirect_status_code": 426,
    "id": "728bb528-996c-41d9-99ce-fea51a593041",
    "methods": null,
    "name": "httpbinroute",
    "path_handling": "v0",
    "paths": [
        "/sample"
    ],
    "preserve_host": false,
    "protocols": [
        "http",
        "https"
    ],
    "regex_priority": 0,
    "request_buffering": true,
    "response_buffering": true,
    "service": {
        "id": "51285acf-946a-4b50-98f1-46b954cb7e2f"
    },
    "snis": null,
    "sources": null,
    "strip_path": true,
    "tags": null,
    "updated_at": 1654110515
}
```

Validate the sample app by calling through the proxy
```
http $(oc get route -n kong-dp kong-kong-proxy -ojsonpath='{.spec.host}')/sample/hello
```

output
```shell
HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 01 Jun 2022 19:37:29 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 7439e381b0d6fc4efb69077feca119cd=c7db98c21c993951f6ffbf9112653534; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 40
x-kong-upstream-latency: 1

Hello World, Kong: 2022-06-01 19:37:29.644071
```

## Ingress Creation
Create a service of type `ExternalName`
```bash
oc apply -f -<<EOF
apiVersion: v1
kind: Service
metadata:
  name: route1-ext
  namespace: default
spec:
  type: ExternalName
  externalName: httpbin.org
EOF
```

Create the Ingress resource
```bash
oc apply -f -<<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: route1
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /route1
          pathType: Prefix
          backend:
            service:
              name: route1-ext
              port:
                number: 80
EOF
```

Consume the ingress to make sure everything is working
```bash
http $(oc get route -n kong-dp kong-kong-proxy -ojsonpath='{.spec.host}')/route1/get
```

output
```bash
HTTP/1.1 200 OK
access-control-allow-credentials: true
access-control-allow-origin: *
cache-control: private
content-length: 552
content-type: application/json
date: Wed, 01 Jun 2022 19:54:52 GMT
server: gunicorn/19.9.0
set-cookie: 7439e381b0d6fc4efb69077feca119cd=c7db98c21c993951f6ffbf9112653534; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 0
x-kong-upstream-latency: 258

{
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate",
        "Forwarded": "for=10.88.0.1;host=kong-proxy.microshift.io;proto=http",
        "Host": "kong-proxy.microshift.io",
        "User-Agent": "HTTPie/3.1.0",
        "X-Amzn-Trace-Id": "Root=1-6297c40b-36eca29948f1422d1feae351",
        "X-Forwarded-Host": "kong-proxy.microshift.io",
        "X-Forwarded-Path": "/route1/get",
        "X-Forwarded-Prefix": "/route1/"
    },
    "origin": "10.88.0.1, 10.42.0.1, 99.46.157.144",
    "url": "http://kong-proxy.microshift.io/get"
}
```


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
- [Kong Gateway Doc](https://docs.google.com/document/d/122_muJ2sRPR1Qd1ajh5Oh6ogkOnevzVWhWi_gw3xh9c/edit#)