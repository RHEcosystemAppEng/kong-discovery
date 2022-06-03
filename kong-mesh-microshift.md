# Kong Mesh on MicroShift
With MicroShift, we get a full OpenShift 4.9 Deployment on a single node. In this document we will deploy Kong Mesh on MicroShift to validate that it performs and works as expected. This document has been tested on `Fedora 35`. This document corresponds to the [Kong Gateway](https://docs.google.com/document/d/122_muJ2sRPR1Qd1ajh5Oh6ogkOnevzVWhWi_gw3xh9c/edit#) doc.

**TOC**  
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Kong Mesh](#deploy-kong-mesh)
- [Deploy Kuma Demo](#deploy-kuma-demo)
- [Configure Sample App from Control Plane](#configure-sample-app-from-control-plane)
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
- httpie, jq, helm3

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

## Deploy Kong Mesh
Download `kumactl`. At the time of this demo there are problems with downloading `kumactl` from the `installer.sh` script.   

<details>
  <summary>Fedora/CentOS</summary>

  ```bash
  wget -O kumactl.tar.gz https://download.konghq.com/mesh-alpine/kuma-1.6.0-centos-amd64.tar.gz

  tar -zxvf kumactl.tar.gz

  sudo mv kuma-1*/bin/kumactl /usr/local/bin/

  rm -rf kuma-1*

  rm kumactl.tar.gz

  kumactl version
  ```

  output
  ```bash
  Client: Kuma 1.6.0
  ```
</details>


<details>
  <summary>Mac</summary>

  ```bash
  wget -O kumactl.tar.gz https://download.konghq.com/mesh-alpine/kuma-1.6.0-darwin-amd64.tar.gz

  tar -zxvf kumactl.tar.gz

  sudo mv kuma-1*/bin/kumactl /usr/local/bin/

  rm -rf kuma-1*

  rm kumactl.tar.gz

  kumactl version
  ```

  output
  ```bash
  Client: Kuma 1.6.0
  ```
</details>

Install control plane in `kuma-system` namespace.

```bash
kumactl install control-plane --cni-enabled | oc apply -f -
oc get pod -n kuma-system
```

Wait for the control plane pod to be ready
```
oc wait --for=condition=ready pod -l app.kubernetes.io/instance=kuma,app.kubernetes.io/name=kuma -n kuma-system
```

Expose the Control Plane Service
```bash
oc expose svc/kuma-control-plane --port=http-api-server --hostname=kuma-control-plane.microshift.io -n kuma-system 
```

Explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  "echo $IP kuma-control-plane.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see kuma-control-plane.microshift.io
```bash
tail -1 /etc/hosts
```
output
```text
10.88.0.2 kuma-control-plane.microshift.io
```

Validate the installed version
```bash
http $(oc get route kuma-control-plane -ojsonpath='{.spec.host}' -n kuma-system) | jq .version
```

output
```text
1.6.0
```

Visit the Control Plane UI in the Browser
```
oc get route kuma-control-plane -n kuma-system --template='{{ .spec.host }}'
```


## Deploy Kuma Demo
In case of Kuma Demo, one of the component requires root access therefore we use anyuid instead of nonroot permission.  

Apply scc of anyuid to kuma-demo  
```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

Deploy the demo app in the `kuma-demo` ns
```bash
oc apply -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml
```

Wait for the demo app to be ready
```bash
oc wait --for=condition=ready pod -l app=kuma-demo-frontend -n kuma-demo --timeout=240s

oc wait --for=condition=ready pod -l app=kuma-demo-backend -n kuma-demo --timeout=240s

oc wait --for=condition=ready pod -l app=postgres -n kuma-demo --timeout=240s

oc wait --for=condition=ready pod -l app=redis -n kuma-demo --timeout=240s
```

Expose the frontend service as an OpenShift route:
```bash
oc expose svc/frontend --port=http --hostname=frontend.microshift.io -n kuma-demo
```

Explain to our local node how to resolve requests to our routes:
```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
sudo sh -c  "echo $IP frontend.microshift.io >> /etc/hosts"
```

Validate `/etc/hosts` has been properly updated, expect to see frontend.microshift.io
```bash
tail -1 /etc/hosts
```

Validate the sample app deployment
```bash
http -h `oc get route frontend -n kuma-demo -ojson | jq -r .spec.host` 
```
output
```text
HTTP/1.1 200 OK
cache-control: max-age=3600
cache-control: private
content-length: 862
content-type: text/html; charset=UTF-8
date: Fri, 03 Jun 2022 16:19:55 GMT
etag: W/"2636989-862-2020-08-16T00:52:19.000Z"
last-modified: Sun, 16 Aug 2020 00:52:19 GMT
server: ecstatic-3.3.2
set-cookie: 7132be541f54d5eca6de5be20e9063c8=ddb0616062b2172f75a417f6f266575c; path=/; HttpOnly
```

The demo app includes the kuma.io/sidecar-injection label enabled on the kuma-demo namespace
```bash
oc get ns kuma-demo -ojsonpath='{ .metadata.annotations.kuma\.io/sidecar-injection }'
```
output
```bash
enabled
```

Check sidecar injection has been performed.
```bash
oc -n kuma-demo get po -ojson | jq '.items[] | .spec.containers[] | .name '
```
output
```bash
"kuma-fe"
"kuma-sidecar"
"kuma-be"
"kuma-sidecar"
"master"
"kuma-sidecar"
"master"
"kuma-sidecar"
```

Enable mTLS
```yaml
oc apply -f -<<EOF
apiVersion: kuma.io/v1alpha1
kind: Mesh
metadata:
  name: default
spec:
  mtls:
    enabledBackend: ca-1
    backends:
    - name: ca-1
      type: builtin
EOF
```
Delete the default traffic permission
```bash
oc delete trafficpermission allow-all-default 
```

Enable Traffic Permissions
```yaml
oc apply -f -<<EOF
apiVersion: kuma.io/v1alpha1
kind: TrafficPermission
mesh: default
metadata:
  namespace: kuma-demo
  name: frontend-to-backend
spec:
  sources:
  - match:
      kuma.io/service: frontend_kuma-demo_svc_8080
  destinations:
  - match:
      kuma.io/service: backend_kuma-demo_svc_3001
---
apiVersion: kuma.io/v1alpha1
kind: TrafficPermission
mesh: default
metadata:
  namespace: kuma-demo
  name: backend-to-postgres
spec:
  sources:
  - match:
      kuma.io/service: backend_kuma-demo_svc_3001
  destinations:
  - match:
      kuma.io/service: postgres_kuma-demo_svc_5432
---
apiVersion: kuma.io/v1alpha1
kind: TrafficPermission
mesh: default
metadata:
  namespace: kuma-demo
  name: backend-to-redis
spec:
  sources:
  - match:
      kuma.io/service: backend_kuma-demo_svc_3001
  destinations:
  - match:
      kuma.io/service: redis_kuma-demo_svc_6379
EOF
```
output
```bash
trafficpermission.kuma.io/frontend-to-backend created
trafficpermission.kuma.io/backend-to-postgres created
trafficpermission.kuma.io/backend-to-redis created
```

Visit the Control Plane UI in the Browser
```
oc get route kuma-control-plane -n kuma-system --template='{{ .spec.host }}'/gui/#/meshes/default
```
Search for MTLS in the page, you should see:
```bash
builtin ca-1
```

## Configure Sample App From Control Plane
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

Validate the sample app by calling through Data Plane Proxy
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
Now, lets use the ingress.   
   
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