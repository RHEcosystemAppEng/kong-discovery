# Federate Kong Mesh Metrics
We will federate the Kong Mesh Prometheus to the OpenShift Prometheus. We will then leverage OpenShift Monitoring to handle the aggregated metrics.

**Pending**
- [x] Define more Params in `ServiceMonitor` to dedupe metrics from Kong
- [x] Create PrometheusRules for Alerting when something goes down 
- [ ] Create Dashboards (Grafana Depricated, talk to team)
   
**TOC**
- [Install Kong Mesh](#install-kong-mesh)
- [Configure Metrics](#configure-metrics)
- [Create RBAC](#create-a-clusterrolebinding-to-allow-scraping)
- [Federate Metrics to OpenShift Monitoring](#federate-metrics-to-openshift-monitoring)
- [Make sure you are scraping Metrics](#make-sure-you-are-scraping-metrics)
- [Clean Up](#clean-up)
- [IGNORE- Test The Federate Endpoint of Kong Prometheus](#test-the-federate-endpoint-of-kong-prometheus)
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


Remove the Sidecars (Still working through a solution with sidecars)
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
A `ServiceMonitor` is meant to tell Prometheus what metrics to scrape. Typically we use a `ServiceMonitor` or `PodMonitor` per application. Another thing that a ServiceMonitor can do is define a prometheus instance for federation.    
   
Create a ServiceMonitor in OpenShift Monitoring to scrape Kong Metrics
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
  - interval: 2s # we should use 30 seconds (only for demo)
    scrapeTimeout: 2s # we should use 30 seconds (only for demo)
    path: /federate
    targetPort: 9090
    port: http
    params:
      'match[]':
      - '{job=~"kuma-dataplanes"}'
      - '{job=~"kubernetes-service-endpoints",kubernetes_namespace=~"kong-mesh-system"}'
    honorLabels: true
EOF
```



Make sure OCP Prom logs are clean
```
kubectl logs prometheus-k8s-1  -n openshift-monitoring --since=1m | grep kong-mesh-metrics
```

## Make sure you are scraping Metrics

Go to the OpenShift Prometheus and try and Scrape metrics from Kong

Go to Prom:
```
kubectl  port-forward svc/prometheus-operated  -n openshift-monitoring 9090 
```

open [Prometheus Targets](http://localhost:9090/targets)

do `ctrl-f` or whatever you do to search in your browser and search for `kong-federation`

## Create PrometheusRules
Prom rules alert us when things go wrong. The simplest and most important prometheus rules that you can have are rules that trigger alerts when services go down and stay down. We are going to define two rules:  
1. Alert when ControlPlane goes down
2. Alert when Federation goes down (Kong's Prom Server is down)


Lets create the PromRule
```
kubectl apply -f -<<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    role: alert-rules
  name: mesh-rules
  namespace: openshift-monitoring
spec:
  groups:
  - name: mesh-rules
    rules:
    - alert: KongControlPlaneDown
      annotations:
        description: ControlPlane pod has not been ready for over a minute.
        summary: CP is down.
      expr: absent(kube_pod_container_status_ready{container="control-plane", endpoint="https-main", job="kube-state-metrics", namespace="kong-mesh-system",service="kube-state-metrics"})
      for: 5s
      labels:
        severity: critical
    - alert: KongMetricsDown
      annotations:
        description: Kong Metrics not being federated.
        summary: Kong Prometheus is down.
      expr: absent(kube_pod_container_status_ready{container="prometheus-server",namespace="kong-mesh-metrics"})
      for: 1m
      labels:
        severity: critical
EOF
```

We want to be alerted when a critical service goes down, so lets test the alert to make sure we will be notified when these incidents occur.

**Take down the Kong ControlPlane**
```
kubectl scale deploy -n kong-mesh-system --replicas=0 --all
kubectl delete po -n kong-mesh-system --all --force --grace-period=0
```

**Take down the Kong Prometheus Server**
```
kubectl scale deploy/prometheus-server --replicas=0 -n kong-mesh-metrics
kubectl delete po -n kong-mesh-metrics --force --grace-period=0 -l app=prometheus
```

Port-forward OpenShift Metric's Prom Service
```
kubectl  port-forward svc/prometheus-operated  -n openshift-monitoring 9090 
```
Lets check the [alerts](http://localhost:9090/alerts), this may take over a minute to two to reflect the alerts. Alerts go from pending to firing.

also, you can check the alerts by curling them
```
curl http://localhost:9090/api/v1/query\?query\=ALERTS | jq 
```

output
```
      {
        "metric": {
          "__name__": "ALERTS",
          "alertname": "KongControlPlaneDown",
          "alertstate": "firing",
          "container": "control-plane",
          "endpoint": "https-main",
          "job": "kube-state-metrics",
          "namespace": "kong-mesh-system",
          "service": "kube-state-metrics",
          "severity": "critical"
        },
        "value": [
          1651865684.46,
          "1"
        ]
      },
      {
        "metric": {
          "__name__": "ALERTS",
          "alertname": "KongMetricsDown",
          "alertstate": "firing",
          "container": "prometheus-server",
          "namespace": "kong-mesh-metrics",
          "severity": "critical"
        },
        "value": [
          1651865684.46,
          "1"
        ]
      },
```

**Bring up the Kong ControlPlane and Kong Prometheus Server**
```
kubectl scale deploy -n kong-mesh-system --replicas=1 --all

kubectl scale deploy/prometheus-server --replicas=1 -n kong-mesh-metrics
```
## Create a Grafana Dashboard 
Since Grafana is now depricated in OCP 4.10, i recommend installing the Grafana Operator for ease of use.

https://access.redhat.com/solutions/6615991

## Clean up

- Uninstall metrics

```bash
kubectl delete servicemonitor -n openshift-monitoring kong-federation 
kubectl delete prometheusrules -n openshift-monitoring mesh-rules
kubectl delete mesh default
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong-mesh-metrics
kumactl install metrics | kubectl delete -f -
```

- Uninstall kong mesh

```bash
kumactl install control-plane --cni-enabled --license-path=./license | kubectl delete -f -
```


## Test The Federate Endpoint of Kong Prometheus
**Ignore** Do not do this block, we are currently getting way too many metrics and need to filter down. This is effectively a DDoS attach on the Kong Prometheus right now until we deduplicate the metrics. You can try it but at your own risk. (To try you need to port-forward the Kong Prometheus to 8888)
```
# curl -v -G --data-urlencode 'match[]={job!=""}'  http://localhost:8888/federate

# curl -v -G --data-urlencode 'match[]={job=~".+"}'  http://localhost:8888/federate 

# curl -v -G --data-urlencode 'match[]={job=~"kubernetes-nodes-cadvisor"}'  http://localhost:8888/federate

curl -v -G --data-urlencode 'match[]={job=~"kubernetes-service-endpoints",app_kubernetes_io_instance=~"kong-mesh"}'  http://localhost:8888/federate
```

**Ignore** this block and do not copy and paste (WIP, more to come)
```
# take grafana out of the mesh
kubectl patch deploy/grafana -n kong-mesh-metrics -p '{"spec": {"template":{"metadata":{"annotations":{"kuma.io/sidecar-injection":"false"}}}} }'
```
