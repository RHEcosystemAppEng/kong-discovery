# Federate Kong Mesh Metrics
in this document, we will federate the Kong Mesh Prometheus to the OpenShift Prometheus. We will then leverage OpenShift Monitoring to handle Kong Mesh metrics.

**Pending**
- [ ] Define more Params in `ServiceMonitor` to improve flow of data
- [ ] Reduce Prometheus Metrics Usage with relabeling
- [ ] Create PrometheusRules for Alerting when something goes down 
- [ ] Create Dashboards    
   
**TOC**
- [Install Kong Mesh](#install-kong-mesh)
- [Configure Metrics](#configure-metrics)
- [Create RBAC](#create-a-clusterrolebinding-to-allow-scraping)
- [Federate Metrics to OpenShift Monitoring](#federate-metrics-to-openshift-monitoring)
- [IGNORE- Test The Federate Endpoint of Kong Prometheus](#test-the-federate-endpoint-of-kong-prometheus)
- [Make sure you are scraping Metrics](#make-sure-you-are-scraping-metrics)
- [Clean Up](#clean-up)
---
## Install Kong Mesh
- Download Kong Mesh
```
curl -L https://docs.konghq.com/mesh/installer.sh | sh -
```

a) Install control plane on kong-mesh-system namespace

```{bash}
./kumactl install control-plane --cni-enabled --license-path=./license | oc apply -f -
oc get pod -n kong-mesh-system
```

- Expose the service

```{bash}
oc expose svc/kong-mesh-control-plane -n kong-mesh-system --port http-api-server
```

- Verify the Installation

```{bash}
http -h `oc get route kong-mesh-control-plane -n kong-mesh-system -ojson | jq -r .spec.host`/gui/
```
output
```
HTTP/1.1 200 OK
accept-ranges: bytes
cache-control: private
content-length: 5962
content-type: text/html; charset=utf-8
date: Thu, 05 May 2022 15:56:54 GMT
set-cookie: 559045d469a6cf01d61b4410371a08e0=1cb25fd8a600fb50f151da51bc64109c; path=/; HttpOnly
```

## Configure Metrics

Note: If you have configured already the mTLS in your mesh, the default installation won't work because the Grafana
deployment has an initContainer that pulls the dashboards from a github repository. )
  
_We are not using Grafana right now so lets just turn it off. We will worry about it when we are building dashboards_.

- Apply scc  of non-root to ```kuma-metrics```
```
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong-mesh-metrics
```

Install metrics
```
./kumactl install metrics | kubectl apply -f -
```
- Turn off the Grafana deployment in `kong-mesh-metrics`
```
kubectl scale deploy/grafana -n kong-mesh-metrics --replicas=0
```

**Ignore** this block and do not copy and paste (WIP, more to come)
```
# take grafana out of the mesh
kubectl patch deploy/grafana -n kong-mesh-metrics -p '{"spec": {"template":{"metadata":{"annotations":{"kuma.io/sidecar-injection":"false"}}}} }'
```

Configure the metrics in the existing mesh

```{bash}
kubectl apply -f -<<EOF
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
        skipMTLS: false
EOF
```


Remove the Sidecars (Still working through a more robust)
```
kubectl label ns kong-mesh-metrics kuma.io/sidecar-injection-

kubectl delete po -n kong-mesh-metrics --force --grace-period=0 --all
```

## Create a ClusterroleBinding to Allow Scraping
We need to allow the `prometheus-k8s` service account to scrape the `kong-mesh-metrics` resources


Create Clusterrole
```
kubectl apply -f -<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  creationTimestamp: null
  name: kong-prom
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - pods/status
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: kong-prom-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kong-prom
subjects:
- kind: ServiceAccount
  name: prometheus-k8s
  namespace: openshift-monitoring
EOF
```

Check Perms
```
k auth can-i get pods --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s

k auth can-i get endpoints --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s

k auth can-i get services --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s 
```


## Federate Metrics to OpenShift Monitoring
Create a ServiceMonitor in OpenShift Monitoring to scrape from Kong
```
kubectl apply -f -<<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kong-federation
  namespace: openshift-monitoring
  labels:
    app: kong-mesh
spec:
  jobLabel: exporter-kong-mesh
  namespaceSelector:
    matchNames:
    - kong-mesh-metrics
  selector:
    matchLabels:
      app: prometheus
      component: server
  endpoints:
  - interval: 15s
    scrapeTimeout: 15s
    path: /federate
    targetPort: 9090
    port: http
    params:
      'match[]':
      - '{job=~"kuma-dataplanes"}'
      - '{job=~"kubernetes-nodes-cadvisor"}'
    honorLabels: true
EOF
```



Make sure logs are clean
```
k logs prometheus-k8s-1  -n openshift-monitoring --since=1m | grep kong-mesh-metrics
```

## Test The Federate Endpoint of Kong Prometheus
**Ignore** Do not do this block, we are currently getting way too many metrics and need to filter down. This is effectively a DDoS attach on the Kong Prometheus right now until we filter down the metrics. You can try it but at your own risk. (To try you need to port-forward the Kong Prometheus to 8888)
```
# curl -v -G --data-urlencode 'match[]={job!=""}'  http://localhost:8888/federate

# curl -v -G --data-urlencode 'match[]={job=~".+"}'  http://localhost:8888/federate 

curl -v -G --data-urlencode 'match[]={job=~"kubernetes-nodes-cadvisor"}'  http://localhost:8888/federate
```

## Make sure you are scraping Metrics

Go to the OpenShift Prometheus and try and Scrape metrics from Kong

Go to Prom:
```
kubectl  port-forward svc/prometheus-operated  -n openshift-monitoring 9090 
```

open [prometheus locally](http://localhost:9090)

Click *Targets* on the top Menu Bar

do `ctrl-f` or whatever you do to search in your browser and search for `kong-federation`


## Clean up

- Uninstall metrics

```bash
kubectl delete servicemonitor -n openshift-monitoring kong-federation 
kubectl delete mesh default
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong-mesh-metrics
kumactl install metrics | kubectl delete -f -
```

- Uninstall kong mesh

```bash
kumactl install control-plane --cni-enabled --license-path=./license | kubectl delete -f -
```
