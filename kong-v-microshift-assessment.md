# Kind vs MicroShift

**Description**
_For integration testing and samples to deploy operators, kind clusters are being used currently. We need a small factor OpenShift to perform evaluation and evaluate the constraints and benefits of using microshift. Ideally, we would need a gist about the good experience and pain point w.r.t to kind clusters._

**TOC**
- [Comparison Table](#comparison-table)
- [Ingress Kind](#ingress-kind)
- [Multi-Cluster Kind](#multi-cluster-kind)
- [Multi-Node and Affinity Kind](#multi-node-and-affinity-kind)
- [Admission Controller Kind](#admission-controller-kind)
- [Ingress MicroShift](#ingress-microshift)
- [Multi-Cluster MicroShift](#multi-cluster-microshift)
- [Multi-Node and Affinity MicroShift](#multi-node-and-affinity-microshift)
- [Admission Controller MicroShift](#admission-controller-microshift)
- [Summary](#summary)

## Comparison Table

|     Test              | MicroShift   |    Kind     |
|      :---:            |    :----:    |    :---:    |
| Ingress Controller    |     ✅       |      ✅      |
| Multi Cluster         |     ✅       |      ✅      |
| Multi Node/Affinity   |     ❌       |      ✅      |
| Admission Controllers |     ❌       |      ✅      |

## Ingress Kind

For this test to pass, we must be able to use Ingress resources in our cluster.

We can create a simple config file to define `extraPortMappings`.
```yaml
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
```

Deploy Kong Ingress Controller (KIC)
```bash
kubectl apply -f https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/master/deploy/single/all-in-one-dbless.yaml
```

Apply `kind` specific patches to forward the `hostPorts` to the ingress controller, set taints and tolerations, and schedule it to the custom labeled node
```bash
kubectl patch deployment -n kong ingress-kong -p '{"spec":{"template":{"spec":{"containers":[{"name":"proxy","ports":[{"containerPort":8000,"hostPort":80,"name":"proxy","protocol":"TCP"},{"containerPort":8443,"hostPort":43,"name":"proxy-ssl","protocol":"TCP"}]}],"nodeSelector":{"ingress-ready":"true"},"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Equal","effect":"NoSchedule"},{"key":"node-role.kubernetes.io/master","operator":"Equal","effect":"NoSchedule"}]}}}}'
```

Apply kind specific patch to change `kong-proxy` service type to `NodePort`
```
kubectl patch service -n kong kong-proxy -p '{"spec":{"type":"NodePort"}}'
```


Wait for the ingress deployment to be ready
```bash
kubectl wait --for=condition=ready pod -l app=ingress-kong -n kong --timeout=180s
```

Deploy a simple nginx pod and service to later serve behind the ingress
```bash
kubectl run nginx --image=nginx --port=80 --expose
```

Wait for the nginx pod to be ready
```bash
kubectl wait --for=condition=ready pod -l run=nginx --timeout=180s
```

Create the Ingress to route to the nginx service
```bash
kubectl apply -f -<<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /nginx
          pathType: Prefix
          backend:
            service:
              name: nginx
              port:
                number: 80
EOF
```

Test the ingress by curling against the route for the `nginx` service
```bash
curl localhost/nginx
```

output
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

Delete the kind cluster
```bash
kind delete cluster --name=kind
```


## Multi-Cluster Kind

For this test to pass, both clusters should function independently.  

In this scenario, we will create two Kind Clusters: east and west.

We will create two clusters, east and west.

```bash
kind create cluster --name=east
kind create cluster --name=west
```

Set the current context to the east cluster
```bash
kubectl config use-context kind-east
```

Now, lets deploy an app in east cluster.

```yaml
oc apply -f -<<EOF
apiVersion: v1
data:
  index.html: |
    <html><body>Blue App in East Cluster</body></html>
kind: ConfigMap
metadata:
  creationTimestamp: null
  name: blue-site
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: blue
  name: blue
spec:
  containers:
  - image: nginx
    name: blue
    ports:
    - containerPort: 80
    resources: {}
    volumeMounts:
    - name: blue-site
      mountPath: /usr/share/nginx/html
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
  - name: blue-site
    configMap:
      name: blue-site
status: {}
---
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  name: blue
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: blue
status:
  loadBalancer: {}
EOF
```

Wait for Blue to be ready:

```bash
kubectl wait --for=condition=ready pod -l run=blue --timeout=180s
```

Port-forward the blue service to 3333 on the local node

```bash
kubectl port-forward svc/blue 3333:80
```

Curl the Blue app to ensure it works

```bash
curl localhost:3333
```

output

```html
<html><body>Blue App in East Cluster</body></html>
```

Change the current-context to the west cluster
```bash
kubectl config use-context kind-west
```

Deploy a green app in west cluster
```yaml
oc apply -f -<<EOF
apiVersion: v1
data:
  index.html: |
    <html><body>Green App in West Cluster</body></html>
kind: ConfigMap
metadata:
  creationTimestamp: null
  name: green-site
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: green
  name: green
spec:
  containers:
  - image: nginx
    name: green
    ports:
    - containerPort: 80
    resources: {}
    volumeMounts:
    - name: green-site
      mountPath: /usr/share/nginx/html
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
  - name: green-site
    configMap:
      name: green-site
status: {}
---
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  name: green
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: green
status:
  loadBalancer: {}
EOF
```

Wait for green to be ready:
```bash
oc wait --for=condition=ready pod -l run=green --timeout=180s
```

Port-forward the green service to 3333 on the local node

```bash
kubectl port-forward svc/green 3333:80
```

Curl the Green app to ensure it works

```bash
curl localhost:3333
```

output

```html
<html><body>Green App in West Cluster</body></html>
```

Destroy `kind-east` and `kind-west`
```bash
kind delete clusters --all
```

## Multi-Node and Affinity Kind

For this test to pass, a 3-node cluster must be created an a deployment with affinity must be used to place a pod on each node.

Create the kind cluster for this test
```yaml
cat <<EOF > config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

kind create cluster --name=east --config=config.yaml
```

Check the nodes:
```bash
kubectl get no
```

output
```bash
NAME                 STATUS   ROLES                  AGE   VERSION
east-control-plane   Ready    control-plane,master   49s   v1.21.1
east-worker          Ready    <none>                 17s   v1.21.1
east-worker2         Ready    <none>                 18s   v1.21.1
```

Create the nginx deployment with `podAnitAffinity` to schedule one pod per node, and a `toleration` to schedule on the control-plane.
```yaml
kubectl apply -f -<<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  creationTimestamp: null
  labels:
    app: affinity-test
  name: affinity-test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: affinity-test
  strategy: {}
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: affinity-test
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - affinity-test
                topologyKey: kubernetes.io/hostname
      tolerations:
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      containers:
      - image: nginx
        name: nginx
        resources: {}
status: {}
EOF
```

Wait for the deployment to be ready
```bash
kubectl wait --for=condition=ready pod -l app=affinity-test --timeout=180s
```

Now, lets make sure there are 3 replicas on 3 different nodes, including the controlplane, and the pods are ready
```
kubectl get po -o wide
```

output
```
NAME                             READY   STATUS    RESTARTS   AGE    IP           NODE                 NOMINATED NODE   READINESS GATES
affinity-test-7788b9bdff-pm5w7   1/1     Running   0          2m3s   10.244.0.5   east-control-plane   <none>           <none>
affinity-test-7788b9bdff-tzg66   1/1     Running   0          2m3s   10.244.1.2   east-worker2         <none>           <none>
affinity-test-7788b9bdff-zcgvw   1/1     Running   0          2m3s   10.244.2.2   east-worker          <none>           <none>
```

Delete the kind cluster
```bash
kind delete cluster --name=east
```

## Admission Controller Kind

For this test to pass, admission controllers should be used to block unsecure manifests from being deployed in the cluster.

We can create a simple config file to define our worker nodes, with PodSecurityPolicy enabled.
```yaml
cat <<EOF > config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
        extraArgs:
          enable-admission-plugins: NodeRestriction,PodSecurityPolicy
EOF
kind create cluster --name=east --config=config.yaml
```

First, create an `PodSecurityPolicy` to define which security contexts are allowed in the cluster. We are attemping to simulate the OpenShift Admission Controller. Notice `privileged` and `allowPrivilegeEscalation` are set to false.  

```yaml
kubectl apply -f -<<EOF
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
  annotations:
    # docker/default identifies a profile for seccomp, but it is not particularly tied to the Docker runtime
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default,runtime/default'
    apparmor.security.beta.kubernetes.io/allowedProfileNames: 'runtime/default'
    apparmor.security.beta.kubernetes.io/defaultProfileName:  'runtime/default'
spec:
  privileged: false
  # Required to prevent escalations to root.
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  # Allow core volume types.
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    # Assume that ephemeral CSI drivers & persistentVolumes set up by the cluster admin are safe to use.
    - 'csi'
    - 'persistentVolumeClaim'
    - 'ephemeral'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    # Require the container to run without root privileges.
    rule: 'MustRunAsNonRoot'
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      # Forbid adding the root group.
      - min: 1
        max: 65535
  readOnlyRootFilesystem: false
EOF
```

Lets attempt to run a privileged pod 
```bash
kubectl apply -f -<<EOF
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: test
  name: test
spec:
  containers:
  - image: nginx
    name: test
    resources: {}
    securityContext:
      privileged: true
  dnsPolicy: ClusterFirst
  restartPolicy: Always
EOF
```

output
```
Error from server (Forbidden): error when creating "STDIN": pods "test" is forbidden: PodSecurityPolicy: unable to admit pod: [pod.metadata.annotations[seccomp.security.alpha.kubernetes.io/pod]: Forbidden:  is not an allowed seccomp profile. Valid values are docker/default,runtime/default pod.metadata.annotations[container.seccomp.security.alpha.kubernetes.io/test]: Forbidden:  is not an allowed seccomp profile. Valid values are docker/default,runtime/default spec.containers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed]
```

Delete the kind cluster
```bash
kind delete cluster --name=east
```


## Ingress MicroShift

For this test to pass, we must be able to use Ingress resources in our cluster.

Create East Cluster

```bash
command -v setsebool >/dev/null 2>&1 || sudo setsebool -P container_manage_cgroup true
sudo podman run -d --rm --name microshift-east --privileged -v microshift-data:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
```

Get `kubeconfig` for East cluster

```bash
sudo podman cp microshift-east:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig-east
oc get all -A --kubeconfig ./kubeconfig-east
```

Wait until all pods are in a running state, _it could take ~3 minutes for the pods to come up_   

```bash
oc wait --for=condition=ready pod -l dns.operator.openshift.io/daemonset-dns=default -n openshift-dns --timeout=240s --kubeconfig ./kubeconfig-east

oc get po -A --kubeconfig ./kubeconfig-east
```

output

```text
NAMESPACE                       NAME                                  READY   STATUS    RESTARTS   AGE
kube-system                     kube-flannel-ds-tc7h8                 1/1     Running   0          2m33s
kubevirt-hostpath-provisioner   kubevirt-hostpath-provisioner-gzgl7   1/1     Running   0          116s
openshift-dns                   dns-default-rpbxm                     2/2     Running   0          2m33s
openshift-dns                   node-resolver-24sts                   1/1     Running   0          2m33s
openshift-ingress               router-default-6c96f6bc66-gs8gd       1/1     Running   0          2m34s
openshift-service-ca            service-ca-7bffb6f6bf-482ff           1/1     Running   0          2m37s
```

Set the active `kubeconfig` to the local kubeconfig
```
export KUBECONFIG=./kubeconfig-east
```

Deploy Kong Ingress Controller (KIC)
```bash
oc apply -f https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/master/deploy/single/all-in-one-dbless.yaml
```

Apply kind specific patch to change `kong-proxy` service type to `NodePort`
```
oc patch service -n kong kong-proxy -p '{"spec":{"type":"NodePort"}}'
```


Wait for the ingress deployment to be ready

```bash
oc wait --for=condition=ready pod -l app=ingress-kong -n kong --timeout=180s
```

Deploy an nginx pod and service to later serve behind the ingress

```bash
oc run nginx --image=nginx --port=80 --expose
```

Wait for the nginx pod to be ready
```bash
oc wait --for=condition=ready pod -l run=nginx --timeout=180s
```

Create the Ingress to route to the nginx service
```bash
oc apply -f -<<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /nginx
          pathType: Prefix
          backend:
            service:
              name: nginx
              port:
                number: 80
EOF
```

Get the `InternalIP` of the node

```bash
export IP=$(oc get no -ojsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
```

Get the `NodePort` used in the `kong-proxy` service

```bash
export PORT=$(oc get svc -n kong kong-proxy -ojsonpath='{ .spec.ports[0].nodePort }')
```


Test the ingress by curling against the internal-ip of the node

```bash
curl $IP:$PORT/nginx
```

output

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

Remove MicroShift `kubeconfig`

```bash
unset KUBECONFIG
rm -f kubeconfig-east
```

Remove Containers, Images and Volumes for MicroShift:
```bash
sudo podman rm -f microshift-east
sudo podman rmi -f quay.io/microshift/microshift-aio
sudo podman volume rm microshift-data
```

## Multi-Cluster MicroShift

For this test to pass, both clusters should function independently.  

In this scenario, we will create two MicroShift Clusters: east and west. We will copy the kubeconfigs so that both clusters are accessible. Note that we must use two different ports on the host but connect to port `6443` on the containers. In the case of the `green` cluster, we will need to change the `kubeconfig` to reflect that we are connecting through the cluster via port `6444` on the host. We will also use two different docker volumes.

Create East Cluster, running on port `6443` on the host with a volume of `microshift-data-west`
```bash
command -v setsebool >/dev/null 2>&1 || sudo setsebool -P container_manage_cgroup true
sudo podman run -d --rm --name microshift-east --privileged -v microshift-data-east:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
```

Get `kubeconfig` for East cluster
```bash
sudo podman cp microshift-east:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig-east
oc get all -A --kubeconfig ./kubeconfig-east
```

Wait until all pods are in a running state, _it could take ~3 minutes for the pods to come up_   

```bash
oc wait --for=condition=ready pod -l dns.operator.openshift.io/daemonset-dns=default -n openshift-dns --timeout=240s --kubeconfig ./kubeconfig-east

oc get po -A --kubeconfig ./kubeconfig-east
```

output

```text
NAMESPACE                       NAME                                  READY   STATUS    RESTARTS   AGE
kube-system                     kube-flannel-ds-tc7h8                 1/1     Running   0          2m33s
kubevirt-hostpath-provisioner   kubevirt-hostpath-provisioner-gzgl7   1/1     Running   0          116s
openshift-dns                   dns-default-rpbxm                     2/2     Running   0          2m33s
openshift-dns                   node-resolver-24sts                   1/1     Running   0          2m33s
openshift-ingress               router-default-6c96f6bc66-gs8gd       1/1     Running   0          2m34s
openshift-service-ca            service-ca-7bffb6f6bf-482ff           1/1     Running   0          2m37s
```

Point `kubeconfig` to the east cluster

```
export KUBECONFIG=./kubeconfig-east
```

Deploy a blue app in east cluster

```yaml
oc apply -f -<<EOF
apiVersion: v1
data:
  index.html: |
    <html><body>Blue App in East Cluster</body></html>
kind: ConfigMap
metadata:
  creationTimestamp: null
  name: blue-site
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: blue
  name: blue
spec:
  containers:
  - image: nginx
    name: blue
    ports:
    - containerPort: 80
    resources: {}
    volumeMounts:
    - name: blue-site
      mountPath: /usr/share/nginx/html
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
  - name: blue-site
    configMap:
      name: blue-site
status: {}
---
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  name: blue
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: blue
status:
  loadBalancer: {}
EOF
```

Wait for Blue to be ready:

```bash
oc wait --for=condition=ready pod -l run=blue --timeout=180s
```

Port-forward the blue service to 3333 on the local node

```bash
oc port-forward svc/blue 3333:80
```

Curl the Blue app to ensure it works

```bash
curl localhost:3333
```

output

```html
<html><body>Blue App in East Cluster</body></html>
```

Unset the `KUBECONFIG` to test the green cluster
```bash
unset KUBECONFIG
```

Create West Cluster, running on port `6444` on the host with a volume of `microshift-data-west`
```bash
sudo podman run -d --rm --name microshift-west --privileged -v microshift-data-west:/var/lib -p 6444:6443 quay.io/microshift/microshift-aio:latest
```

Get `kubeconfig` for West cluster, and update it to reflect that we will connect through port `6444`
```bash
sudo podman cp microshift-west:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig-west
sed -i 's/6443/6444/g' kubeconfig-west
oc get all -A --kubeconfig ./kubeconfig-west
```

Wait until all pods are in a running state, _it could take ~3 minutes for the pods to come up_   

```bash
oc wait --for=condition=ready pod -l dns.operator.openshift.io/daemonset-dns=default -n openshift-dns --timeout=240s --kubeconfig ./kubeconfig-west

oc get po -A --kubeconfig ./kubeconfig-west
```

output

```text
NAMESPACE                       NAME                                  READY   STATUS    RESTARTS   AGE
kube-system                     kube-flannel-ds-tc7h8                 1/1     Running   0          2m33s
kubevirt-hostpath-provisioner   kubevirt-hostpath-provisioner-gzgl7   1/1     Running   0          116s
openshift-dns                   dns-default-rpbxm                     2/2     Running   0          2m33s
openshift-dns                   node-resolver-24sts                   1/1     Running   0          2m33s
openshift-ingress               router-default-6c96f6bc66-gs8gd       1/1     Running   0          2m34s
openshift-service-ca            service-ca-7bffb6f6bf-482ff           1/1     Running   0          2m37s
```


Point `kubeconfig` to the west cluster
```
export KUBECONFIG=./kubeconfig-west
```

Deploy a green app in west cluster
```yaml
oc apply -f -<<EOF
apiVersion: v1
data:
  index.html: |
    <html><body>Green App in West Cluster</body></html>
kind: ConfigMap
metadata:
  creationTimestamp: null
  name: green-site
---
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: green
  name: green
spec:
  containers:
  - image: nginx
    name: green
    ports:
    - containerPort: 80
    resources: {}
    volumeMounts:
    - name: green-site
      mountPath: /usr/share/nginx/html
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
  - name: green-site
    configMap:
      name: green-site
status: {}
---
apiVersion: v1
kind: Service
metadata:
  creationTimestamp: null
  name: green
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: green
status:
  loadBalancer: {}
EOF
```

Wait for green to be ready:
```bash
oc wait --for=condition=ready pod -l run=green --timeout=180s
```

Port-forward the green service to 3333 on the local node

```bash
oc port-forward svc/green 3333:80
```

Curl the Green app to ensure it works

```bash
curl localhost:3333
```

output

```html
<html><body>Green App in West Cluster</body></html>
```

Remove MicroShift `kubeconfig`s
```bash
unset KUBECONFIG
rm -f kubeconfig-east kubeconfig-west
```

Remove Containers, Images and Volumes for MicroShift:
```bash
sudo podman rm -f microshift-east microshift-west
sudo podman rmi -f quay.io/microshift/microshift-aio
sudo podman volume rm microshift-data-east microshift-data-west 
```

## Multi-Node and Affinity MicroShift

For this test to pass, a 3-node cluster must be created an a deployment with affinity must be used to place a pod on each node.

This is out of scope [for a while](https://microshift.slack.com/archives/C025AQ0QD8B/p1655119431314959?thread_ts=1655119342.079369&cid=C025AQ0QD8B) in MicroShift. However, there is an [open PR](https://microshift.slack.com/archives/C025AQ0QD8B/p1655119431314959?thread_ts=1655119342.079369&cid=C025AQ0QD8B) that should work if you rebase the PR on top of the current main branch. I have ommitted this seeing as it is currently not part of the product.

## Admission Controller MicroShift

For this test to pass, admission controllers should be used to block unsecure manifests from being deployed in the cluster.

This is currently not [possible](https://microshift.slack.com/archives/C025AQ0QD8B/p1654516382661149). It may be an option in the future but for now they are focused on edge use cases. 


## Summary

**Multi-Cluster** Both MicroShift and Kind have the abililty to spin up and configure multiple local clusters. In many multi-cluster tools, like submariner, it is advantagous to be able to defined Cluster/Service CIDR ranges. Both Kind and MicroShift have this feature.
- [MicroShift](https://microshift.io/docs/user-documentation/configuring/)
- [Kind](https://kind.sigs.k8s.io/docs/user/configuration/)

**Multi-Node/Affinity** Kind is more mature in this area. MicroShift does not officially have a way to support this as of yet.

**Admission Controllers** Kind is more mature in this area. MicroShift does not officially have a way to support this as of yet.

**Ingress** Both Kind and MicroShift have the ability to use Ingress resources in the cluster.

**Conclusion** This document may seem like Kind is a more mature alternative than MicroShift, but that is not entirely true. MicroShift has a more "OpenShift" feel with routes. The functionality missing currently in MicroShift has been thought about, but not prioritized due to their focus being around productization for edge computing. Today, I would choose Kind, but in the future MicroShift could be a real contender. 

[go to top](#kind-vs-microshift)