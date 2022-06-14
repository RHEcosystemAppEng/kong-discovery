# Kong Mesh on MicroShift

With MicroShift, we get a full OpenShift 4.9 Deployment on a single node. In this document we will deploy Kong Mesh on MicroShift to validate that it performs and works as expected. This document has been tested on `Fedora 35`. This document corresponds to the [Kong Mesh](https://github.com/RHEcosystemAppEng/kong-discovery/blob/main/kong-mesh.md) doc.

**TOC**  
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Kong Mesh](#deploy-kong-mesh)
- [Deploy Kuma Demo](#deploy-kuma-demo)
- [Traffic Metrics](#traffic-metrics)
- [Tracing](#tracing)
- [Logging](#logging)
- [Fault Injection](#fault-injection)
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
oc get route kuma-control-plane -n kuma-system --template='{{ .spec.host }}'/gui
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

Enable specific Traffic Permissions
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

## Traffic Metrics

Typically we would have sidecars enabled when we install metrics. In this case on MicroShift, the `grafana` and `prometheus` pods do not come up with sidecars enabled. This time it is not because of the initContainer, which actually works, but because they both fail the liveness/readiness probes. (Step is performed after metrics installation)
```bash
oc get po -n kuma-metrics
```
output
```bash
NAME                                             READY   STATUS    RESTARTS   AGE
grafana-784fb96cbb-7jmzg                         1/2     Running   4          10m
prometheus-alertmanager-fd98dd68b-hnxbh          3/3     Running   0          10m
prometheus-kube-state-metrics-5ddc7b5dfd-p4728   2/2     Running   0          10m
prometheus-node-exporter-z4n8h                   1/1     Running   0          10m
prometheus-pushgateway-67c7db48fd-b6tw2          2/2     Running   0          10m
prometheus-server-66889f8847-gpq4p               0/3     Pending   0          10m
```

Don't take my word for it, check it out. Do not remove the sidecar-injection labels and you can see for yourself.
```bash
# grafana logs
oc logs deploy/grafana -c grafana -n kuma-metrics 

# get events -n kuma-metrics
oc get ev -n kuma-metrics --sort-by='.lastTimestamp'
```


Install Kuma Metrics
```bash
kumactl install metrics | oc apply -f -
```

Due to the problem stated above, remove the sidecars from the namespace label and roll the pods:
```bash
oc label ns/kuma-metrics kuma.io/sidecar-injection-
oc delete po -n kuma-metrics --all --force --grace-period=0
```

Wait for the demo app to be ready
```bash
oc wait --for=condition=ready pod -l app=prometheus -n kuma-metrics --timeout=240s

oc wait --for=condition=ready pod -l app=grafana -n kuma-metrics --timeout=240s
```

Configure the metrics in the existing mesh
```bash
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
  metrics:
    enabledBackend: prometheus-1
    backends:
    - name: prometheus-1
      type: prometheus
      conf:
        port: 5670
        path: /metrics
        skipMTLS: true
EOF
```
View the Grafana Dashboard to verify that it is working and metrics are being written to prometheus
```
oc port-forward svc/grafana -n kuma-metrics 3000:80
```

Open [http://localhost:3000](http://localhost:3000) in the browser. Login with username `admin` and password `admin`

## Tracing

Install kuma tracing
```bash
kumactl install tracing | oc apply -f -
```

Wait for the jaegar pod to be ready
```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/name=jaeger -n kuma-tracing --timeout=240s
```

Configure tracing in the existing mesh
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
  tracing:
    defaultBackend: jaeger-collector
    backends:
    - name: jaeger-collector
      type: zipkin
      sampling: 100.0
      conf:
        url: http://jaeger-collector.kuma-tracing:9411/api/v2/spans    
  metrics:
    enabledBackend: prometheus-1
    backends:
    - name: prometheus-1
      type: prometheus
      conf:
        port: 5670
        path: /metrics
        skipMTLS: false
EOF
```

Add TrafficTrace resource
```bash
oc apply -f -<<EOF
apiVersion: kuma.io/v1alpha1
kind: TrafficTrace
mesh: default
metadata:
  name: trace-all-traffic
spec:
  selectors:
  - match:
      kuma.io/service: '*'
  conf:
    backend: jaeger-collector # or the name of any backend defined for the mesh 
EOF
```

Update the jaeger datasource in grafana: Go to the [Grafana UI](http://localhost:3000) -> Settings -> Data Sources -> Jaeger 
and set the URL to http://jaeger-query.kuma-tracing/
```bash
oc port-forward svc/grafana -n kuma-metrics 3000:80
```

## Logging

The loki statefulset requires anyuid capabilities so the anyuid should be used
```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-logging
```

Install Logging
```bash
kumactl install logging | oc apply -f -
```

Wait for the demo app to be ready
```bash
oc wait --for=condition=ready pod -l app=loki -n kuma-logging --timeout=240s

oc wait --for=condition=ready pod -l app=promtail -n kuma-logging --timeout=240s
```

Add logging backend to the existing mesh
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
  logging:
    defaultBackend: loki
    backends:
      - name: loki
        type: file
        conf:
          path: /dev/stdout
      - name: logstash
        format: '{"start_time": "%START_TIME%", "source": "%KUMA_SOURCE_SERVICE%", "destination": "%KUMA_DESTINATION_SERVICE%", "source_address": "%KUMA_SOURCE_ADDRESS_WITHOUT_PORT%", "destination_address": "%UPSTREAM_HOST%", "duration_millis": "%DURATION%", "bytes_received": "%BYTES_RECEIVED%", "bytes_sent": "%BYTES_SENT%"}'
        type: tcp
        conf:
          address: 127.0.0.1:5000
      - name: file
        type: file
        conf:
          path: /tmp/access.log
  tracing:
    defaultBackend: jaeger-collector
    backends:
    - name: jaeger-collector
      type: zipkin
      sampling: 100.0
      conf:
        url: http://jaeger-collector.kuma-tracing:9411/api/v2/spans    
  metrics:
    enabledBackend: prometheus-1
    backends:
    - name: prometheus-1
      type: prometheus
      conf:
        port: 5670
        path: /metrics
        skipMTLS: true
EOF
```

Create the TrafficLog
```yaml
oc apply -f -<<EOF
apiVersion: kuma.io/v1alpha1
kind: TrafficLog
metadata:
  name: all-traffic
mesh: default
spec:
  # This TrafficLog policy applies all traffic in that Mesh.
  sources:
    - match:
        kuma.io/service: '*'
  destinations:
    - match:
        kuma.io/service: '*'
EOF
```

Update the loki datasource in grafana: Go to the [Grafana UI](http://localhost:3000) -> Settings -> Data Sources -> Loki 
and set the URL to http://loki.kong-mesh-logging:3100/
```bash
oc port-forward svc/grafana -n kuma-metrics 3000:80
```

## Fault Injection

FaultInjections helps testing our microservices against resiliency. There are 3 different types of failures that could be imitated in our environment:

- [Delay](https://kuma.io/docs/1.6.x/policies/fault-injection/#delay)
- [Abort](https://kuma.io/docs/1.6.x/policies/fault-injection/#abort)
- [ResponseBandwidth](https://kuma.io/docs/1.5.x/policies/fault-injection/#responsebandwidth-limit)

Create an example FaultInjection that adds a bit of everything:

```bash
oc apply -f -<<EOF
apiVersion: kuma.io/v1alpha1
kind: FaultInjection
mesh: default
metadata:
  name: example-fi
spec:
  sources:
    - match:
        kuma.io/service: frontend_kuma-demo_svc_8080
        kuma.io/protocol: http
  destinations:
    - match:
        kuma.io/service: backend_kuma-demo_svc_3001
        kuma.io/protocol: http
  conf:        
    abort:
      httpStatus: 500
      percentage: 50
    delay:
      percentage: 50.5
      value: 5s
    responseBandwidth:
      limit: 50 mbps
      percentage: 50 
EOF
```

Then browse the application and see how the website resources randomly fail to be fetched, are delayed or corrupted (due to the bandwitdh limitation). Open the demo route in the browser
```bash
oc get routes frontend -n kuma-demo --template='{{ .spec.host }}'
```

Once finished, remove the faultInjection resource

```bash
oc delete faultinjection example-fi
```

## Clean Up
Since this is just a container, we will just delete the container, restore /etc/hosts, and clean up our container runtime environment.

<details>
  <summary>Linux</summary>
  Remove files created during demo

  ```bash
  rm kubeconfig 
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
  rm kubeconfig
  ```
  Restore /etc/hosts:

  ```bash
  sudo sh -c "sed -i '/^${IP}/d' /etc/hosts"
  ```

  Remove Containers, Images and Volumes for MicroShift:

  ```bash
  sudo docker rm -f microshift
  sudo docker rmi -f quay.io/microshift/microshift-aio
  sudo docker volume rm microshift-data
  ```
</details>

## Resources
- [Kong Mesh Doc](https://github.com/RHEcosystemAppEng/kong-discovery/blob/main/kong-mesh.md)