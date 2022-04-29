# Install Kong Kubernetes Ingress Controller

```bash
oc new-project kong
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong
oc annotate namespace kong kuma.io/sidecar-injection=enabled
```

## Install the ingress using helm

```bash
helm repo add kong https://charts.konghq.com
helm repo update
```

### Using internal registry

See [openshift-registry](./openshift-registry/README.md) and make sure you have the required images in the registry.

```bash
OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
cd openshift-registry
./pull-tag-push.sh kong-kic.properties $OCP_REGISTRY/kong-image-registry
cd ..
```

Install the helm chart

```bash
KONG_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')/kong-image-registry
helm install kong kong/kong -n kong \
  --set ingressController.installCRDs=false \
  --set ingressController.image.repository="${KONG_REGISTRY}"/kubernetes-ingress-controller \
  --set ingressController.image.tag=2.3.1 \
  --set image.repository="${KONG_REGISTRY}"/kong-gateway \
  --set image.tag=2.8 \
  --set podAnnotations."kuma\.io/mesh"=default \
  --set podAnnotations."kuma\.io/gateway"=enabled
```

### Using docker.io (default)

```bash
helm install kong kong/kong -n kong \
  --set ingressController.installCRDs=false \
  --set ingressController.image.tag=2.3.1 \
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

## Health checks

This step doesn't affect the deployment, it is just to avoid the Health check errors.

It seems that the current version of Lua that uses the proxy containers doesn't support HTTP/2.0 and this error keeps
showing up in the logs

```
127.0.0.1 - - [29/Apr/2022:08:42:59 +0000] "GET /status HTTP/2.0" 500 42 "-" "Go-http-client/2.0"
2022/04/29 08:43:02 [error] 2073#0: *135 [lua] api_helpers.lua:526: handle_error(): /usr/local/share/lua/5.1/lapis/application.lua:424: /usr/local/share/lua/5.1/kong/api/routes/health.lua:52: http2 requests not supported yet
stack traceback:
       [C]: in function 'capture'
       /usr/local/share/lua/5.1/kong/api/routes/health.lua:52: in function 'fn'
       /usr/local/share/lua/5.1/kong/api/api_helpers.lua:293: in function 'fn'
        /usr/local/share/lua/5.1/kong/api/api_helpers.lua:293: in function </usr/local/share/lua/5.1/kong/api/api_helpers.lua:276>
```

To avoid this error we can patch the deployment to not use HTTP/2.0

```bash
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PROXY_LISTEN\", \"value\":                                   
\"0.0.0.0:8000, 0.0.0.0:8443 ssl\" }, { \"name\" : \"KONG_ADMIN_LISTEN\", \"value\": \"127.0.0.1:8444 ssl\" }]}]}}}}"
```

## Security

* Not yet working. If you deleted the `allow-all-default` TrafficPermission you will need to allow traffic
between the proxy and the rest of the services.

```
oc apply -f kic/traffic_permission.yaml
```

## Proxy traffic to our demo app

Create the kuma-demo ingress
```
oc apply -f kic/kuma-demo-ingress.yaml
```

You can now access your application:

```
http `oc get route kong-kong-proxy --template='{{ .spec.host }}'`/demo-app
```

## Uninstall

Uninstall kong using chart

```bash
helm uninstall kong
```

Remove the helm chart

```bash
helm repo remove helm
```

Delete the `kong` namespace

```bash
oc delete project kong
```

Remove the permissions

```bash
oc adm policy remove-scc-from-group nonroot system:serviceaccounts:kong
```
