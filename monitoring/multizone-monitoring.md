# Kong Mesh Multizone Monitoring

This document describes how to monitor a Multizone Kong Mesh Cluster.

Having 2 OCP clusters:

- kong-gcp:
  - Global Control Plane
  - Centralized Observability
  - Prometheus + Thanos sidecar for monitoring the GCP
- kong-zone1 (or any additional zones):
  - Remote Control Plane
  - Kubernetes Ingress Controller
  - Demo apps
  - Prometheus + Thanos sidecar

## Table of contents

- [Install Kong Mesh in Multizone](#install-kong-mesh-in-multizone)
- [Install Kubernetes Ingress Controller](#install-kubernetes-ingress-controller)
- [Deploy the demo apps](#deploy-the-demo-apps)
- [Configure Metrics in Zone1](#configure-metrics-in-zone1)
- [Configure Metrics in the Global Control Plane](#configure-metrics-in-the-global-control-plane)
- [Deploy Thanos Query](#deploy-thanos-query)
- [Configure Grafana](#configure-grafana)
- [Clean up](#clean-up)

## Install Kong Mesh in Multizone

Refer to [Install Global Control Plane](../global-control-plane.md#install-mesh-global-control-plane)
Refer to [Install Remote Control Plane](../gateway-multizone/kong-ocp.md)

## Install Kubernetes Ingress Controller

In kong-zone1 install the KIC

- Install the helm repo

```bash
helm repo add kong https://charts.konghq.com                                               
helm repo update 
```

- Create and prepare the namespace

```bash
oc new-project kong
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong
oc annotate namespace kong kuma.io/sidecar-injection=enabled
```

- Install KIC using the Helm Chart

```bash
helm install kong kong/kong -n kong \                                                      
  --set ingressController.installCRDs=false \
  --set podAnnotations."kuma\.io/mesh"=default \
  --set podAnnotations."kuma\.io/gateway"=enabled
```

- Expose the Proxy secure route

```bash
oc create route passthrough kong-kong-proxy-tls --port=kong-proxy-tls --service=kong-kong-proxy -n kong
```

- Test the endpoint

```bash
$ https --verify=false `oc get route kong-kong-proxy-tls -n kong --template='{{.spec.host}}'`              
HTTP/1.1 404 Not Found
Connection: keep-alive
Content-Length: 48
Content-Type: application/json; charset=utf-8
Date: Wed, 22 Jun 2022 14:53:03 GMT
Server: kong/2.8.1
X-Kong-Response-Latency: 0

{
    "message": "no Route matched with those values"
}
```

## Deploy the demo apps

```bash
oc create ns kuma-app                                                                                  
oc annotate namespace kuma-app kuma.io/sidecar-injection=enabled
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kuma-app
oc apply -f gateway-multizone/magnanimo.yaml -n kuma-app
oc apply -f gateway-multizone/benigno.yaml -n kuma-app
```

### Create the Ingress for the demo app

```bash
oc apply -f -<<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: magnanimo
  namespace: kuma-app
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /magnanimo
          pathType: Prefix
          backend:
            service:
              name: magnanimo
              port:
                number: 4000
EOF
```

- Validate the `magnanimo` application is working and connected to `benigno`

```bash
$ https --verify=false `oc get route kong-kong-proxy-tls -n kong --template='{{.spec.host}}'`/magnanimo/hw3
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 49
Content-Type: text/html; charset=utf-8
Date: Wed, 22 Jun 2022 14:52:17 GMT
Server: Werkzeug/1.0.1 Python/3.8.3
Via: kong/2.8.1
X-Kong-Proxy-Latency: 1
X-Kong-Upstream-Latency: 16

Hello World, Benigno - 2022-06-22 14:52:17.714041
```

## Configure Metrics in Zone1

### Deploy Prometheus in Zone1

- Create a subscription in the kong-mesh-system namespace

```bash
oc apply -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/prometheus.kong-mesh-system: ""
  name: prometheus
  namespace: kong-mesh-system
spec:
  channel: beta
  installPlanApproval: Automatic
  name: prometheus
  source: community-operators
  sourceNamespace: openshift-marketplace
  startingCSV: prometheusoperator.0.56.3
EOF
```

- Create the prometheus instance and roles

```bash
oc apply -f monitoring/multizone/prom-cluster-role.yaml
oc apply -f monitoring/multizone/prometheus.yaml
```

- Expose the thanos-sidecar endpoint as a LoadBalancer Service.

An alternative could be to use a route and TLS but by default, as it is a gRPC service
the host is not forwarded and the Openshift router can't properly forward the request so the
only solution for non-TLS endpoints is to use a LoadBalancer service.

```bash
oc expose svc/prometheus-operated --type LoadBalancer --port=10901 --name thanos-sidecar --generator="service/v2"
```

- Keep the external-ip to use it later

```bash
export ZONE_1_GRPC=`oc get svc thanos-sidecar -ojson | jq -r '.status.loadBalancer.ingress[0].hostname'`
```

- An additional validation can be done by using `grpcurl`

```bash
$ grpcurl -plaintext $ZONE_1_GRPC:10901 grpc.health.v1.Health.Check     
{
  "status": "SERVING"
}
```

### Monitor Mesh Remote Control Plane

- Create the following ServiceMonitor

```bash
oc apply -f monitoring/multizone/service-monitor.yaml
```

- Confirm the ServiceMonitor is discovered and scrapping metrics

Create a port-forward

```bash
oc port-forward svc/prometheus-operated 9090
```

In the [Prometheus UI](http://localhost:9090/targets) check the target exists and is up.
It might take a couple of minutes.

You can close the port-forward.

## Configure Metrics in the Global Control Plane

### Deploy Prometheus in Global Control Plane

- Create a subscription in the kong-mesh-system namespace

```bash
oc apply -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/prometheus.kong-mesh-system: ""
  name: prometheus
  namespace: kong-mesh-system
spec:
  channel: beta
  installPlanApproval: Automatic
  name: prometheus
  source: community-operators
  sourceNamespace: openshift-marketplace
  startingCSV: prometheusoperator.0.56.3
EOF
```

- Create the prometheus instance and roles

```bash
oc apply -f monitoring/multizone/prom-cluster-role.yaml
oc apply -f monitoring/multizone/prometheus.yaml
```

### Monitor the Mesh Global Control Plane

Similarly to what we did in Zone1 we will monitor the Control Plane

- Create the following ServiceMonitor

```bash
oc apply -f monitoring/multizone/service-monitor.yaml
```

- Confirm the ServiceMonitor is discovered and scrapping metrics

Create a port-forward

```bash
oc port-forward svc/prometheus-operated 9090
```

In the [Prometheus UI](http://localhost:9090/targets) check the target exists and is up.
It might take a couple of minutes.

You can close the port-forward.

## Deploy Thanos Query

- Create the namespace

```bash
oc create ns grafana
```

- Create the Deployment and Service that Grafana will use. Note that we're using
the ZONE_1_GRPC endpoint. Add more lines for other zones.

```bash
envsubst < monitoring/multizone/query-deployment.yaml | oc apply -f -
```

### Validation

In order to confirm that Thanos is properly connected to all the thanos-sidecars you can
porf-forward port 10902 and open the web UI.

```bash
oc port-forward svc/thanos-query 10902
```

Now open the [Thanos Query UI](http://localhost:10902) as we did for Prometheus.

- Check there is one Store for each Zone and one for the Global CP
- Check there is one Target for each Zone and one for the Global CP
- All should be UP

Once done, stop the port-forwarding

## Configure Grafana

Also in the `grafana` cluster we will configure Grafana

- Create the subscription

```bash
oc apply -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  creationT
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

- Install Grafana

```bash
oc apply -f monitoring/multizone/grafana.yaml
```

- Create the Datasource

```bash
oc apply -f monitoring/multizone/datasource.yaml
```

- Create the Dashboards

```bash
oc apply -f mesh/dashboards
```

### Validate the Grafana installation

- Login to Grafana

```bash
xdg-open https://`oc get route -n mesh-observability grafana-route --template='{{.spec.host}}'`
```

The default user/password (see the CRD) is admin/admin but you will be prompted to
change it at the first login.

- Confirm in Datasources there is a `Prometheus` datasource. Click _Save & Test_ to validate the
connectivity

- Confirm in Dashboards there is a `mesh-observability` folder containing all the
datasources.

## Clean up

### Delete Grafana and Thanos

```bash
oc delete grafana kong-grafana -n grafana
oc delete grafanadashboards,grafanadatasource --all -n grafana
oc delete -f monitoring/multizone/query-deployment.yaml
oc delete subscription grafana-operator -n grafana
oc delete ns grafana
```

### Delete Prometheus

In all the clusters where the Kong Mesh Control Plane has been installed (both Global and Remote)

```bash
oc delete -f monitoring/multizone/prometheus.yaml
oc delete -f monitoring/multizone/prom-cluster-role.yaml
oc delete subscription prometheus -n kong-mesh-system
```

Only in Remote Control Plane clusters

```bash
oc delete svc thanos-sidecar -n kong-mesh-system
```

### Delete the Kubernetes Ingress Controller

In the zone cluster:

```bash
helm uninstall kong -n kong
oc delete route kong-kong-proxy-tls
oc delete ns kong
```

### Uninstall Kong Mesh in Multizone

Refer to [Uninstall Global Control Plane](../global-control-plane.md#clean-up)