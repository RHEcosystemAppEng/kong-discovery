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

Create the kuma-demo ingress. We're creating a specific route in the kong namespace for setting
a dedicated hostname for this ingress.

```bash
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" kic/kuma-demo-ingress.yaml | kubectl apply -f -
```

You can now access your application:

```
http `oc get route demo-app -n kong --template='{{ .spec.host }}'`/
```

### Using Plugins

There are 2 types of plugins:

* KongPlugins: Can be used by resources in the same namespace
* KongClusterPlugins: Can be used cluster wide

### RateLimiting example

Create a KongPlugin and update the Ingress to use it.

```bash
kubectl apply -f kic/simple-rate-limiting.yaml
oc annotate ingress demo-app-ingress --overwrite -n kuma-demo konghq.com/plugins=rate-free-tier
```

After that, you can see in the HTTP headers the rate limiting information:

```bash
$ http `oc get route demo-app -n kong --template='{{ .spec.host }}'`/demo-app
HTTP/1.1 200 OK
...
ratelimit-limit: 10
ratelimit-remaining: 9
ratelimit-reset: 54
x-ratelimit-limit-minute: 10
x-ratelimit-remaining-minute: 9
```

### Advanced RateLimiting example

It is also possible to limit rating based on the authenticated user. For that we can create a secret with the apiKey
of a consumer, the KongConsumer that will be matched to this apiKey thanks to the auth-plugin.

Then the rate limiting plugin will be defined by consumer. Allowing only authenticated users.

First, create a configmap with the credentials

```bash
oc create secret generic user1-apikey -n kuma-demo --from-literal=kongCredType=key-auth --from-literal=key=demo
```

Then apply the complex-rate-limiting file that creates all the necessary resources and updates the ingress

```bash
kubectl apply -f kic/complex-rate-limiting.yaml
oc annotate ingress demo-app-ingress --overwrite -n kuma-demo konghq.com/plugins=user1-auth,rate-paid-tier
```

Let's try the auth plugin and the rate limiting without providing the apiKey

```bash
$ http `oc get route demo-app -n kong --template='{{ .spec.host }}'`/             
HTTP/1.1 401 Unauthorized
content-length: 45
content-type: application/json; charset=utf-8
date: Fri, 29 Apr 2022 12:05:30 GMT
server: kong/2.8.1.0-enterprise-edition
set-cookie: 157c7d417676c54695fa6cf886b2feeb=6b42459352c6c11b78a624dfb4af1f0b; path=/; HttpOnly
www-authenticate: Key realm="kong"
x-kong-response-latency: 0

{
    "message": "No API key found in request"
}
```

Now let's provide an invalid apiKey

```bash
$ http `oc get route demo-app -n kong --template='{{ .spec.host }}'`/ apiKey:invalid         
HTTP/1.1 401 Unauthorized
content-length: 52
content-type: application/json; charset=utf-8
date: Fri, 29 Apr 2022 12:06:31 GMT
server: kong/2.8.1.0-enterprise-edition
set-cookie: 157c7d417676c54695fa6cf886b2feeb=6b42459352c6c11b78a624dfb4af1f0b; path=/; HttpOnly
x-kong-response-latency: 0

{
    "message": "Invalid authentication credentials"
}
```

Finally, let's make Kong happy by providing the right apiKey

```bash
$ http `oc get route demo-app -n kong --template='{{ .spec.host }}'`/ apiKey:demo   
HTTP/1.1 200 OK
ratelimit-limit: 100
ratelimit-remaining: 99
ratelimit-reset: 56
x-ratelimit-limit-minute: 100
x-ratelimit-remaining-minute: 99
```

### Restore the configuration

Remove all the resources we used:

```bash
kubectl delete secret user1-apikey -n kuma-demo
kubectl delete -f kic/complex-rate-limiting.yaml
kubectl delete -f kic/simple-rate-limiting.yaml
```

Restore the original ingress annotations

```bash
oc annotate ingress demo-app-ingress --overwrite -n kuma-demo konghq.com/plugins-
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
