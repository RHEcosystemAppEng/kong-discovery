# Install Kong Kubernetes Ingress Controller

```bash
oc new-project kong
oc adm policy add-scc-to-group nonroot -z kong-serviceaccount -n kong
oc annotate namespace kong kuma.io/sidecar-injection=enabled
```

Install the ingress using helm

```
helm repo add kong https://charts.konghq.com
helm repo update

helm install kong kong/kong -n kong \
  --set ingressController.installCRDs=false \
  --set ingressController.image.repository="${KONG_REGISTRY}"/kubernetes-ingress-controller \  
  --set ingressController.image.tag=2.3.1 \
  --set image.repository="${KONG_REGISTRY}"/kong-gateway \
  --set image.tag=2.8 \
  --set podAnnotations."kuma\.io/mesh"=default \
  --set podAnnotations."kuma\.io/gateway"=enabled

```

## Create ClusterIP services

This deployment is oriented to Kubernetes. For Openshift is better to replace the LoadBalancer services
with ClusterIP and then expose them through routes.

```
kubectl delete svc kong-kong-proxy
kubectl apply -f kic/expose-kong-proxy.yaml
```

Allow communication between kong Ingress Controller and the mesh

```
oc apply -f kic/traffic_permission.yaml
```

Create the kuma-demo ingress
```
oc apply -f kic/kuma-demo-ingress.yaml
```

You can now access your application:

```
http `oc get route kong-kong-proxy --template='{{ .spec.host }}'`/demo-app
```

NOTE: After some time it stops working:

```
$ http `oc get route kong-kong-proxy --template='{{ .spec.host }}'`/demo-app
HTTP/1.1 503 Service Unavailable
content-length: 95
content-type: text/plain; charset=UTF-8
date: Thu, 28 Apr 2022 15:19:01 GMT
server: envoy
set-cookie: 157c7d417676c54695fa6cf886b2feeb=fde5bcb91b17e49f15ea3646b20eb9b6; path=/; HttpOnly
via: kong/2.8.1
x-kong-proxy-latency: 0
x-kong-upstream-latency: 244

upstream connect error or disconnect/reset before headers. reset reason: connection termination

```