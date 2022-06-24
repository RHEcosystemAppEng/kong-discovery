# Gateway Usage

**TOC**
- [Install Operator](#install-operator)
- [Deploy Prereqs](#deploy-prereqs)
- [Deploy ControlPlane](#deploy-controlplane)
- [Uninstall](#uninstall)

## Install Operator

Create a subscription object to subscribe a namespace to the Red Hat OpenShift GitOps.

```yaml
oc apply -f -<<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: stable 
  installPlanApproval: Automatic
  name: openshift-gitops-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
EOF
```

Wait for the objects to be created in openshift-gitops namespace

```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/name=cluster --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=kam --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-application-controller --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-dex-server --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-redis --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-repo-server --timeout=180s -n openshift-gitops
oc wait --for=condition=ready pod -l app.kubernetes.io/name=openshift-gitops-server --timeout=180s -n openshift-gitops
```

Get the admin password for the Argo UI:

```bash
export ARGO_PW=$(oc get secret -n openshift-gitops openshift-gitops-cluster -ojsonpath='{.data.admin\.password}' | base64 -d)
```

Open the url in your browser and login to Argo UI, username "admin" and password equal to the value of `$ARGO_PW`

```bash
k get routes -n openshift-gitops openshift-gitops-server --template='{{ .spec.host }}'
```

keep the UI open for the rest of this doc.


## Deploy Prereqs

Think of this like a multi-stage deployment, we will first deploy the the prerequisite manifests like the namespace, web console customizations and the secret.

Create the license secret in kong namespace ( **for now**, next we will use Vault )

```bash
oc create secret generic kong-enterprise-license -n kong --from-file=license=license.json
```

The `validated-patterns/gateway/prereqs` contains the prereq manifests that we need to deploy before deploying the Kong Gateway Control Plane.

```yaml
oc apply -f -<<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0" # for the next steps
  name: prereqs
  namespace: openshift-gitops
spec:
  destination:
    namespace: default
    server: https://kubernetes.default.svc
  project: default
  source:
    directory:
      recurse: true
    path: validated-patterns/gateway/prereqs
    repoURL: https://github.com/cmwylie19/kong-discovery.git
    targetRevision: design-concept # branch
  syncPolicy:
    automated: # automatically sync repo changes
      prune: true
      selfHeal: true
EOF
```

Now, lets check and see if the `kong` ns has been created:

```bash
oc get ns | grep kong
```

output

```bash
kong Active   31s
```

Check the Argo UI to ensure `prereqs` is reporting healthy and synced.

Do a secondary check the argo application through the terminal to become more familiar

```bash
oc get application -n openshift-gitops prereqs
```

output

```bash
NAME              SYNC STATUS   HEALTH STATUS
prereqs           Synced        Healthy
```

Synced in this case means that the repo manifests match what is deployed in the cluster.


In this section, we deployed:
- Customized Argo Instance with Plugins
- kong namespace
- custom consolelink for kong docs
- the kong license secret, kong tls cluster-cert secret
- rbac clusterrole/clusterrolebinding for openshift-gitops-argocd-application-controller

## Deploy ControlPlane

In this section we deploy the ControlPlane

Render the Control Plane:

```bash
kustomize build validated-patterns/gateway/controlplane | kubectl apply -f - 
```

Wait for the Kong Control Plane to come up:
```bash
oc wait --for=condition=ready pod -l app.kubernetes.io/component=app,app.kubernetes.io/instance=kong -n kong --timeout=180s
```

You should see kong deployed in the control plane
```bash
oc get po -n kong
```

output

```bash
oc get po -n kong 
```

output

```
NAME                       READY   STATUS      RESTARTS   AGE
kong-kong-f6879f58-tbzn2   1/1     Running     0          25s
```
Check the `Application` to see the state of `kong-cp`

```bash
oc get application -n openshift-gitops
```

output

```bash
NAME      SYNC STATUS   HEALTH STATUS
kong-cp   Synced        Healthy
prereqs   Synced        Healthy
```


## Uninstall

Delete the Argo Application

```bash
oc delete application -n openshift-gitops --all 
```

```bash
# Get CSV
export CSV=$(oc get subs -n openshift-operators openshift-gitops-operator -oyaml | grep currentCSV | sed 's/currentCSV://g')

# Delete Subscription
oc delete subs openshift-gitops-operator -n openshift-operators 

# Delete CSV
oc delete csv $CSV -n openshift-operators
```
