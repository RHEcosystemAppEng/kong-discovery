# Kong Gateway using the Operator (CP/DP with Ingress Controller)  
The Kong Operator is a helm operator. The values defined in the operator instance are turned into helm values. All possible fields for the operator can be found [here](https://github.com/Kong/kong-operator/blob/main/deploy/crds/charts_v1alpha1_kong_cr.yaml) and are the same as the helm values for this operator which can be found [here](https://github.com/Kong/kong-operator/blob/main/helm-charts/kong/values.yaml).  

We will Deploy the Kong Gateway using the Kong Operator and deploy the Control Plane and Data Plane in two distinct namespaces.

**TOC**  
- [Register a cluster to Red Hat Market place](#register-a-cluster-to-Red-Hat-Market-place)
- [Deploy Sample App](#deploy-sample-app)
- [Install the Operator](#install-operator-subscription)
- [Create Control Plane Namespace](#create-control-plane-namespace)
- [Create Control Plane Secrets](#create-control-plane-secrets)
- [Deploy kong operator for Control Plane](#deploy-kong-operator-for-control-plane)
- [Expose Control Plane Services](#expose-control-plane-services)
- [Check the version](#check-the-version)
- [Configure Kong Manager Service](#configure-kong-manager-service)
- [Configure Kong Dev Portal](#configure-kong-dev-portal)
- [Visit Kong Manager](#visit-kong-manager)
- [Create Data Plane Namespace](#create-data-plane-namespace)
- [Create Data Plane Secrets](#create-data-plane-secrets)
- [Deploy kong operator for Data Plane](#deploy-kong-operator-for-data-plane)
- [Expose Data Plane Services](#expose-data-plane-services)
- [Checking the Data Plane from the Control Plane](#checking-the-data-plane-from-the-control-plane)\
- [Deploy Sample App](#deploy-sample-app)
- [Defining a Service and a Route](#defining-a-service-and-a-route)
- [Create a Service and Route using CRDs](#create-a-service-and-route-using-crds)
- [Define Rate Limiting Policy](#defined-rate-limiting-policy)
- [Define an API Key Policy](#define-api-key-policy)
- [Clean Up](#clean-up)

## Register a cluster to Red Hat Market place
- Register a cluster to Red Hat Market place

```
RedHat Marketplace -> Workspace -> Cluster -> Add Cluster
oc create namespace openshift-redhat-marketplace
```

-  Create Red Hat Marketplace Subscription
```
oc apply -f "https://marketplace.redhat.com/provisioning/v1/rhm-operator/rhm-operator-subscription?approvalStrategy=Automatic"
```
- Monitor the CSV
```
oc get csv -n openshift-redhat-marketplace -w # The phase should be succeeded.
```
- Monitor the subs
```
oc get subs -n openshift-redhat-marketplace
```
- Create Red Hat Marketplace Kubernetes Secret
```
oc create secret generic redhat-marketplace-pull-secret -n openshift-redhat-marketplace --from-literal=PULL_SECRET=<<PULL-SECRET>
```

- Add the Red Hat Marketplace pull secret to the global pull secret on the cluster
```
curl -sL https://marketplace.redhat.com/provisioning/v1/scripts/update-global-pull-secret | bash -s <<PULL_SECRET>>
```
- Validate the registration of cluster from 
```
Red Hat Marketplace -> Workspace -> Clusters
```

## Deploy Sample App
We start by deploying a sample app that we will use with Kong Gateway.
```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: sample
  namespace: default
  labels:
    app: sample
spec:
  type: ClusterIP
  ports:
  - port: 5000
    name: http
  selector:
    app: sample
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sample
  template:
    metadata:
      labels:
        app: sample
        version: v1
    spec:
      containers:
      - name: sample
        image: claudioacquaviva/sampleapp
        ports:
        - containerPort: 5000
EOF
```

## Install Operator Subscription
```
kubectl create -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kong-offline-operator-rhmp
  namespace: openshift-operators
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: kong-offline-operator-rhmp
  source: redhat-marketplace
  sourceNamespace: openshift-marketplace
  startingCSV: kong.v0.10.0
EOF
```
- Monitor the install
```
oc get csv -n openshift-operators -w #Pghase needs to be Succeded
```

## Create Control Plane Namespace
We will store our control plane components on the kong namespace
```
kubectl create ns kong
```

## Create Control Plane Secrets
These are prerequisites for using Kong Gateway Enterprise.

Create Kong enterprise secret
```
kubectl create secret generic kong-enterprise-license --from-file=license -n kong
```

Generate Private Key and Digital Certificate
```
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"

kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong

kubectl create secret generic kong-enterprise-superuser-password -n kong --from-literal=password=kong
```

Create Session Config for Kong Manager and Kong DevPortal
```
cat <<EOF > admin_gui_session_conf
{"cookie_name":"admin_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}
EOF

cat <<EOF > portal_session_conf
{"cookie_name":"portal_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}
EOF

kubectl create secret generic kong-session-config -n kong --from-file=admin_gui_session_conf --from-file=portal_session_conf
```

## Deploy kong operator for Control Plane
Avoid this error:
```
{
  "level": "error",
  "ts": 1648670959.9781337,
  "logger": "controller.kong-controller",
  "msg": "Reconciler error",
  "name": "kong",
  "namespace": "kong",
  "error": "failed to install release: template: kong/templates/ingress-class.yaml:2:34: executing \"kong/templates/ingress-class.yaml\" at <lookup \"networking.k8s.io/v1\" \"IngressClass\" \"\" \"kong\">: error calling lookup: ingressclasses.networking.k8s.io \"kong\" is forbidden: User \"system:serviceaccount:openshift-operators:kong-operator\" cannot get resource \"ingressclasses\" in API group \"networking.k8s.io\" at the cluster scope",
  "stacktrace": "sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2.2\n\t/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.10.0/pkg/internal/controller/controller.go:227"
}
```
By assigning cluster-admin clusterrole to the kong-operator ServiceAccount in openshift-operators, or else the StatefulSet will have problems.   
```
kubectl create clusterrolebinding kong-admin --clusterrole=cluster-admin --serviceaccount=openshift-operators:kong-operator
```


Next, we need the value of the `kong` namespace's `sa.scc.uid-range`. we will use this value when we create an instance of the Kong Operator.
```
kubectl get ns kong -ojsonpath='{.metadata.annotations.openshift\.io\/sa\.scc\.uid-range}'
```
Assign that value to `.spec.postgresql.securityContext.runAsUser`

Now, deploy an instance of the operator.
```
kubectl apply -f -<<EOF
apiVersion: charts.konghq.com/v1alpha1
kind: Kong
metadata:
  name: kong
  namespace: kong
spec:
  admin:
    enabled: true
    http:
      enabled: true
    type: NodePort
  cluster:
    enabled: true
    tls:
      containerPort: 8005
      enabled: true
      servicePort: 8005
  clustertelemetry:
    enabled: true
    tls:
      containerPort: 8006
      enabled: true
      servicePort: 8006
  enterprise:
    enabled: true
    license_secret: kong-enterprise-license
    portal:
      enabled: true
    rbac:
      admin_gui_auth_conf_secret: admin-gui-session-conf
      enabled: true
      session_conf_secret: kong-session-config
    smtp:
      enabled: false
  env:
    cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
    cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
    database: postgres
    password:
      valueFrom:
        secretKeyRef:
          key: password
          name: kong-enterprise-superuser-password
    portal_gui_protocol: http
    role: control_plane
  image:
    repository: kong/kong-gateway
    tag: 2.8.0.0-alpine
  ingressController:
    enabled: true
    env:
      enable_reverse_sync: true
      kong_admin_token:
        valueFrom:
          secretKeyRef:
            key: password
            name: kong-enterprise-superuser-password
      sync_period: 1m
    image:
      repository: kong/kubernetes-ingress-controller
      tag: 2.2.1
    installCRDs: false
  manager:
    enabled: true
    type: NodePort
  portal:
    enabled: true
    http:
      enabled: true
    type: NodePort
  portalapi:
    enabled: true
    http:
      enabled: true
    type: NodePort
  postgresql:
    enabled: true
    postgresqlDatabase: kong
    postgresqlPassword: kong
    postgresqlUsername: kong
    securityContext:
      fsGroup: ""
      runAsUser: 1000720000
  proxy:
    enabled: true
  secretVolumes:
  - kong-cluster-cert
EOF
```

## Expose Control Plane Services
```
oc expose svc/kong-kong-admin -n kong
oc expose svc/kong-kong-manager -n kong
oc expose svc/kong-kong-portal -n kong
oc expose svc/kong-kong-portalapi -n kong
```

## Check the Version
Wait for the pods to come up first
```
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=app -n kong
```

Check the version
```
http $(kubectl get route kong-kong-admin -n kong -ojsonpath='{.status.ingress[0].host}') | jq -r .version
```
output:
```
2.4.0
```

## Configure Kong Manager Service
Patch the kong-kong deployment with the value of your `kong-kong-admin` route:
```
kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}{"\n"}'
```
output:
```
kong-kong-admin-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com
```
Patch the deployment
```
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"kong-kong-admin-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
```

## Configure Kong Dev Portal
Get the route of the dev portalapi and patch the Kong deployment
```
kubectl get routes -n kong  kong-kong-portalapi -ojsonpath='{.status.ingress[0].host}{"\n"}'
```
output:
```
kong-kong-portalapi-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com
```

Patch the deployment
```
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_API_URL\", \"value\": \"http://kong-kong-portalapi-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
```

Get the route of the dev portal and patch the Kong deployment
```
kubectl get routes -n kong  kong-kong-portal -ojsonpath='{.status.ingress[0].host}{"\n"}'
```
output:
```
kong-kong-portal-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com
```

patch the deployment
```
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_GUI_HOST\", \"value\": \"kong-kong-portal-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
```

## Visit Kong Manager
Open in your browser
```
kubectl get routes -n kong kong-kong-manager -ojsonpath='{.status.ingress[0].host}{"\n"}'
```
## Create Data Plane Namespace
This is namespace is where your Data Plane components
```
kubectl create ns kong-dp
```
## Create Data Plane Secrets
These are prerequisites for using Kong Gateway Enterprise.

Create Kong enterprise secrets
```
kubectl create secret generic kong-enterprise-license --from-file=license -n kong-dp

kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp

kubectl create secret generic kong-enterprise-superuser-password -n kong-dp --from-literal=password=kong
```


## Deploy kong operator for Data Plane
Now, deploy an instance of the operator for the Data Plane.
```
kubectl apply -f -<<EOF
apiVersion: charts.konghq.com/v1alpha1
kind: Kong
metadata:
  name: kong-dp
  namespace: kong-dp
spec:
  enterprise:
    enabled: true
    license_secret: kong-enterprise-license
    portal:
      enabled: false
    rbac:
      enabled: false
    smtp:
      enabled: false
  env:
    cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
    cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
    cluster_control_plane: kong-kong-cluster.kong.svc.cluster.local:8005
    cluster_telemetry_endpoint: kong-kong-clustertelemetry.kong.svc.cluster.local:8006
    database: "off"
    lua_ssl_trusted_certificate: /etc/secrets/kong-cluster-cert/tls.crt
    role: data_plane
    status_listen: 0.0.0.0:8100
  image:
    repository: kong/kong-gateway
    tag: 2.8.0.0-alpine
  ingressController:
    enabled: false
  manager:
    enabled: false
  portal:
    enabled: false
  portalapi:
    enabled: false
  proxy:
    enabled: true
    type: NodePort
  secretVolumes:
  - kong-cluster-cert
EOF
```

## Expose Data Plane Services
```
oc expose service kong-dp-kong-proxy -n kong-dp
```

## Checking the Data Plane from the Control Plane
```
http $(kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}')/clustering/status kong-admin-token:kong
```
output
```
HTTP/1.1 200 OK
access-control-allow-origin: *
cache-control: private
content-length: 176
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 15:40:50 GMT
deprecation: true
server: kong/2.4.0
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=40227c2ec427147f4f6f73d9025a0b09; path=/; HttpOnly
x-kong-admin-latency: 1

{
    "c4846b12-3cf9-48ca-8821-a61ad535f5d3": {
        "config_hash": "00000000000000000000000000000000",
        "hostname": "kong-dp-kong-86b8b669f4-mkrr6",
        "ip": "10.128.2.21",
        "last_seen": 1648741236
    }
}
```


## Checking the Proxy
```
http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')
```
output:
```
HTTP/1.1 404 Not Found
cache-control: private
content-length: 48
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 15:41:09 GMT
server: kong/2.4.0
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=603cd394d7a6aa0e90a25d5376b51682; path=/; HttpOnly
x-kong-response-latency: 0

{
    "message": "no Route matched with those values"
}
```

## Defining a Service and a Route
From your laptop define a service and a route sending requests to the Control Plane
```
http $(kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}')/services name=sampleservice url='http://sample.default.svc.cluster.local:5000'
```
output:
```
HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 382
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 15:41:25 GMT
server: kong/2.4.0
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=40227c2ec427147f4f6f73d9025a0b09; path=/; HttpOnly
x-kong-admin-latency: 7

{
    "ca_certificates": null,
    "client_certificate": null,
    "connect_timeout": 60000,
    "created_at": 1648741285,
    "host": "sample.default.svc.cluster.local",
    "id": "98c280a1-17ca-49b9-b8d7-7589542464d0",
    "name": "sampleservice",
    "path": null,
    "port": 5000,
    "protocol": "http",
    "read_timeout": 60000,
    "retries": 5,
    "tags": null,
    "tls_verify": null,
    "tls_verify_depth": null,
    "updated_at": 1648741285,
    "write_timeout": 60000
}
```

Create a route
```
http $(kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}')/services/sampleservice/routes name='httpbinroute' paths:='["/sample"]'
```
output
```
HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 486
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 15:41:44 GMT
server: kong/2.4.0
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=40227c2ec427147f4f6f73d9025a0b09; path=/; HttpOnly
x-kong-admin-latency: 12

{
    "created_at": 1648741304,
    "destinations": null,
    "headers": null,
    "hosts": null,
    "https_redirect_status_code": 426,
    "id": "3d1f59a0-5ca5-462f-8fbc-723089920673",
    "methods": null,
    "name": "httpbinroute",
    "path_handling": "v0",
    "paths": [
        "/sample"
    ],
    "preserve_host": false,
    "protocols": [
        "http",
        "https"
    ],
    "regex_priority": 0,
    "request_buffering": true,
    "response_buffering": true,
    "service": {
        "id": "98c280a1-17ca-49b9-b8d7-7589542464d0"
    },
    "snis": null,
    "sources": null,
    "strip_path": true,
    "tags": null,
    "updated_at": 1648741304
}
```

Curl the service
```
http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')/sample/hello
```

output
```
HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:03:18 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=f5bb7287e8b6563624170fb6bd601bd6; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 359
x-kong-upstream-latency: 4

Hello World, Kong: 2022-03-30 23:03:18.589683
```

Curl Consecutively (if you want)
```
for x in $(seq 20); do http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')/sample/hello; done
```
output
```
HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:10:54 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=72ee36ab6aa688d39e144b267679f458; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 6
x-kong-upstream-latency: 1

Hello World, Kong: 2022-03-30 23:10:54.294184


HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:10:54 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=72ee36ab6aa688d39e144b267679f458; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 1
x-kong-upstream-latency: 1

Hello World, Kong: 2022-03-30 23:10:54.804185


HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:10:55 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=72ee36ab6aa688d39e144b267679f458; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 0
x-kong-upstream-latency: 2

Hello World, Kong: 2022-03-30 23:10:55.294731


^CHTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:10:56 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=72ee36ab6aa688d39e144b267679f458; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 1
x-kong-upstream-latency: 2

Hello World, Kong: 2022-03-30 23:10:56.047257


HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Wed, 30 Mar 2022 23:10:56 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=72ee36ab6aa688d39e144b267679f458; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 1
x-kong-upstream-latency: 2

Hello World, Kong: 2022-03-30 23:10:56.544776


^C%  
```
**Visit Kong Manager Again**   
Open in your browser
```
kubectl get routes -n kong kong-kong-manager -ojsonpath='{.status.ingress[0].host}'
```

## Define a Service and a Route using CRDs
We are going to create a route, `/sampleroute` to route to the sample service
```
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sampleroute
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /sampleroute
          pathType: Prefix
          backend:
            service:
              name: sample
              port:
                number: 5000

EOF
```
output
```
ingress.networking.k8s.io/sampleroute created
```

## Define Rate Limiting Policy
Since we have the Microservice exposed through a route defined in the Ingress Controller, let's protect it with a Rate Limiting Policy first.

Create the plugin
```
cat <<EOF | kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rl-by-minute
  namespace: default
config:
  minute: 3
  policy: local
plugin: rate-limiting
EOF
```

Add plugin to the route
```
kubectl patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"rl-by-minute"}}}'
```

Test the plugin
```
for z in $(seq 10); do http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')/sampleroute/hello; done
```

output
```
HTTP/1.1 429 Too Many Requests
content-length: 41
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 15:53:41 GMT
ratelimit-limit: 3
ratelimit-remaining: 0
ratelimit-reset: 19
retry-after: 19
server: kong/2.4.0
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=603cd394d7a6aa0e90a25d5376b51682; path=/; HttpOnly
x-kong-response-latency: 1
x-ratelimit-limit-minute: 3
x-ratelimit-remaining-minute: 0

{
    "message": "API rate limit exceeded"
}
```

## Define an API Key Policy
Now, we will add an API Key Policy to the route

Create the plugin
```
cat <<EOF | kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: apikey
  namespace: default
plugin: key-auth
EOF
```

Apply the plugin to the route:
```
kubectl patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"apikey, rl-by-minute"}}}'
```

Test the plugin 
```
http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')/sampleroute/hello
```

output
```
HTTP/1.1 401 Unauthorized
content-length: 45
content-type: application/json; charset=utf-8
date: Thu, 31 Mar 2022 16:02:21 GMT
server: kong/2.4.0
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=603cd394d7a6aa0e90a25d5376b51682; path=/; HttpOnly
www-authenticate: Key realm="kong"
x-kong-response-latency: 0

{
    "message": "No API key found in request"
}
```


Provision a key
```
kubectl create secret generic consumerapikey -n default --from-literal=kongCredType=key-auth --from-literal=key=kong-secret
```

Create a consumer with the key
```
cat <<EOF | kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: consumer1
  namespace: default
  annotations:
    kubernetes.io/ingress.class: kong
username: consumer1
credentials:
- consumerapikey
EOF
```

Consume Route with Key and Test
```
http $(kubectl get routes -n kong-dp kong-dp-kong-proxy -ojsonpath='{.status.ingress[0].host}')/sampleroute/hello apikey:kong-secret
```

output:
```
HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Thu, 31 Mar 2022 16:04:02 GMT
ratelimit-limit: 3
ratelimit-remaining: 2
ratelimit-reset: 58
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=603cd394d7a6aa0e90a25d5376b51682; path=/; HttpOnly
via: kong/2.4.0
x-kong-proxy-latency: 1
x-kong-upstream-latency: 2
x-ratelimit-limit-minute: 3
x-ratelimit-remaining-minute: 2

Hello World, Kong: 2022-03-31 16:04:02.495356
```

## Clean up
Delete the Kong instance, subscription, and CSV from the `openshift-operators` namespace:
```
kubectl delete kongconsumer consumer1 -n default
kubectl delete secret consumerapikey -n default
kubectl delete kongplugin apikey
kubectl annotate ingress sampleroute -n default konghq.com/plugins-
kubectl delete kongplugin rl-by-minute
kubectl delete ing sampleroute --force --grace-period=0

kubectl delete kong/kong -n kong
kubectl delete kong/kong-dp -n kong-dp

kubectl delete subs -n openshift-operators kong-offline-operator-rhmp

kubectl delete csv -n openshift-operators kong.v0.10.0  

kubectl delete po,pvc -n kong --force --grace-period=0 --all

kubectl delete routes -n kong --all
kubectl delete routes -n kong-dp --all

kubectl delete secrets -n kong --all
kubectl delete secrets -n kong-dp --all

kubectl delete clusterrolebinding kong-admin

kubectl delete deploy,svc sample -n default --force --grace-period=0
```
