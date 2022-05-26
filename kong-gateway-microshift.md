# Kong Gateway on MicroShift
- [Prerequisites](#prerequisites)
- [Install MicroShift](#install-microshift)
- [Deploy Kong Gateway](#deploy-kong-gateway)
- [Clean Up](#clean-up)

## Prerequisites
Before starting, make sure you have at least:
- a supported 64-bit2 CPU architecture (amd64/x86_64, arm64, or riscv64)
- a supported OS (Linux, Mac, Windows)
- 2 CPU cores
- 2GB of RAM
- 1GB of free storage space for MicroShift 

## Install MicroShift
The [installation process](https://microshift.io/docs/getting-started/#using-microshift-for-application-development) for MicroShift varies across different Operating Systems, nevertheless, a container runtime is a requirement regardless of the underlying operating system.

<details>
  <summary>Linux</summary>
  Run MicroShift ephemerally using:

  ```bash
  command -v setsebool >/dev/null 2>&1 || sudo setsebool -P container_manage_cgroup true
  sudo podman run -d --rm --name microshift --privileged -v microshift-data:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
  ```

  Access the MicroShift environment on using the `oc` client installed on the host:

  ```bash
  sudo podman cp microshift:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig
  oc get all -A --kubeconfig ./kubeconfig
  ```
</details>

<details>
  <summary>Mac</summary>
  Run MicroShift ephemerally using:

  ```bash
  docker run -d --rm --name microshift --privileged -v microshift-data:/var/lib -p 6443:6443 quay.io/microshift/microshift-aio:latest
  ```

  Access the MicroShift environment on using the `oc` client installed on the host:

  ```bash
  docker cp microshift:/var/lib/microshift/resources/kubeadmin/kubeconfig ./kubeconfig
  oc get all -A --kubeconfig ./kubeconfig
  ```
</details>

Set the active `kubeconfig` to the local kubeconfig
```
export KUBECONFIG=./kubeconfig
```


**NOTE** - If you stop your work or want to continue later, stopping and restarting the MicroShift all-in-one container will bring some known issues with the CNI. It is recommended to `pause` and `unpause` the microshift container.
```
docker/podman pause microshift
docker/podman unpause microshift
```

## Deploy Kong Gateway
Create a namespace
```
oc new-project kong
```

Create a secret from the license
```
oc create secret generic kong-enterprise-license --from-file=./license -n kong 
```

Deploy the Gateway on OpenShift
```
oc apply -f https://bit.ly/k4k8s-enterprise-install
```

Wait for the ingress pod to be ready
```
oc wait --for=condition=ready --timeout=90s pod -l app=ingress-kong -n kong
```

Patch the kong-proxy service to type `ClusterIP` since a Load Balancer is not available.
```
oc patch svc/kong-proxy -p '{"spec":{"type":"NodePort"}}' -n kong
```

Expose the proxy service
```
oc expose svc/kong-proxy -n kong --hostname=localhost.local
```

Check the Proxy
```
export KONG_DP_PROXY_URL=$(oc get route kong-proxy -o jsonpath='{.spec.host}' -n kong)
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

## Clean Up
<details>
  <summary>Linux</summary>
  Prune Docker if you don't have anything important running:

  ```bash
  sudo podman system prune -a -f
  ```

  Prune the volumes if do not need them:

  ```bash
  sudo podman volume prune -f
  ```
</details>

<details>
  <summary>Mac</summary>
  Prune Docker if you don't have anything important running:

  ```bash
  docker system prune -a -f
  ```

  Prune the volumes if do not need them:

  ```bash
  docker volume prune -f
  ```
</details>
