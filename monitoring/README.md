# Kong Gateway Plugins - Discovery

## Install demo-app on kuma-demo namespace

- Apply scc of anyuid to kuma-demo

```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

- Install resources on kuma-demo ns

```bash
kubectl apply -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml
```

## Install Kong Gateway - All-in-one DB Full

```bash
oc new-project kong
oc create secret generic kong-enterprise-license --from-file=license=./license.json -n kong
```

Generate a certificate that will be used to expose the TLS. Use that certificate to create
a secret

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong 

# I'm using my own postgres
oc new-app -n kong --template=postgresql-ephemeral --param=POSTGRESQL_USER=kong --param=POSTGRESQL_PASSWORD=kong123 --param=POSTGRESQL_DATABASE=kong
```

```bash
echo '{"cookie_name":"admin_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}' > admin_gui_session_conf
echo '{"cookie_name":"portal_session","cookie_samesite":"off","secret":"kong","cookie_secure":false,"storage":"kong"}' > portal_session_conf
oc create secret generic kong-session-config -n kong --from-file=admin_gui_session_conf --from-file=portal_session_conf
```

- Creating Kong Manager password

```bash
oc create secret generic kong-enterprise-superuser-password -n kong --from-literal=password=kong
```

### Deploy KONG

helm install kong kong/kong -n kong --values gateway-values.yaml

### Expose svcs

```bash
oc expose svc/kong-kong-proxy -n kong
oc expose svc/kong-kong-admin -n kong                                         
oc expose svc/kong-kong-manager -n kong
oc expose svc/kong-kong-portal -n kong
oc expose svc/kong-kong-portalapi -n kong
```

### Patch deployment with generated Routes

```bash
export KONG_ADMIN_URI=`oc get route kong-kong-admin --template='{{ .spec.host }}'`

kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"${KONG_ADMIN_URI}\" }, { \"name\" : \"KONG_PORTAL_API_URL\", \"value\": \"${KONG_ADMIN_URI}\" },{ \"name\" : \"KONG_PORTAL_GUI_HOST\", \"value\": \"${KONG_ADMIN_URI}\" }]}]}}}}"
```

### Access kong-manager

```bash
$ oc get route kong-kong-manager --template='{{ .spec.host }}'
http://kong-kong-manager-kong.apps-crc.testing/
```

Login as `kong_admin`/`kong`

## Expose the demo app

### Create Ingress and OCP Route

```bash
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" ingress.yaml | kubectl apply -f -
oc expose svc/kong-kong-proxy -n kong --name demo-app --port kong-proxy
```

### Check the demo app

Open in browser

```bash
xdg-open http://`oc get routes demo-app --template={{.spec.host}}`
```

## Monitoring

### InfluxDB

Deploy influxDB

```bash
oc new-app -n kong --docker-image=influxdb:1.8.4-alpine -e INFLUXDB_DB=kong --name=influxdb
```

Patch the kong-kong deployment to configure Vitals strategy to `influxdb`:

```bash
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_VITALS_STRATEGY\", \"value\": \"influxdb\" }, { \"name\" : \"KONG_VITALS_TSDB_ADDRESS\", \"value\": \"influxdb:8086\" }]}]}}}}"
```

When the redeployment is complete you can check in the _Vitals_ page the _Reports_ button. There you can configure and export the report based on the data stored in influxDB.

### Prometheus

Install Prometheus and Grafana operator from the OLM in the kong namespace or with the subscription yaml

```bash
oc apply -f olm-subscriptions.yaml
```

We have to enable the status API so let's update the Helm deployment.

**Note**: I have noticed a problem when loading the manager page with the status api enabled. The page takes a lot of time to load and is
not responsive

```bash
helm upgrade kong kong/kong -n kong --values gateway-with-status-values.yam
```

As we have RBAC enabled we cannot query the /metrics endpoint on the admin API because it requires
a custom header `kong-admin-token` that we cannot configure on Prometheus.
For that we enabled the status api in the installation. [Docs](https://docs.konghq.com/hub/kong-inc/prometheus/#accessing-the-metrics)

Create the `kong-kong-status` service for port 8100. That has a label `kong-metrics: kong-admin` we will use in the ServiceMonitor.

```bash
oc apply -f status-service.yaml
```

Create prometheus and servicemonitor.

```bash
oc apply -f prometheus.yaml
```

Check the status of the serviceMonitors. There should be only one Target that after a while should transition from `UNKNOWN` to `UP`

```
oc port-forward -n kong svc/prometheus-operated 9090
```

Now create the Prometheus KongClusterPlugin

```
oc apply -f prometheus-plugin.yaml
```

And annotate the frontend service to use the service

```
oc annotate svc frontend -n kuma-demo konghq.com/plugins=prometheus-plugin
```

#### Grafana

Install Grafana on the kong namespace

Create a Grafana instance with the Prometheus Datasource and the Kong Dashboard

```
oc apply -f grafana.yaml
```

Get the login credentials:

```bash
$ kubectl get secret -n kong grafana-admin-credentials -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'
GF_SECURITY_ADMIN_PASSWORD: yKSDuWQb5wOBPg==
GF_SECURITY_ADMIN_USER: admin
```

#### Validate the metrics

I have used the rate-limit plugin from ../kic/simple-rate-limiting.yaml and made a lot of requests until the rate limit is exeeded. Then in the Dashboard you can correlate the 
requests per second and confirm the 429 status codes start appearing when the limit of 10 requests per minute is reached.

## Clean up

### Remove Kuma Demo App

```bash
oc delete ns kuma-demo
```

### Remove Grafana and Prometheus

```bash
oc delete -f prometheus.yaml
oc delete -f grafana.yaml
oc delete -f olm-subscriptions.yaml
```

### Remove InfluxDB

```bash
oc delete svc,deployment influxdb

### Remove Kong Gateway

```bash
helm delete kong -n kong
oc delete ns kong
```

### Remove other permissions

```bash
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo
```
