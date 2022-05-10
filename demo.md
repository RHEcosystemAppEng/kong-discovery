- Deployment using helm charts
- CP/DP with Ingress Controller, DevPortal and RBAC
- Control Plane
- Create kong project

```bash
oc new-project kong
```

- Create the secret for license key

```bash
oc create secret generic kong-enterprise-license -n kong --from-file=license=./license.json
```

- Find the OpenShift project scc uid

```bash
oc describe project kong | grep 'scc'
```

- Generating Private Key and Digital Certificate

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"

oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong
```

- Creating session conf for Kong Manager and Kong DevPortal

```bash
echo '{"cookie_name":"admin_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}' > admin_gui_session_conf
echo '{"cookie_name":"portal_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}' > portal_session_conf
oc create secret generic kong-session-config -n kong --from-file=admin_gui_session_conf --from-file=portal_session_conf
```

- Creating Kong Manager password

```bash
oc create secret generic kong-enterprise-superuser-password -n kong --from-literal=password=kong
```

- Add Kong charts repository

```bash
helm repo add kong https://charts.konghq.com
helm repo update
```

- Deploy the chart

Before deploy we need to replace a few parameters.

`postgresql.primary.containerSecurityContext.runAsUser` with value in the range of project SCC UID range.

`postgresql.primary.podSecurityContext.fsGroup` with value in the range of project SCC supplemental groups.

```bash
helm install kong kong/kong -n kong \
--set env.database=postgres \
--set env.password.valueFrom.secretKeyRef.name=kong-enterprise-superuser-password \
--set env.password.valueFrom.secretKeyRef.key=password \
--set env.role=control_plane \
--set env.cluster_cert=/etc/secrets/kong-cluster-cert/tls.crt \
--set env.cluster_cert_key=/etc/secrets/kong-cluster-cert/tls.key \
--set cluster.enabled=true \
--set cluster.tls.enabled=true \
--set cluster.tls.servicePort=8005 \
--set cluster.tls.containerPort=8005 \
--set clustertelemetry.enabled=true \
--set clustertelemetry.tls.enabled=true \
--set clustertelemetry.tls.servicePort=8006 \
--set clustertelemetry.tls.containerPort=8006 \
--set image.repository=kong/kong-gateway \
--set image.tag=2.8.0.0-alpine \
--set admin.enabled=true \
--set admin.http.enabled=true \
--set admin.type=NodePort \
--set proxy.enabled=true \
--set ingressController.enabled=true \
--set ingressController.installCRDs=false \
--set ingressController.image.repository=kong/kubernetes-ingress-controller \
--set ingressController.image.tag=2.2.1 \
--set ingressController.env.kong_admin_token.valueFrom.secretKeyRef.name=kong-enterprise-superuser-password \
--set ingressController.env.kong_admin_token.valueFrom.secretKeyRef.key=password \
--set ingressController.env.enable_reverse_sync=true \
--set ingressController.env.sync_period="1m" \
--set postgresql.enabled=true \
--set postgresql.auth.username=kong \
--set postgresql.auth.database=kong \
--set postgresql.auth.password=kong \
--set postgresql.primary.containerSecurityContext.runAsUser=<SCC_UID_RANGE> \
--set postgresql.primary.podSecurityContext.fsGroup=<SCC_SUPPLEMENTAL_GROUPS> \
--set enterprise.enabled=true \
--set enterprise.license_secret=kong-enterprise-license \
--set enterprise.rbac.enabled=true \
--set enterprise.rbac.session_conf_secret=kong-session-config \
--set enterprise.rbac.admin_gui_auth_conf_secret=admin-gui-session-conf \
--set enterprise.smtp.enabled=false \
--set enterprise.portal.enabled=true \
--set manager.enabled=true \
--set manager.type=NodePort \
--set portal.enabled=true \
--set portal.http.enabled=true \
--set env.portal_gui_protocol=http \
--set portal.type=NodePort \
--set portalapi.enabled=true \
--set portalapi.http.enabled=true \
--set portalapi.type=NodePort \
--set secretVolumes[0]=kong-cluster-cert
```

or

```bash
helm install kong kong/kong -n kong \
--set postgresql.securityContext.runAsUser=<SCC_UID_RANGE> \
--set postgresql.securityContext.fsGroup=<SCC_SUPPLEMENTAL_GROUPS> \
-f konnect-cp.yaml
```

- Create the routes

```bash
oc expose service kong-kong-admin -n kong
oc expose service kong-kong-manager -n kong
oc expose service kong-kong-portal -n kong
oc expose service kong-kong-portalapi -n kong
```

- Checking the Admin API

```bash
export KONG_ADMIN_URL=$(oc get route kong-kong-admin -o jsonpath='{.spec.host}' -n kong)
http $KONG_ADMIN_URL kong-admin-token:kong | jq -r .version
```

- Configuring Kong Manager Service

```bash
oc patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"$KONG_ADMIN_URL\" }]}]}}}}"
```

- Configuring Kong Dev Portal

```bash
export KONG_PORTAL_API_URL=$(oc get route kong-kong-portalapi -o jsonpath='{.spec.host}' -n kong)
oc patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_API_URL\", \"value\": \"http://$KONG_PORTAL_API_URL\" }]}]}}}}"
oc patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_PORTAL_GUI_HOST\", \"value\": \"$KONG_PORTAL_API_URL\" }]}]}}}}"
```

- Data Plane

```bash
oc new-project kong-dp
oc create secret generic kong-enterprise-license --from-file=license=./license.json -n kong-dp
oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp

