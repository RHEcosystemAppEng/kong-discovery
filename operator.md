
- Create namespace
```
oc create namespace openshift-redhat-marketplace
```

-  Create Red Hat Marketplace Subscription

```
oc create namespace openshift-redhat-marketplace
```

- Create Red Hat Marketplace Kubernetes Secret
```
oc create secret generic redhat-marketplace-pull-secret -n openshift-redhat-marketplace --from-literal=PULL_SECRET=<<PULL SECRET VALUE>
```

- Add the Red Hat Marketplace pull secret to the global pull secret on the cluster

```
curl -sL https://marketplace.redhat.com/provisioning/v1/scripts/update-global-pull-secret | bash -s <<PULL SECRET VALUE>
```

- Install the operator
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

- Install the konnect control plane
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
      runAsUser: 1000680000
  proxy:
    enabled: true
    type: ClusterIP
  secretVolumes:
  - kong-cluster-cert
EOF
```