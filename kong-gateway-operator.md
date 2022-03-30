# Kong Gateway using the Operator (CP/DP)
**WIP**   
The Kong Operator is a helm operator. The operator fields from the operator instance are turned into helm overrides. All possible fields for the operator can be found [here](https://github.com/Kong/kong-operator/blob/main/deploy/crds/charts_v1alpha1_kong_cr.yaml) and are the same as the helm values for this operator which can be found [here](https://github.com/Kong/kong-operator/blob/main/helm-charts/kong/values.yaml).  
  

- [Install the Operator](#install-operator-subscription)
- [Create Control Plane Secrets](#create-control-plane-secrets)
- [Deploy kong operator for Control Plane](#deploy-kong-operator-for-control-plane)
- [Expose Control Plane Services](#expose-control-plane-services)
- [Check the version](#check-the-version)
- [Configure Kong Manager Service](#configure-kong-manager-service)

## Install Operator Subscription
```
kubectl create -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kong-offline-operator
  namespace: openshift-operators
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: kong-offline-operator
  source: certified-operators
  sourceNamespace: openshift-marketplace
  startingCSV: kong.v0.10.0
EOF
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
      enabled: false
    rbac:
      enabled: false
    smtp:
      enabled: false
  env:
    cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
    cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
    database: postgres
    role: control_plane
  image:
    repository: kong/kong-gateway
    tag: 2.8.0.0-alpine
  ingressController:
    enabled: true
    image:
      repository: kong/kubernetes-ingress-controller
      tag: 2.2.1
    installCRDs: false
  manager:
    enabled: true
    type: NodePort
  postgresql:
    enabled: true
    postgresqlDatabase: kong
    postgresqlPassword: kong
    postgresqlUsername: kong
    securityContext:
      fsGroup: ""
      runAsUser: 1000660000
  proxy:
    enabled: true
    type: ClusterIP
  secretVolumes:
  - kong-cluster-cert
EOF
```


## Expose Control Plane Services
```
oc expose svc/kong-kong-admin -n kong
oc expose svc/kong-kong-manager -n kong
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
kubectl get routes -n kong kong-kong-admin -ojsonpath='{.status.ingress[0].host}'
```
output:
```
kong-kong-admin-kong.apps.kong-cwylie.fsi-env2.rhecoeng.com
```
Patch the deployment
```
kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"kong-kong-admin-kong.apps.kong-cwylie.fsi-env2.rhecoeng.com\" }]}]}}}}"
```

## Cleanup
Delete the Kong instance, subscription, and CSV from the `openshift-operators` namespace:
```
kubectl delete kong/kong -n kong

kubectl delete subs -n openshift-operators kong-offline-operator

kubectl delete csv -n openshift-operators kong.v0.10.0  

kubectl delete po,pvc -n kong --force --grace-period=0 --all

kubectl delete routes -n kong --all

kubectl delete secrets -n kong --all

kubectl delete clusterrolebinding kong-admin
```