helm install kong-dp kong/kong -n kong-dp \
--set ingressController.enabled=false \
--set image.repository=kong/kong-gateway \
--set image.tag=2.8.0.0-alpine \
--set env.database=off \
--set env.role=data_plane \
--set env.cluster_cert=/etc/secrets/kong-cluster-cert/tls.crt \
--set env.cluster_cert_key=/etc/secrets/kong-cluster-cert/tls.key \
--set env.lua_ssl_trusted_certificate=/etc/secrets/kong-cluster-cert/tls.crt \
--set env.cluster_control_plane=kong-kong-cluster.kong.svc.cluster.local:8005 \
--set env.cluster_telemetry_endpoint=kong-kong-clustertelemetry.kong.svc.cluster.local:8006 \
--set proxy.enabled=true \
--set proxy.type=NodePort \
--set enterprise.enabled=true \
--set enterprise.license_secret=kong-enterprise-license \
--set enterprise.portal.enabled=false \
--set enterprise.rbac.enabled=false \
--set enterprise.smtp.enabled=false \
--set manager.enabled=false \
--set portal.enabled=false \
--set portalapi.enabled=false \
--set env.status_listen=0.0.0.0:8100 \
--set secretVolumes[0]=kong-cluster-cert
```

or

```bash
helm install kong-dp kong/kong -n kong-dp -f kong-dp.yaml
```

- Checking the Data Plane from the Control Plane

```bash
http $KONG_ADMIN_URL/clustering/status kong-admin-token:kong
```

- Expose the proxy

```bash
oc expose service kong-dp-kong-proxy -n kong-dp
```

- Checking the Proxy

```bash
export KONG_DP_PROXY_URL=$(oc get route kong-dp-kong-proxy -o jsonpath='{.spec.host}' -n kong-dp)
http $KONG_DP_PROXY_URL
```

- Deploy sample application

```bash
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

- Defining a Service and a Route

```bash
http $KONG_ADMIN_URL/services name=sampleservice url='http://sample.default.svc.cluster.local:5000' kong-admin-token:kong
http $KONG_ADMIN_URL/services/sampleservice/routes name='sampleapp' paths:='["/sample"]' kong-admin-token:kong
```

- Test the service and route

```bash
http $KONG_DP_PROXY_URL/sample/hello
while [ 1 ]; do curl $KONG_DP_PROXY_URL/sample/hello; echo; done
```

- Connecting to external service

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: route1-ext
  namespace: default
spec:
  type: ExternalName
  externalName: httpbin.org
EOF
```

- Ingress

```bash
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: route1
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /route1
          pathType: Prefix
          backend:
            service:
              name: route1-ext
              port:
                number: 80
EOF

```

- Consume the ingress

```bash
http $KONG_DP_PROXY_URL/route1/get
```

```bash
while [ 1 ]; do curl http://$KONG_DP_PROXY_URL/route1/get; echo; done
```

- Scaling the deployment

```bash
oc scale deployment.v1.apps/kong-dp-kong -n kong-dp --replicas=3
```

- Ingress Controller Policies

```bash
cat <<EOF | oc apply -f -
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

- Create the rate limiting plugin

```bash
cat <<EOF | oc apply -f -
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

- For deleting the plugin

```bash
oc delete kongplugin rl-by-minute
```

- Apply the plugin to Ingress

```bash
oc patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"rl-by-minute"}}}'
```

- Deleting the annotation

```bash
oc annotate ingress sampleroute -n default konghq.com/plugins-
```

- Test the plugins

```bash
http $KONG_DP_PROXY_URL/sampleroute/hello
```

- Create the API key plugin

```bash
cat <<EOF | oc apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: apikey
  namespace: default
plugin: key-auth
EOF

```

- Delete the plugin

```bash
oc delete kongplugin apikey
```

- Apply the plugin to the route

```bash
oc patch ingress sampleroute -n default -p '{"metadata":{"annotations":{"konghq.com/plugins":"apikey, rl-by-minute"}}}'
```

- Test the plugin

```bash
http $KONG_DP_PROXY_URL/sampleroute/hello
```

- Provisioning the key

```bash
oc create secret generic consumerapikey -n default --from-literal=kongCredType=key-auth --from-literal=key=kong-secret
```

- Deleting the key

```bash
oc delete secret consumerapikey -n default
```

- Creating a consumer with a key

```bash
cat <<EOF | oc apply -f -
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

- Delete the key

```bash
oc delete kongconsumer consumer1 -n default
```

- Consumer the route with the API key

```bash
http $KONG_DP_PROXY_URL/sampleroute/hello apikey:kong-secret
```

- Uninstall all the components

```bash
oc delete ingress sampleroute
oc delete ingress route1
oc delete service route1-ext
oc delete pvc --all -n kong --force --grace-period=0 

helm uninstall kong -n kong
helm uninstall kong-dp -n kong-dp

oc delete project kong
oc delete project kong-dp
oc delete -f https://bit.ly/kong-ingress-enterprise
```
