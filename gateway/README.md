# Install Gateway CP/DP

## Kong Gateway Control Plane

As usual, create the namespace and the secret with the license.

```bash
oc new-project kong
oc create secret generic kong-enterprise-license --from-file=license=./license.json
```

Generate a certificate that will be used to expose the TLS. Use that certificate to create
a secret

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong 
```

### Deploy the Control Plane

Follow the [Internal Registry](../openshift-registry/README.md) instructions if you want to avoid pulling
images from `docker.io` in your cluster.

Install the Helm chart using the internal registry.

```bash
OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
sed -e 's/\$OCP_REGISTRY/'"$OCP_REGISTRY"'/' gateway/cp-values.yaml | helm install kong -n kong kong/kong -f -
```

### Expose the Control Plane services

Create routes for exposing the Control Plane services: `admin` and `manager`

```bash
oc apply -f gateway/expose-kong-cp.yaml
```

### Validate the installed version

```bash
http kong-kong-admin-kong.apps-crc.testing | jq -r .version
2.8.0.0-enterprise-edition
```

## Kong Gateway Data Plane

Similarly to the Control Plane, let's create the namespace with the secret containing the license

```bash
oc new-project kong-dp
kubectl create secret generic kong-enterprise-license -n kong-dp --from-file=license=../license.json
```

Now, lets re-use the generated certificates to create a secret in the Data Plane namespace

```bash
kubectl create secret tls kong-cluster-cert --cert=./gateway/cluster.crt --key=./gateway/cluster.key -n kong-dp
```

### Add the Data Plane to the Mesh

In order for the Data Plane to be part of the Mesh we have to annotate the Namespace and add the service account
to the `anyuid` scc.

```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kong-dp
oc annotate namespace kong-dp kuma.io/sidecar-injection=enabled
```

### Deploy the Data Plane

Use Helm to install Kong Data Plane in the `kong-dp` namespace.

```bash
OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
sed -e 's/\$OCP_REGISTRY/'"$OCP_REGISTRY"'/' gateway/dp-values.yaml | helm install kong kong/kong -n kong-dp -f -
```

### Expose the Proxy service

Expose the proxy so that it can be accessed from outside of the cluster.

```bash
oc apply -f gateway/expose-kong-dp.yaml
```

## Check the Data Plane from the Control Plane

Let's query the Control Plane to make sure the Data Plane is part of the cluster

```bash
http `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/clustering/status
HTTP/1.1 200 OK
access-control-allow-origin: *
cache-control: private
content-length: 349
content-type: application/json; charset=utf-8
date: Wed, 04 May 2022 10:32:48 GMT
deprecation: true
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=c0302cf3ea7c8eec70ac1a390dd15e45; path=/; HttpOnly
x-kong-admin-latency: 2
x-kong-admin-request-id: YBVhMVMrq2i9ZhYXEKlo4zbFCTQhqOhT

{
    "186c245a-a54a-4b4d-8ebd-7ed4dba05c61": {
        "config_hash": "b57e49dc4da34cd349069f9907349779",
        "hostname": "kong-dp-kong-8498fd457c-x6gjc",
        "ip": "10.217.0.157",
        "last_seen": 1651659823
    },
    "e665cd97-89ab-4584-8e0b-37a745e6399b": {
        "config_hash": "b57e49dc4da34cd349069f9907349779",
        "hostname": "kong-kong-9fb5b9646-4ds7t",
        "ip": "10.217.0.160",
        "last_seen": 1651660361
    }
}
```

## Checking the Data Plane Proxy

Now let's query the route of the Data Plane's Proxy to make sure it is working

```bash
http `oc get route -n kong-dp kong-kong-proxy --template='{{ .spec.host }}'`/
HTTP/1.1 404 Not Found
cache-control: private
content-length: 48
content-type: application/json; charset=utf-8
date: Wed, 04 May 2022 10:33:59 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 7439e381b0d6fc4efb69077feca119cd=78f6d7195d726f6af9486553b2d2cccd; path=/; HttpOnly
x-kong-response-latency: 0

{
    "message": "no Route matched with those values"
}
```

## Proxy traffic to our demo app

The demo-app is installed as part of the [mesh](../kong-mesh.md#kuma-demo-application)

Create an OpenShift route to have a dedicated hostname for the routing because the reverse proxy is not configured

```bash
oc apply -f gateway/kuma-demo-route.yaml
```

In order to configure the Data Plane Proxy to forward the requests to our demo app service we can either define a Service and Route in Kong Gateway or
create Kubernetes Ingress that the Ingress Controller will use to configure the Proxy.

### Creating a Service/Route in Kong Gateway

Use the Rest API to create the service

```bash
http `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/services name=kuma-demo url='http://frontend.kuma-demo.svc.cluster.local:8080'
HTTP/1.1 201 Created
```

Create a Gateway Route to forward requests to the OpenShift route (e.g. demo-app.kong-dp.apps-myocp.example.com) to the demo-app service in the kuma-demo namespace.

```bash
echo "http -v `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/services/kuma-demo/routes name=demoroute hosts:='[\"`oc get route -n kong-dp demo-app --template='{{ .spec.host }}'`\"]' --ignore-stdin" | sh -
HTTP/1.1 201 Created
```

### Creating an Ingress

Alternatively you can create an Ingress that the Kubernetes Ingress Controller will process and forward to the demo app.

```bash
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" kic/kuma-demo-ingress.yaml | kubectl apply -f -
```

### Validate the demo app

You can access the application in the browser or with httpie

```bash
http `oc get route demo-app -n kong-dp --template='{{ .spec.host }}'`
```

## Uninstall

Uninstall the Helm charts, the scc policies and the namespaces

```bash
helm delete kong -n kong-dp
helm delete kong -n kong

oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kong-dp
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kong

oc delete ns kong kong-dp
```
