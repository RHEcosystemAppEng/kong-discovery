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

- Install Kong Gateway
```bash
helm install kong kong/kong -n kong --values gateway-values.yaml
```

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

## Keycloak

Create the Keycloak specific namespace

```bash
oc create ns kong-keycloak
```

Deploy the keycloak operator on the `kong-keycloak` namespace.
You can use the _Openshift Console_ or create the subscription manually with this:

```bash
oc apply -f keycloak-subscription.yaml
```

Then create the Keycloak instance and resources.

```yaml
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" keycloak.yaml | kubectl apply -f -
```

The previous resource contains the following:

- Keycloak instance
- Realm `kong`
  - `customer` role definition
- Client definition: `kuma-demo-client`
- Users:
  - kermit/kong with role customer
  - bob/kong with no roles

### If you want to validate the configuration

Open in browser

```bash
xdg-open https://`oc get routes -n kong-keycloak keycloak --template={{.spec.host}}`/auth/admin/master/console/#/realms/kong
```

Extract the username/password:

```bash
kubectl get secret -n kong-keycloak credential-kong-keycloak -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'
ADMIN_PASSWORD: 93-14Jim2shH3A==
ADMIN_USERNAME: admin
```

You can validate the access_token retrieved from keycloak by doing the following:

```bash
http --verify=no -f https://`oc get routes -n kong-keycloak keycloak --template={{.spec.host}} `/auth/realms/kong/protocol/openid-connect/token client_id=kuma-demo-client grant_type=password username=kermit password=kong client_secret=client-secret | jq -r .access_token
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJLbktpd1FJbE5VcDA5Sk5ja3U3VFBjSHJEbWR1dW9aaGxyY0h5c0R4MXlNIn0.eyJleHAiOjE2NTM1NjQwNjAsImlhdCI6MTY1MzU2Mzc2MCwianRpIjoiMjE4YzY4N2MtMjI1MC00NDc0LWI5YjYtNWUyMWI2NjZlNmU0IiwiaXNzIjoiaHR0cHM6Ly9rZXljbG9hay1rb25nLWtleWNsb2FrLmFwcHMtY3JjLnRlc3RpbmcvYXV0aC9yZWFsbXMva29uZyIsInN1YiI6IjBhNjRkYTg3LTAwZDUtNGRmYy1iNWNlLTQxZmVmODYxMGYwYSIsInR5cCI6IkJlYXJlciIsImF6cCI6Imt1bWEtZGVtby1jbGllbnQiLCJzZXNzaW9uX3N0YXRlIjoiMjI4YmE0MGUtZmU5OS00M2VjLTlmYjMtZGQ3M2JhZjMyYWRiIiwic2NvcGUiOiIiLCJzaWQiOiIyMjhiYTQwZS1mZTk5LTQzZWMtOWZiMy1kZDczYmFmMzJhZGIiLCJyb2xlcyI6WyJjdXN0b21lciJdfQ.eylu9eOzeQEh-Aal0Gmu-d8snqwMoHJZcaVGuTyzKTCOImQVvbau_z8xPAFjwyspd6E00qdLE-INF8bowJl-PirPZ4F4NsWki_un9-n8zr9oNQgof5Arfy6E0oYf2xDII9bS8oU_NhIR0vf0UxEMElxI7sgN25d4pq6NEtH7oBmqqs8QXbCt0Zupfmc0FRc0eufGhO3nF_Jn1zTb2b49sDnnKIkD8-mAxYWw9C683KOkqu45GzsI4EwiO3bh3LJ9i8CzFt_-TtAYR1adCR8t2zSRlKHA7VLmC-0cbNmtj66iBOg04OVuCQuyToI15g3dnl3J78RdP1hYuAVxIqL4xg
```

Then you can go to jwt.io and paste the access_token, you should see something like this:

```json
{
  "exp": 1653564060,
  "iat": 1653563760,
  "jti": "218c687c-2250-4474-b9b6-5e21b666e6e4",
  "iss": "https://keycloak-kong-keycloak.apps-crc.testing/auth/realms/kong",
  "sub": "0a64da87-00d5-4dfc-b5ce-41fef8610f0a",
  "typ": "Bearer",
  "azp": "kuma-demo-client",
  "session_state": "228ba40e-fe99-43ec-9fb3-dd73baf32adb",
  "scope": "",
  "sid": "228ba40e-fe99-43ec-9fb3-dd73baf32adb",
  "roles": [
    "customer"
  ]
}
```

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

The application is not secured.

## Authentication/Authorization

We're going to create an openid-connect plugin that only allows authenticated users
with the `customer` role to access the application.

```bash
# Create the plugin
OCP_DOMAIN=`oc get ingresses.config/cluster -o jsonpath={.spec.domain}`
sed -e "s/\${i}/1/" -e "s/\$OCP_DOMAIN/$OCP_DOMAIN/" openidc-keycloak-plugin.yaml | kubectl apply -f -
# Annotate the service to use the plugin
oc annotate svc frontend -n kuma-demo konghq.com/plugins=keycloak-auth-plugin
```

Check the `roles_required` array in the Plugin

```yaml
  roles_required:
  - customer
```

### Check the demo app is now secured

Open in browser

```bash
xdg-open http://`oc get routes demo-app --template={{.spec.host}}`
```

Login as `kermit` with password `kong` --> access should be granted

Login as `bob` with password `kong` --> access should be forbidden

## Clean up

### Remove Keycloak

```bash
oc delete -f keycloak.yaml
oc delete -f keycloak-subscription.yaml
oc delete ns kong-keycloak
```

### Remove Kuma Demo App

```bash
oc delete ns kuma-demo
```

### Remove Kong Gateway

```bash
helm delete kong -n kong
oc delete ns kong
```

### Remove other permissions

```bash
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo
```
