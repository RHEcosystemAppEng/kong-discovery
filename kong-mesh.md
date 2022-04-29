- Download Kong Mesh
```
curl -L https://docs.konghq.com/mesh/installer.sh | sh -
```

a) Install control plane on kong-mesh-system namespace

```
./kumactl install control-plane --cni-enabled --license-path=./license | oc apply -f -
oc get pod -n kong-mesh-system
```

b) Using the internal registry (avoid docker.io). See [using the openshift-registry](./openshift-registry/README.md)

```bash
KONG_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')/kong-image-registry
./kumactl install control-plane --dataplane-registry=$KONG_REGISTRY --control-plane-registry=$KONG_REGISTRY --cni-enabled --license-path=./license.json  | kubectl apply -f -
```

- Expose the service

```{bash}
oc expose svc/kong-mesh-control-plane -n kong-mesh-system --port http-api-server
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

- Install resources on kuma-demo ns
```
kubectl apply -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml
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
$ kubectl -n kuma-demo get po -ojson | jq '.items[] | .spec.containers[] | .name '
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
kubectl delete trafficpermission allow-all-default
kubectl apply -f mesh/demo/traffic-permissions.yaml
oc port-forward svc/frontend -n kuma-demo 8080
```

Applying the mtls will no longer allow traffic from route to the service. TBC - KIC needs to be implemented.

## Traffic metrics

Note: If you have configured already the mTLS in your mesh, the default installation won't work because the Grafana
deployment has an initContainer that pulls the dashboards from a github repository. You can build your own Grafana
image containing the plugin using the [Dockerfile](./mesh/custom-grafana/Dockerfile).

```bash
podman build -t $KONG_REGISTRY/grafana:8.3.3-kong ./mesh/custom-grafana
podman push $KONG_REGISTRY/grafana:8.3.3-kong
./openshift-registry/pull-tag-push.sh openshift-registry/kong-mesh-metrics.properties $OCP_REGISTRY/kong-image-registry
```

- Apply scc  of non-root to ```kuma-metrics```
```
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong-mesh-metrics
```

- Allow other namespaces to pull from the kong-image-registry
```
oc policy add-role-to-group system:image-puller system:serviceaccounts:kong-mesh-metrics --namespace=kong-image-registry
```

```
./kumactl install metrics | kubectl apply -f -
```

- Patch to use registry images

```
# scale down to 0
oc project kong-mesh-metrics

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

```
./kumactl install tracing | kubectl apply -f -
```

- Allow other namespaces to pull from the kong-image-registry
```
oc policy add-role-to-group system:image-puller system:serviceaccounts:kong-mesh-tracing --namespace=kong-image-registry
```

- Patch to use registry images
```

./openshift-registry/pull-tag-push.sh openshift-registry/kong-mesh-tracing.properties $OCP_REGISTRY/kong-image-registry

oc project kong-mesh-tracing

# scale down to 0
oc scale deployment/jaeger --replicas=0

kubectl patch deployment/jaeger -n kong-mesh-tracing -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"jaeger\", \"image\": \"$KONG_REGISTRY/all-in-one:1.23\"}]}}}}"

oc scale deployment/jaeger --replicas=1
```

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
./kumactl install logging | kubectl apply -f -
```

- Allow other namespaces to pull from the kong-image-registry
```
oc policy add-role-to-group system:image-puller system:serviceaccounts:kong-mesh-logging --namespace=kong-image-registry
```

- Patch to use registry images
```

./openshift-registry/pull-tag-push.sh openshift-registry/kong-mesh-logging.properties $OCP_REGISTRY/kong-image-registry

oc project kong-mesh-logging

kubectl patch daemonset/loki-promtail -n kong-mesh-logging -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"promtail\", \"image\": \"$KONG_REGISTRY/promtail:2.4.1\"}]}}}}"

# scale down to 0

oc scale statefulset/loki --replicas=0

kubectl patch statefulset/loki -n kong-mesh-logging -p "{\"spec\": {\"template\":{\"spec\": {\"containers\": [{\"name\": \"loki\", \"image\": \"$KONG_REGISTRY/loki:2.4.1\"}]}}}}"

oc scale statefulset/loki --replicas=1
```

Create a ClusterRole for the loki-promtail serviceAccount
```bash
kubectl apply -f mesh/logging/clusterrole.yaml
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

## FaultInjection

FaultInjections helps testing our microservices against resiliency. There are 3 different ypes of failures that could be 
imitated in our environment:

- [Delay](https://kuma.io/docs/1.6.x/policies/fault-injection/#delay)
- [Abort](https://kuma.io/docs/1.6.x/policies/fault-injection/#abort)
- [ResponseBandwidth](https://kuma.io/docs/1.5.x/policies/fault-injection/#responsebandwidth-limit)

Create an example FaultInjection that adds a bit of everything:

```bash
kubectl apply -f mesh/fault_injection.yaml
```

Then browse the application and see how the website resources randomly
fail to be fetched, are delayed or corrupted (due to the bandwitdh limitation).

Once finished, remove the faultInjection resource

```bash
kubectl delete -f mesh/fault_injection.yaml
```

## Clean up

- Delete demo project

```bash
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo
kubectl delete ns kuma-demo
```

- Uninstall logging

```bash
./kumactl install logging | kubectl delete -f -
```

- Uninstall tracing

```bash
./kumactl install tracing | kubectl delete -f -
```

- Uninstall metrics

```bash
kubectl delete trafficpermission grafana-to-prometheus metrics-permissions
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong-mesh-metrics
./kumactl install metrics | kubectl delete -f -
```

- Uninstall kong mesh

```bash
./kumactl install control-plane --dataplane-registry=default-route-openshift-image-registry.apps.mw-ocp4.cloud.lab.eng.bos.redhat.com/kong-image-registry --control-plane-registry=default-route-openshift-image-registry.apps.mw-ocp4.cloud.lab.eng.bos.redhat.com/kong-mesh-system --cni-enabled --license-path=./license.json  | kubectl delete -f -
```

- Remove registry if used

```bash
kubectl delete ns kong-image-registry
```
