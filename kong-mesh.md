- Download Kong Mesh
```
curl -L https://docs.konghq.com/mesh/installer.sh | sh -
```

- Run kong mesh
```
cd kong-mesh-1.6.0/bin
./kumactl install control-plane --cni-enabled --license-path=./license | oc apply -f -
oc get pod -n kong-mesh-system
```

- Verify the Installation
```
oc port-forward svc/kong-mesh-control-plane -n kong-mesh-system 5681:5681
```

- Apply scc  of non-root to ```kuma-metrics```
```
oc adm policy add-scc-to-group nonroot system:serviceaccounts:kong-mesh-metrics
oc adm policy add-scc-to-group node-exporter system:serviceaccounts:kuma-metrics
```

- Apply scc of anyuid to kuma-demo
```
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

- Clone the demo repo
```
git clone https://github.com/kumahq/kuma-counter-demo.git
```

- Install resources on kuma-demo ns
```
kubectl apply -f demo.yaml
```

- Validate the deployment
```
kubectl port-forward svc/demo-app -n kuma-demo 5000:5000
```

- Check side car injection has been performed
```
kubectl get namespace kuma-demo -oyaml
```

- Enable MTls and Traffic permissions
```
echo "apiVersion: kuma.io/v1alpha1
kind: Mesh
metadata:
  name: default
spec:
  mtls:
    enabledBackend: ca-1
    backends:
    - name: ca-1
      type: builtin" | kubectl apply -f -

```

- Delete the traffic permission
```
kubectl delete trafficpermission allow-all-default

```

- Apply the traffic permissions back again
```
echo "apiVersion: kuma.io/v1alpha1
kind: TrafficPermission
mesh: default
metadata:
  namespace: default
  name: allow-all-default
spec:
  sources:
    - match:
        kuma.io/service: '*'
  destinations:
    - match:
        kuma.io/service: '*'" | kubectl apply -f -

```

- Explore the traffic metrics
```
./kumactl install metrics | kubectl apply -f -  # With this step, grafana pods never errors out on initplugin with the message =>> wget: bad address 'github.com' 
```
