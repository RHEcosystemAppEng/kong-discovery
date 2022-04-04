# Kong Gateway using the Operator (CP/DP with Ingress Controller)  
The Kong Operator is a helm operator. The values defined in the operator instance are turned into helm values. All possible fields for the operator can be found 
[here](https://github.com/Kong/kong-operator/blob/main/deploy/crds/charts_v1alpha1_kong_cr.yaml) and are the same as the helm values for this operator which can be found 
[here](https://github.com/Kong/kong-operator/blob/main/helm-charts/kong/values.yaml).  

We will Deploy the Kong Gateway using the Kong Operator and deploy the Control Plane and Data Plane in two distinct namespaces.

**TOC**  
- [Register a cluster to Red Hat Market place](#register-a-cluster-to-red-hat-market-place)
- [Deploy Sample App](#deploy-sample-app)
- [Install the Operator](#install-operator-subscription)
- [Patch the Operator Deployment](#patch-operator-deployment)
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
- [Defining a Service and a Route](#defining-a-service-and-a-route)
- [Define a Service and a Route using CRDs](#define-a-service-and-a-route-using-crds)
- [Define Rate Limiting Policy](#define-rate-limiting-policy)
- [Define an API Key Policy](#define-an-api-key-policy)
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
output
```
service/sample created
deployment.apps/sample created
```

wait for app to be ready
```
kubectl wait --for=condition=ready pod -l app=sample --timeout=120s
```
output
```
pod/sample-76db6bb547-klztz condition met
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

## Patch Operator Deployment
Patch kong-operator deployment update `RELATED_IMAGE_KONG`.
```
kubectl patch deploy/kong-operator -n openshift-operators  -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"kong-operator\",\"env\": [{ \"name\" : \"RELATED_IMAGE_KONG\", \"value\": 
\"kong/kong-gateway:2.8.0.0-alpine\" }]}]}}}}"
```
Patch kong-operator deployment, update `RELATED_IMAGE_KONG_CONTROLLER`
```
kubectl patch deploy/kong-operator -n openshift-operators  -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"kong-operator\",\"env\": [{ \"name\" : \"RELATED_IMAGE_KONG_CONTROLLER\", \"value\": 
\"kong/kubernetes-ingress-controller:2.2.1\" }]}]}}}}"
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
  "error": "failed to install release: template: kong/templates/ingress-class.yaml:2:34: executing \"kong/templates/ingress-class.yaml\" at <lookup \"networking.k8s.io/v1\" \"IngressClass\" \"\" \"kong\">: error 
calling lookup: ingressclasses.networking.k8s.io \"kong\" is forbidden: User \"system:serviceaccount:openshift-operators:kong-operator\" cannot get resource \"ingressclasses\" in API group \"networking.k8s.io\" at 
the cluster scope",
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
    unifiedRepoTag: kong/kong-gateway:2.8.0.0-alpine
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
      unifiedRepoTag: kong/kubernetes-ingress-controller:2.2.1
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
      runAsUser: 1000670000
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
http $(kubectl get route kong-kong-admin -n kong -ojsonpath='{.status.ingress[0].host}') kong-admin-token:kong | jq -r .version
```
output:
```
2.8.0.0-enterprise-edition
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
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": 
\"kong-kong-admin-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
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
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_API_URL\", \"value\": 
\"kong-kong-portalapi-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
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
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_GUI_HOST\", \"value\": 
\"kong-kong-portal-kong.apps.mpkongdemo.51ty.p1.openshiftapps.com\" }]}]}}}}"
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
    unifiedRepoTag: kong/kong-gateway:2.8.0.0-alpine
  ingressController:
    enabled: false
    image:
      unifiedRepoTag: kong/kubernetes-ingress-controller:2.2.1
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
output
```
kong.charts.konghq.com/kong-dp created
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
date: Mon, 04 Apr 2022 22:34:00 GMT
deprecation: true
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=58532545a25e6ff24dadc281c58c45bd; path=/; HttpOnly
x-kong-admin-latency: 53
x-kong-admin-request-id: p3iUf2AibJMME3seQgjfty9MpIk8Gp8a

{
    "b2ddab51-ef6c-43ec-aaa8-7375969c9fbc": {
        "config_hash": "8da25e9d3cb10ff3a634af9fc0401e06",
        "hostname": "kong-dp-kong-7b6d5dddbb-thdm8",
        "ip": "10.131.1.51",
        "last_seen": 1649111623
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
date: Mon, 04 Apr 2022 22:34:24 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
x-kong-response-latency: 0

{
    "message": "no Route matched with those values"
}
```

## Defining a Service and a Route
From your laptop define a service and a route sending requests to the Control Plane
```
http $(kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}')/services name=sampleservice url='http://sample.default.svc.cluster.local:5000' kong-admin-token:kong
```
output:
```
HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 397
content-type: application/json; charset=utf-8
date: Mon, 04 Apr 2022 22:35:01 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=58532545a25e6ff24dadc281c58c45bd; path=/; HttpOnly
x-kong-admin-latency: 81
x-kong-admin-request-id: sFOL9fY79YEVNpKFb2Y64odlHvzvbRby

{
    "ca_certificates": null,
    "client_certificate": null,
    "connect_timeout": 60000,
    "created_at": 1649111701,
    "enabled": true,
    "host": "sample.default.svc.cluster.local",
    "id": "d94c6700-fcdd-4c17-bff5-4f81867b7abb",
    "name": "sampleservice",
    "path": null,
    "port": 5000,
    "protocol": "http",
    "read_timeout": 60000,
    "retries": 5,
    "tags": null,
    "tls_verify": null,
    "tls_verify_depth": null,
    "updated_at": 1649111701,
    "write_timeout": 60000
}
```

Create a route
```
http $(kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}')/services/sampleservice/routes name='httpbinroute' paths:='["/sample"]' kong-admin-token:kong
```
output
```
HTTP/1.1 201 Created
access-control-allow-origin: *
content-length: 486
content-type: application/json; charset=utf-8
date: Mon, 04 Apr 2022 22:35:38 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 9da87f6e8821b5f9e46a0f05aee42078=58532545a25e6ff24dadc281c58c45bd; path=/; HttpOnly
x-kong-admin-latency: 80
x-kong-admin-request-id: QhidOnJhNT7C3q58TBmXos0OQJgQ0epW

{
    "created_at": 1649111738,
    "destinations": null,
    "headers": null,
    "hosts": null,
    "https_redirect_status_code": 426,
    "id": "bb1706b4-81e0-472e-a4aa-9ac04d1a7cef",
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
        "id": "d94c6700-fcdd-4c17-bff5-4f81867b7abb"
    },
    "snis": null,
    "sources": null,
    "strip_path": true,
    "tags": null,
    "updated_at": 1649111738
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
date: Mon, 04 Apr 2022 22:36:42 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 8
x-kong-upstream-latency: 7

Hello World, Kong: 2022-04-04 22:36:42.025975
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
date: Mon, 04 Apr 2022 22:37:03 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 1
x-kong-upstream-latency: 4

Hello World, Kong: 2022-04-04 22:37:03.944241


HTTP/1.1 200 OK
cache-control: private
content-length: 45
content-type: text/html; charset=utf-8
date: Mon, 04 Apr 2022 22:37:05 GMT
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 1
x-kong-upstream-latency: 267

Hello World, Kong: 2022-04-04 22:37:05.004412


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
output
```
kongplugin.configuration.konghq.com/rl-by-minute created
```

Add plugin to the route
```
kubectl patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"rl-by-minute"}}}'
```
output
```
ingress.networking.k8s.io/sampleroute patched
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
date: Mon, 04 Apr 2022 22:39:10 GMT
ratelimit-limit: 3
ratelimit-remaining: 0
ratelimit-reset: 50
retry-after: 50
server: kong/2.8.0.0-enterprise-edition
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
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
output
```
kongplugin.configuration.konghq.com/apikey created
```

Apply the plugin to the route:
```
kubectl patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"apikey, rl-by-minute"}}}'
```
output
```
ingress.networking.k8s.io/sampleroute patched
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
date: Mon, 04 Apr 2022 22:40:29 GMT
server: kong/2.8.0.0-enterprise-edition
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
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
output
```
secret/consumerapikey created
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
output
```
kongconsumer.configuration.konghq.com/consumer1 created
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
date: Mon, 04 Apr 2022 22:41:27 GMT
ratelimit-limit: 3
ratelimit-remaining: 2
ratelimit-reset: 33
server: Werkzeug/1.0.1 Python/3.7.4
set-cookie: 221e03621b6ead39ca50bfd3582fedc0=1f6fbc4cf35e7510cbea2620cf2a9c78; path=/; HttpOnly
via: kong/2.8.0.0-enterprise-edition
x-kong-proxy-latency: 1
x-kong-upstream-latency: 3
x-ratelimit-limit-minute: 3
x-ratelimit-remaining-minute: 2

Hello World, Kong: 2022-04-04 22:41:27.048848
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
