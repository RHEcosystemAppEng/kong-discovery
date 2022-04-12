- Download Kong Mesh
```
curl -L https://docs.konghq.com/mesh/installer.sh | sh -
```

- Install control plane on kong-mesh-system namespace

```
cd kong-mesh-1.6.0/bin
./kumactl install control-plane --cni-enabled --license-path=./license | oc apply -f -
oc get pod -n kong-mesh-system
```

- Using the internal registry (avoid docker.io)

```bash
KONG_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')/kong-image-registry
./kong-mesh-1.6.0/bin/kumactl install control-plane --dataplane-registry=$KONG_REGISTRY --control-plane-registry=$KONG_REGISTRY --cni-enabled --license-path=./license.json  | kubectl apply -f -
```

- Expose the service

```{bash}
oc expose svc/kong-mesh-control-plane -n kong-mesh-system
```

- Verify the Installation

```{bash}
$ http -h `oc get route kong-mesh-control-plane -n kong-mesh-system -ojson | jq -r .spec.host`/gui/
HTTP/1.1 200 OK
cache-control: private
content-length: 295
content-type: application/json
date: Tue, 05 Apr 2022 14:54:17 GMT
set-cookie: 559045d469a6cf01d61b4410371a08e0=35991f4fa47508ce861e82fa7d63d40a; path=/; HttpOnly
```

## Kuma Demo application

- Apply scc of anyuid to kuma-demo
```
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

- Clone the demo repo
```
git clone https://github.com/kumahq/kuma-demo.git
```

- Install resources on kuma-demo ns
```
kubectl apply -f kubernetes/kuma-demo-aio.yaml
```

- Expose the service

```{bash}
oc expose svc/frontend -n kuma-demo
```

- Validate the deployment

```{bash}
$ http -h `oc get route frontend -n kuma-demo -ojson | jq -r .spec.host` 
HTTP/1.1 200 OK
```

- Check sidecar injection has been performed
```
$ kubectl get po -ojson | jq '.items[] | .spec.containers[] | .name '
"kuma-fe"
"kuma-sidecar"
"kuma-be"
"kuma-sidecar"
"master"
"kuma-sidecar"
"master"
"kuma-sidecar"
```

- Enable MTls and Traffic permissions
```
kubectl apply -f mesh/mtls.yaml
kubectl apply -f mesh/demo/traffic-permissions.yaml
```

## Traffic metrics

- Apply scc  of non-root to ```kuma-metrics```
```
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong-mesh-metrics
#oc adm policy add-scc-to-group node-exporter system:serviceaccounts:kong-mesh-metrics
```

```
./kumactl install metrics | kubectl apply -f -
```

- Patch to use registry images

```
# scale down to 0
for d in grafana prometheus-pushgateway prometheus-alertmanager prometheus-server
do 
  oc scale deployment/$d --replicas=0
done

# grafana
kubectl patch deployment/grafana -n kong-mesh-metrics --type=json -p "[{\"op\": \"remove\", \"path\": \"/spec/template/spec/initContainers\"}]"
kubectl patch deployment/grafana -n kong-mesh-metrics -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"grafana\", \"image\": \"$KONG_REGISTRY/grafana:8.3.3-kong\"}]}}}}"

# prometheuses
kubectl patch deployment/prometheus-alertmanager -n kong-mesh-metrics -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"prometheus-alertmanager\", \"image\": \"$KONG_REGISTRY/alertmanager:v0.23.0\"},{\"name\": \"prometheus-alertmanager-configmap-reload\", \"image\": \"$KONG_REGISTRY/configmap-reload:v0.6.1\"}]}}}}"
kubectl patch deployment/prometheus-pushgateway -n kong-mesh-metrics -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"prometheus-pushgateway\", \"image\": \"$KONG_REGISTRY/pushgateway:v1.4.2\"}]}}}}"
kubectl patch deployment/prometheus-server -n kong-mesh-metrics -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"prometheus-server\", \"image\": \"$KONG_REGISTRY/prometheus:v2.32.1\"},{\"name\": \"prometheus-server-configmap-reload\", \"image\": \"$KONG_REGISTRY/configmap-reload:v0.6.1\"}]}}}}"

# scale down back up
for d in grafana prometheus-pushgateway prometheus-alertmanager prometheus-server
do 
  oc scale deployment/$d --replicas=1
done
```

Configure the metrics in the existing mesh

```{bash}
kubectl apply -f mesh/metrics/mesh.yaml
```

Allow traffic from Grafana to Prometheus Server and from Prometheus server to data plane proxy metrics and other Prometheus components:

```bash
kubectl apply -f mesh/metrics/traffic-permissions.yaml
```

## Tracing

./kong-mesh-1.6.0/bin/kumactl install tracing | kubectl apply -f -

```{bash}
kubectl apply -f mesh/tracing/mesh.yaml
```

- Add TrafficTrace resource

```bash
kubectl apply -f mesh/tracing/traffic-trace.yaml
```

- Update the jaeger datasource in grafana: Go to the Grafana UI -> Settings -> Data Sources -> Jaeger 
and set the URL to http://jaeger-query.kong-mesh-tracing/

## Logging

The loki statefulset requires anyuid capabilities so the anyuid should be used
```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kong-mesh-logging
```

```bash
./kong-mesh-1.6.0/bin/kumactl install logging | kubectl apply -f -
```

Create a ClusterRole for the loki-promtail serviceAccount
```bash
kubectl apply -f mesh/logging/cluster-role.yaml
```

Make the loki-promtail containers run as privileged

```bash
kubectl patch daemonset/loki-promtail -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"promtail\", \"securityContext\": {\"privileged\": true}}]}}}}"
```

Add the logging backend to the existing Mesh

```{bash}
kubectl apply -f mesh/logging/mesh.yaml
```

Create the TrafficLog

```bash
kubectl apply -f mesh/logging/traffic-log.yaml
```

Update the grafana datasource to `http://loki.kong-mesh-logging:3100`

## Clean up

- Delete demo project

```bash
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo
kubectl delete ns kuma-demo
```

- Uninstall logging

```bash
./kong-mesh-1.6.0/bin/kumactl install logging | kubectl delete -f -
```

- Uninstall tracing

```bash
./kong-mesh-1.6.0/bin/kumactl install tracing | kubectl delete -f -
```

- Uninstall metrics

```bash
kubectl delete trafficpermission grafana-to-prometheus metrics-permissions
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong-mesh-metrics
/kong-mesh-1.6.0/bin/kumactl install metrics | kubectl delete -f -
```

- Uninstall kong mesh

```bash
./kong-mesh-1.6.0/bin/kumactl install control-plane --dataplane-registry=default-route-openshift-image-registry.apps.mw-ocp4.cloud.lab.eng.bos.redhat.com/kong-image-registry --control-plane-registry=default-route-openshift-image-registry.apps.mw-ocp4.cloud.lab.eng.bos.redhat.com/kong-mesh-system --cni-enabled --license-path=./license.json  | kubectl delete -f -
```

- Remove registry if used

```bash
kubectl delete ns kong-image-registry
```
