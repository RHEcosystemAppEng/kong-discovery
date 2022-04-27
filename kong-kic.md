# Install Kong Kubernetes Ingress Controller

```bash
oc new-project kong
```

```

oc adm policy add-scc-to-user hostmount-anyuid -z kong-serviceaccount -n kong
```

Create secret with license

```bash
oc create secret generic kong-enterprise-license --from-file=license=./license.json
```

Generate certificates

```bash
kubectl create secret generic kong-enterprise-superuser-password -n kong --from-literal=password=kong
```

Install the ingress using a predefined yaml file

```
kubectl apply -f https://bit.ly/kong-ingress-enterprise
```

## Create ClusterIP services

This deployment is oriented to Kubernetes. For Openshift is better to replace the LoadBalancer services
with ClusterIP and then expose them through routes.

```
kubectl delete svc kong-admin kong-manager kong-proxy
kubectl apply -f kic/expose-kong-gateway.yaml
```

Set the ADMIN_API uri

```
KONG_ADMIN_IP=$(kubectl get route -n kong kong-admin --output=jsonpath='{.spec.host}')
kubectl patch deployment -n kong ingress-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"${KONG_ADMIN_IP}\" }]}]}}}}"
```

## Visit Kong Manager

Open in your browser

```
kubectl get routes -n kong kong-manager -ojsonpath='{.status.ingress[0].host}{"\n"}'
```

* User `kong_admin` password `kong`

## Make the Gateway join the Mesh

```
kubectl label namespace kong kuma.io/sidecar-injection=enabled
oc delete po --all -n kong
```

* After this step, the initContainer that performs some migration in Postgres doesn't work anymore because it is not part of the Mesh.

Allow communication between ingress-kong and postgres

```
oc apply -f kic/traffic_permission.yaml
```

Create the kuma-demo ingress
```
oc apply -f kic/kuma-demo-ingress.yaml
```