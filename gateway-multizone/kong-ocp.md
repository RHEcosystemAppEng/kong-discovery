# Kong Multizone OCP

In this document I will describe how to integrate:

- Kong Mesh Remote Control Plane running on OCP with a Kong Mesh Global Control Plane running on a VM
- Kong Gateway Data Plane running on OCP with a Kong Gateway Control Plane running on a VM

This document assumes the VM side is installed following the [Kong in a VM](kong-vm.md#kong-in-a-vm)

## Install Kong Gateway Data Plane

- Create the `kong-dp` namespace

```bash
oc new-project kong-dp
```

- Create the secret with the license

```bash
kubectl create secret generic kong-enterprise-license -n kong-dp --from-file=license=./license.json 
secret/kong-enterprise-license created

```

- Create the secret with the cluster keys

```bash
scp -i "rromerom2.pem" rromerom@ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:~/cluster.crt .
scp -i "rromerom2.pem" rromerom@ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:~/cluster.key .
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp
```

- Add the Data Plane to the Mesh

```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kong-dp
oc annotate namespace kong-dp kuma.io/sidecar-injection=enabled
```

- Define the cluster and cluster telemetry endpoints

```bash
export CLUSTER_URL=ec2-35-180-211-252.eu-west-3.compute.amazonaws.com
```

- Install the Gateway DP

```bash
sed -e 's/\$CLUSTER_URL/'"$CLUSTER_URL"'/' -e 's/\$CLUSTER_TELEMETRY_URL/'"$CLUSTER_TELEMETRY_URL"'/' gateway-multizone/dp-values.yaml  | helm install kong -n kong-dp kong/kong -f -
```

- Check the Data Plane is part of the cluster:

```bash
$ https --verify=false ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:8444/clustering/status                                                                    
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Connection: keep-alive
Content-Length: 865
Content-Type: application/json; charset=utf-8
Date: Wed, 08 Jun 2022 15:01:47 GMT
Deprecation: true
Server: kong/2.8.1.1-enterprise-edition
X-Kong-Admin-Latency: 1
X-Kong-Admin-Request-ID: OfB5KNb6HFY3NVgyzlvcntaVFaVS6b8a

{
    "1a594e26-d921-4d8f-ba95-1b3e41b174e4": {
        "config_hash": "c5cb18462bb37e133d2394cae7151737",
        "hostname": "kong-kong-76d96975f6-9gf95",
        "ip": "13.36.159.89",
        "last_seen": 1654685986
    }
}
```

- In the mesh you should also see the kong gateway as a service

```bash
$ https --verify=false ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:5682/meshes/default/service-insights | jq '.items[].name'
"kong-kong-proxy_kong-dp_svc_80"
"magnanimo_kuma-app_svc_4000"
```

- Now let's expose the kong proxy routes

```bash
oc expose svc kong-kong-proxy -n kong-dp --port=http
oc create route passthrough kong-kong-proxy-tls --port=kong-proxy-tls --service=kong-kong-proxy -n kong-dp
```

- And create the service to access the `magnanimo` service

```bash
https --verify=false ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:8444/services name=magnanimoservice url='http://magnanimo.kuma-app.svc.cluster.local:4000'
https --verify=false ec2-35-180-211-252.eu-west-3.compute.amazonaws.com:8444/services/magnanimoservice/routes name='magnanimoroute' paths:='["/magnanimo"]' 
```

- Try the service

```bash
https --verify=false kong-kong-proxy-tls-kong-dp.apps.kong-ocp.o1wf.p1.openshiftapps.com/magnanimo                                                       
HTTP/1.1 200 OK
Connection: keep-alive
Content-Length: 22
Content-Type: text/html; charset=utf-8
Date: Wed, 08 Jun 2022 15:08:49 GMT
Server: Werkzeug/1.0.1 Python/3.8.3
Via: kong/2.8.1.1-enterprise-edition
X-Kong-Proxy-Latency: 10
X-Kong-Upstream-Latency: 2

Hello World, Magnanimo
```

- You can check the vitals are updated in the Gateway CP GUI