# Kuma Service Mesh Global with Control Plane

This document describes the use of the Kuma Global Control Plane. The Global Control Plane is a way
of deploying the Mesh Control Plane that centralizes the distribution of the license and the Mesh Management
itself.

The Kuma Remote Control Planes will join the Global Control Plane upon deployment and define specific zones.

The 2 openshift clusters will be named as follows:

- kong-global: Contains the Kong Gateway CP and the Kuma Mesh Global CP
- kong-dp1: Contains the Kong Gateway DP and the frontend (magnanimo)

 As this document involves multiple contexts in different OCP clusters you might consider using [kubectx](https://github.com/ahmetb/kubectx)

## Installing the Kong Gateway CP

Let's start by installing the Kong Gateway CP in the `kong-global` cluster.

### Install Kong Gateway CP

- create ns kong

```bash
oc create ns kong
```

- create license secret

```bash
oc create secret generic kong-enterprise-license --from-file=license=./license.json -n kong
```

- create cert + secret

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong
```

- install custom postgres

```bash
oc new-app -n kong --template=postgresql-ephemeral --param=POSTGRESQL_USER=kong --param=POSTGRESQL_PASSWORD=kong123 --param=POSTGRESQL_DATABASE=kong
```

- install helm gateway-multizone/cp-values.yaml

```bash
helm install kong -n kong kong/kong -f gateway-multizone/cp-values.yaml       
```

- expose svc admin

```bash
oc expose svc kong-kong-admin -n kong
oc expose svc kong-kong-manager -n kong
```

- create secure routes

```bash
oc create route passthrough kong-kong-manager-tls --port=kong-manager-tls --service=kong-kong-manager -n kong
oc create route passthrough kong-kong-admin-tls --port=kong-admin-tls --service=kong-kong-admin -n kong
```

- update the ADMIN URI in the deployment

```bash
oc patch deploy -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"${GW_CP_URL}\" }]}]}}}}"
```

- save the cluster/clustertelemetry endpoints for later

```bash
export CLUSTER_URL=$(oc get svc kong-kong-cluster -ojson | jq -r '.status.loadBalancer.ingress[].hostname')
export CLUSTER_TELEMETRY_URL=$(oc get svc kong-kong-clustertelemetry -ojson | jq -r '.status.loadBalancer.ingress[].hostname')
```

- check the management UI is working at:

```bash
oc get route -n kong kong-kong-manager --template='{{.spec.host}}'
```

- check the admin endpoint is available

```bash
http `oc get route -n kong kong-kong-admin --template='{{.spec.host}}'` | jq .version
"2.8.1.1-enterprise-edition"
```

- export the Gateway ControlPlane endpoint to use it later

```bash
export GW_CP_URL=$(oc get route -n kong kong-kong-admin --template='{{.spec.host}})
${GW_CP_URL}
```

## Installing the Mesh in Openshift

For the alternate installation on a VM refer to [Kong in a VM](./gateway-multizone/kong-vm.md#kong-in-a-vm)

### Install Mesh Global Control Plane

```bash
kumactl install control-plane --cni-enabled --mode=global --license-path=./license.json | oc apply -f -
```

If running Kong Mesh in a multi-zone deployment, the file must be passed to the global kuma-cp. In this mode, Kong Mesh automatically synchronizes the license to the remote kuma-cp, therefore this operation is only required on the global kuma-cp.

Enable TLS for the default mesh

```bash
kubectl apply -f mesh/mtls.yaml -n kong-mesh-system
```

Expose the svc

```bash
oc create route passthrough -n kong-mesh-system kong-mesh-control-plane --service=kong-mesh-control-plane --port=https-api-server 
```

Check it is working

```bash
$ https --verify=false `oc get route kong-mesh-control-plane -n kong-mesh-system -ojson | jq -r .spec.host`/config | jq .mode
"global"
```

Create the Global Remote Sync route and extract the endpoint:

```bash
oc create route passthrough kong-mesh-global-zone-sync --service=kong-mesh-global-zone-sync --port=global-zone-sync -n kong-mesh-system
export GLOBAL_SYNC=$(oc get route -n kong-mesh-system kong-mesh-global-zone-sync --template='{{ .spec.host }}'):443
```

### Install the Mesh Control Plane in Zone 1

Login to the `kong-dp1` cluster

```bash
kumactl install control-plane --cni-enabled --mode=zone --zone=kumadp1 --ingress-enabled --kds-global-address grpcs://${GLOBAL_SYNC} | oc apply -f -
```

Wait until pods are ready

```bash
$ oc wait --for=condition=ready pod -l app.kubernetes.io/name=kong-mesh -n kong-mesh-system --timeout=180s                                            
pod/kong-mesh-control-plane-7d478b859-pkmrr condition met
pod/kong-mesh-ingress-75559d7644-qtbwp condition met
```

Check the zone is discovered in the global. Connect to the global control plane cluster to get the route

```bash
http `oc get route kong-mesh-control-plane -n kong-mesh-system -ojson | jq -r .spec.host`/status/zones
HTTP/1.1 200 OK
cache-control: private
content-length: 48
content-type: application/json
date: Fri, 03 Jun 2022 15:54:07 GMT
set-cookie: 559045d469a6cf01d61b4410371a08e0=a2d29fef296bbefe83902b97d4268a00; path=/; HttpOnly

[
    {
        "active": true,
        "name": "kumadp1"
    }
]
```

### Install Kong Gateway DP

- create ns kong-dp

```bash
oc create ns kong-dp
```

- create license secret

```bash
oc create secret generic kong-enterprise-license --from-file=license=./license.json -n kong-dp
```

- create certificate secret using the existing same certs we used in the control plane

```bash
oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp
```

- add the serviceaccount to the anyuid scc so the sidecars can be created and annotate the namespace.
That will allow the pod to be created together with the sidecar

```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kong-dp
kubectl label namespace kong-dp kuma.io/sidecar-injection=enabled
```

- install the Data Plane. Use the appropriate endpoints depending on the Control plane install (VM/OCP)

```bash
sed -e 's/\$CLUSTER_URL/'"$CLUSTER_URL"'/' -e 's/\$CLUSTER_TELEMETRY_URL/'"$CLUSTER_TELEMETRY_URL"'/' gateway-multizone/dp-values.yaml | helm install kong -n kong-dp kong/kong -f -
```

- wait until pods are ready

```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/name=kong -n kong-dp --timeout=180s              
pod/kong-kong-69f75fd99c-hgd9m condition met
```

- expose proxy routes (http/https)

```bash
oc expose svc kong-kong-proxy -n kong-dp --port=kong-proxy
oc create route passthrough kong-kong-proxy-tls --port=kong-proxy-tls --service=kong-kong-proxy -n kong-dp
```

- check clustering

**VM installation**: Refer to [Verify clustering is working](./gateway-multizone/kong-vm.md#verify-clustering-is-working)

```bash
http ${GW_CP_URL}/clustering/status
```

- check proxy

```bash
http `oc get route -n kong-dp kong-kong-proxy --template='{{ .spec.host }}'`/
```

Export the Gateway DataPlane endpoint to use it later:

```bash
export GW_DP_URL=$(oc get route -n kong-dp kong-kong-proxy-tls --template='{{.spec.host}}')
```

## Deploy the demo apps

### Deploy Magnanimo on DP1

```bash
oc create ns kuma-app
oc annotate namespace kuma-app kuma.io/sidecar-injection=enabled
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kuma-app
oc apply -f gateway-multizone/magnanimo.yaml -n kuma-app
```

Wait until the application is ready

```bash
oc wait --for=condition=ready pod -l app=magnanimo -n kuma-app --timeout=180s                                                  
pod/magnanimo-86c978654b-pcxw7 condition met
```

### Deploy Benigno on DP1

```bash
oc apply -f gateway-multizone/benigno.yaml -n kuma-app
```

Wait until the application is ready

```bash
oc wait --for=condition=ready pod -l app=benigno -n kuma-app --timeout=180s                                                  
pod/benigno-v1-5b5cdc5b5b-hpn28 condition met
```

Check the Mesh control plane the the service is discovered, it can be done from the UI
or using the `/meshes/default/service-insights` endpoint.

```
"benigno_kuma-app_svc_5000"
"kong-kong-proxy_kong-dp_svc_80"
"magnanimo_kuma-app_svc_4000"
```

### Create the service and route

**VM installation**: Refer to [Access the application](./gateway-multizone/kong-vm.md#access-the-application)

Let's create the service and the route in the Gateway Control Plane `kong-global`

```bash
http ${GW_CP_URL}/services name=magnanimoservice url='http://magnanimo.kuma-app.svc.cluster.local:4000'
http ${GW_CP_URL}/services/magnanimoservice/routes name='magnanimoroute' paths:='["/magnanimo"]'
```

Now we should be able to query the service in the Gateway DataPlane endpoint

```bash
$ https --verify=false ${GW_DP_URL}/magnanimo/hello
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 22
Content-Type: text/html; charset=utf-8
Date: Fri, 17 Jun 2022 14:24:35 GMT
Server: Werkzeug/1.0.1 Python/3.8.3
Via: kong/2.8.1.1-enterprise-edition
X-Kong-Proxy-Latency: 12
X-Kong-Upstream-Latency: 2

Hello World, Magnanimo: 2022-06-17 14:25:43.599616
```

```bash
$ https --verify=false ${GW_DP_URL}/magnanimo/hw3
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 49
Content-Type: text/html; charset=utf-8
Date: Fri, 17 Jun 2022 14:25:03 GMT
Server: Werkzeug/1.0.1 Python/3.8.3
Via: kong/2.8.1.1-enterprise-edition
X-Kong-Proxy-Latency: 2
X-Kong-Upstream-Latency: 16

Hello World, Benigno - 2022-06-17 14:25:03.859064
```

## Set specific traffic permissions

Delete the `allow-all-default` permission

```bash
kumactl delete traffic-permissions allow-all-default
```

Create a specific traffic-permission for the gateway

```bash
cat << EOF | kumactl apply -f -
type: TrafficPermission
name: gateway-all-traffic
mesh: default
sources:
  - match:
      kuma.io/service: 'kong-kong-proxy_kong-dp_svc_80'
destinations:
  - match:
      kuma.io/service: '*'
EOF
```

Now let's allow traffic between `magnanimo` and `benigno`

```bash
cat << EOF | kumactl apply -f -
type: TrafficPermission
name: magnanimo-to-benigno
mesh: default
sources:
  - match:
      kuma.io/service: 'magnanimo_kuma-app_svc_4000'
destinations:
  - match:
      kuma.io/service: 'benigno_kuma-app_svc_5000'
EOF
```

Confirm the application works again

```bash
https --verify=false ${GW_DP_URL}/magnanimo/hw3
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 49
Content-Type: text/html; charset=utf-8
Date: Fri, 17 Jun 2022 15:18:10 GMT
Server: Werkzeug/1.0.1 Python/3.8.3
Via: kong/2.8.1.1-enterprise-edition
X-Kong-Proxy-Latency: 11
X-Kong-Upstream-Latency: 19

Hello World, Benigno - 2022-06-17 15:18:10.933966
```

## Clean up

### Remove demo app

```bash
oc annotate namespace kuma-app kuma.io/sidecar-injection-
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-app
oc delete -f gateway-multizone/magnanimo.yaml
oc delete -f gateway-multizone/benigno.yaml
oc delete ns kuma-app
```

### Remove the Kong Data Plane

```bash
kubectl label namespace kong-dp kuma.io/sidecar-injection-
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kong-dp
helm delete kong -n kong-dp
oc delete ns kong-dp
```

### Remove the Kuma Remote Control Plane

```bash
kumactl install control-plane --cni-enabled --mode=zone --zone=kumadp1 --ingress-enabled --kds-global-address grpcs://${GLOBAL_SYNC} | oc delete -f -
```

### Remove the Kong Control Plane

**VM installation**: Refer to [Remove the Kong Gateway Control Plane](./gateway-multizone/kong-vm.md#remove-the-kong-gateway-control-plane)

```bash
helm delete kong -n kong
oc delete ns kong
```

### Remove the Kuma Global Control Plane

**VM installation**: Refer to [Remove the Kong Mesh Global Control Plane](./gateway-multizone/kong-vm.md#remove-the-kong-mesh-global-control-plane)

```bash
kumactl install control-plane --cni-enabled --mode=global --license-path=./license.json | oc delete -f -
```
