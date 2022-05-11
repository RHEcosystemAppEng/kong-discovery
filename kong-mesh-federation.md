# Federate Kong Mesh Metrics
We will federate the Kong Mesh Prometheus to the OpenShift Prometheus. We will then leverage OpenShift Monitoring to handle the aggregated metrics.

**Pending**
- [x] Define more Params in `ServiceMonitor` to dedupe metrics from Kong
- [x] Create PrometheusRules for Alerting when something goes down 
- [x] Create Dashboards 
- [ ] Scrape with mTLS enabled 
   
**TOC**
- [Install Kong Mesh](#install-kong-mesh)
- [Kuma Demo Application](#kuma-demo-application)
- [Configure Metrics](#configure-metrics)
- [Create RBAC](#create-a-clusterrolebinding-to-allow-scraping)
- [Federate Metrics to OpenShift Monitoring](#federate-metrics-to-openshift-monitoring)
- [Verify you are scraping Metrics](#verify-you-are-scraping-metrics)
- [Create Prom Rules](#create-prometheusrules)
- [Create Grafana Dashboards](#create-grafana-dashboards)
- [Clean Up](#clean-up)
- [IGNORE- Test The Federate Endpoint of Kong Prometheus](#test-the-federate-endpoint-of-kong-prometheus)
---

## Install Kong Mesh
- Download Kong Mesh
```bash
curl -L https://docs.konghq.com/mesh/installer.sh | sh -
```

a) Install control plane on kong-mesh-system namespace

```bash
./kumactl install control-plane --cni-enabled --license-path=./license | oc apply -f -
oc get pod -n kong-mesh-system
```

- Expose the service

```bash
oc expose svc/kong-mesh-control-plane -n kong-mesh-system --port http-api-server
```

- Verify the Installation

```bash
http -h `oc get route kong-mesh-control-plane -n kong-mesh-system -ojson | jq -r .spec.host`/gui/
```
output
```bash
HTTP/1.1 200 OK
accept-ranges: bytes
cache-control: private
content-length: 5962
content-type: text/html; charset=utf-8
date: Thu, 05 May 2022 15:56:54 GMT
set-cookie: 559045d469a6cf01d61b4410371a08e0=1cb25fd8a600fb50f151da51bc64109c; path=/; HttpOnly
```

## Kuma Demo application

- Apply scc of anyuid to kuma-demo
```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

- Install resources in kuma-demo ns
```bash
oc apply -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml
```

- Expose the frontend service

```bash
oc expose svc/frontend -n kuma-demo
```

- Validate the deployment

```bash
http -h `oc get route frontend -n kuma-demo -ojson | jq -r .spec.host` 
```
output
```bash
HTTP/1.1 200 OK
cache-control: max-age=3600
cache-control: private
content-length: 862
content-type: text/html; charset=UTF-8
date: Tue, 10 May 2022 11:11:11 GMT
etag: W/"251702827-862-2020-08-16T00:52:19.000Z"
last-modified: Sun, 16 Aug 2020 00:52:19 GMT
server: envoy
set-cookie: 7132be541f54d5eca6de5be20e9063c8=d64fd1cc85da2d615f07506082000ef8; path=/; HttpOnly
```

- Check sidecar injection has been performed (NS has sidecar label)
```bash
oc -n kuma-demo get po -ojson | jq '.items[] | .spec.containers[] | .name'
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

- Enable mTLS and Traffic permissions
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
EOF

# Check the frontend
oc port-forward svc/frontend -n kuma-demo 8080
```

go to [localhost:8080](http://localhost:8080)

Take down Redis in the `kong-demo` namespace (for Alert Demo)
```bash
oc scale deploy/redis-master --replicas=0 -n kuma-demo
oc delete po --force --grace-period=0 -n redis-demo -l app=redis 
```
## Configure Metrics

Note: If you have configured already the mTLS in your mesh, the default installation won't work because the Grafana
deployment has an initContainer that pulls the dashboards from a github repository. 
  
_We are not using Grafana right now so lets just turn it off_.

- Apply scc  of non-root to `kuma-metrics`
```bash
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong-mesh-metrics
```

Install metrics
```bash
./kumactl install metrics | oc apply -f -
```
- Turn off the Grafana deployment in `kong-mesh-metrics`
```
oc scale deploy/grafana -n kong-mesh-metrics --replicas=0
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


Remove the Sidecars (Still working through a solution with [sidecars](https://support.f5.com/csp/article/K03234274))

Strict mTLS is enabled, then Prometheus will need to be configured to scrape using  certificates. (WIP)
```bash
oc label ns kong-mesh-metrics kuma.io/sidecar-injection-

oc delete po -n kong-mesh-metrics --force --grace-period=0 --all
```

## Create a ClusterroleBinding to Allow Scraping
We need to allow the `prometheus-k8s` service account to scrape the `kong-mesh-metrics` resources.


Create Clusterrole
```bash
oc apply -f -<<EOF
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

Check permissions for prometheus-k8s service-account
```bash
oc auth can-i get pods --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s

oc auth can-i get endpoints --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s

oc auth can-i get services --namespace=kong-mesh-metrics --as system:serviceaccount:openshift-monitoring:prometheus-k8s 
```
output
```bash
yes
yes
yes
```

## Federate Metrics to OpenShift Monitoring
A `ServiceMonitor` is meant to tell Prometheus what metrics to scrape. Typically we use a `ServiceMonitor` or `PodMonitor` per application. Another thing that a ServiceMonitor can do is federate a prometheus instance.    
   
Create a ServiceMonitor in OpenShift Monitoring to federate Kong Metrics
```bash
oc apply -f -<<EOF
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
    scrapeTimeout: 2s # we should use 30 seconds (not a sane default)
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
```bash
oc logs prometheus-k8s-1  -n openshift-monitoring --since=1m | grep kong-mesh-metrics
```

## Verify you are scraping Metrics
Go to the OpenShift Prometheus and take a look at the targets

Go to Prom:
```bash
oc port-forward svc/prometheus-operated -n openshift-monitoring 9090 
```

open [Prometheus Targets](http://localhost:9090/targets)

do `ctrl-f` or whatever you do to search in your browser and search for `kong-federation`. May take about 30 seconds or so.

## Create PrometheusRules
Prom rules alert us when things go wrong/down. The simplest and most important prometheus rules that you can have are rules that trigger alerts when services go down and stay down. We are going to define just a few rules:  
   
1. ControlPlane Down
2. Federation Down (Kong's Prom Server is down)
3. Kong Demo Backend Down
4. Kong Demo Frontend Down
5. Kond Demo Postgres Down
6. Kong Demo Redis Down


Lets create the PromRule(s)
```bash
oc apply -f -<<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    role: alert-rules
  name: mesh-rules
  namespace: openshift-monitoring
spec:
  groups:
  - name: dataplane-rules
    rules:
    - alert: KongDemoBackendDown
      annotations:
        description: Demo Backend pod has not been ready the defined time period.
        summary: Demo Backend is down.
      expr: absent(up{app="kuma-demo-backend",job="kuma-dataplanes"} == 1)
      for: 60s
      labels:
        severity: critical
    - alert: KongDemoFrontendDown
      annotations:
        description: Demo Frontend pod has not been ready the defined time period.
        summary: Demo Frontend is down.
      expr: absent(up{app="kuma-demo-frontend",job="kuma-dataplanes"} == 1)
      for: 5s
      labels:
        severity: critical
    - alert: KongDemoDBDown
      annotations:
        description: Demo DB pod has not been ready the defined time period.
        summary: Demo DB is down.
      expr: absent(up{app="postgres",job="kuma-dataplanes"} == 1)
      for: 5s
      labels:
        severity: critical
    - alert: KongDemoCacheDown
      annotations:
        description: Demo Cache pod has not been ready the defined time period.
        summary: Demo Cache is down.
      expr: absent(up{app="redis",job="kuma-dataplanes"} == 1)
      for: 5s
      labels:
        severity: critical
  - name: mesh-rules
    rules:
    - alert: KongControlPlaneDown
      annotations:
        description: ControlPlane pod has not been ready for over a minute.
        summary: CP is down.
      expr: absent(kube_pod_container_status_ready{namespace="kong-mesh-system"})
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

We want to be alerted when a critical service goes down, so lets test the alert to make sure we will be notified when these incidents occur. To keep this brief, we will only test the `KongDemoCacheDown` rule.

**Take down the the Cache in Kuma Demo**
```bash
oc scale deploy/redis-master -n kuma-demo --replicas=0
oc delete pod --force --grace-period=0 -l app=redis -n kuma-demo
```

**Check the Alerts in the OpenShift Prometheus**
Go to Prom and wait until you see the alert for `KongDemoCacheDown`
```bash
oc port-forward svc/prometheus-operated -n openshift-monitoring 9090 
```

open [Prometheus Alerts](http://localhost:9090/alerts)

**Bring up the Kong ControlPlane and Kong Prometheus Server**
```bash
oc scale deploy/redis-master -n kuma-demo --replicas=1
```
## Create Grafana Dashboards
Since Grafana is now depricated in OCP 4.10, we are using the Grafana Operator for ease of use and configuration.

https://access.redhat.com/solutions/6615991

Create the Grafana namespace
```bash
oc apply -f -<<EOF
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: grafana
spec: {}
status: {}
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: grafana
  namespace: grafana
spec:
  targetNamespaces:
  - grafana
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/grafana-operator.grafana: ""
  name: grafana-operator
  namespace: grafana
spec:
  channel: v4
  installPlanApproval: Automatic
  name: grafana-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  startingCSV: grafana-operator.v4.4.1
EOF
```

Wait for Grafana to become ready
```bash
oc wait --for=condition=Ready --timeout=180s pod -l control-plane=controller-manager -n grafana
```

Create an instance of Grafana
```bash
oc apply -f -<<EOF
apiVersion: integreatly.org/v1alpha1
kind: Grafana
metadata:
  name: grafana
  namespace: grafana
spec:
  baseImage: grafana/grafana:8.3.3 # same as Kong's Grafana
  client:
    preferService: true
  config:
    security:
      admin_user: "admin"
      admin_password: "admin"
    users:
      viewers_can_edit: True
    log:
      mode: "console"
      level: "error"
    log.frontend:
      enabled: true
    auth:
      disable_login_form: True
      disable_signout_menu: True
    auth.anonymous:
      enabled: True
  service:
    name: "grafana-service"
    labels:
      app: "grafana"
      type: "grafana-service"
  dashboardLabelSelector:
    - matchExpressions:
        - { key: app, operator: In, values: [grafana] }
  resources:
    # Optionally specify container resources
    limits:
      cpu: 200m
      memory: 200Mi
    requests:
      cpu: 100m
      memory: 100Mi
EOF
```

*Connect Prometheus to Grafana*
- Grant `grafana-serviceaccount` cluster-monitoring-view clusterrole.
- Get Bearer Token from `grafana-serviceaccount`
- Create an instance of `GrafanaDataSource` with Bearer Token

```bash
oc apply -f -<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: null
  name: cluster-monitoring-view
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-monitoring-view
subjects:
- kind: ServiceAccount
  name: grafana-serviceaccount
  namespace: grafana
---
apiVersion: integreatly.org/v1alpha1
kind: GrafanaDataSource
metadata:
  name: prometheus-grafanadatasource
  namespace: grafana
spec:
  datasources:
    - access: proxy
      editable: true
      isDefault: true
      jsonData:
        httpHeaderName1: 'Authorization'
        timeInterval: 5s
        tlsSkipVerify: true
      name: Prometheus
      secureJsonData:
        httpHeaderValue1: 'Bearer $(oc serviceaccounts get-token grafana-serviceaccount -n grafana)'
      type: prometheus
      url: 'https://thanos-querier.openshift-monitoring.svc.cluster.local:9091'
  name: prometheus-grafanadatasource.yaml
EOF
```

Create the Dashboards
```bash
oc apply -f mesh/dashboards
```

Bring up the Grafana Instance
```bash
oc port-forward svc/grafana-service 3000 -n grafana 
```
open [Grafana](http://localhost:3000)

## Clean up

- Clean up Grafana 
```bash
oc delete grafanadashboard,grafanadatasource,grafana -n grafana --all --force --grace-period=0

oc delete subs,og,csv -n grafana --all --force --grace-period=0
```

- Uninstall Demo App
```bash
oc delete -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml

oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo

oc delete routes -n kuma-demo --force --all
oc delete mesh default
```
- Uninstall metrics

```bash
oc delete servicemonitor -n openshift-monitoring kong-federation 
oc delete prometheusrules -n openshift-monitoring mesh-rules
oc delete mesh default
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong-mesh-metrics
kumactl install metrics | oc delete -f -
oc delete pvc,po --force --grace-period=0 --all -n kong-mesh-metrics
```

- Uninstall kong mesh

```bash
kumactl install control-plane --cni-enabled --license-path=./license | oc delete -f -
sleep 3;
oc delete po,pvc --all -n kong-mesh-system --force --grace-period=0
```


## Test The Federate Endpoint of Kong Prometheus
**Ignore** Do not do this block, we are currently getting way too many metrics and need to filter down. This is effectively a DDoS attack on the Kong Prometheus right now until we deduplicate the metrics. You can try it but at your own risk. (To try you need to port-forward the Kong Prometheus to 8888)
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

## Ignore Prometheus Sidecar
insecure_skip_verify: true