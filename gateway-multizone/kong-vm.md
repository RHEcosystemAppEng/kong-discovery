# Kong in a VM

## Install Kong Mesh

- required ports

  - 22: SSH
  - 5681: HTTP rest API and GUI
  - 5682: HTTPS rest API and GUI 
  - 5685: gRPC for remote CP to connect to the Global CP

- download the Kuma Mesh CLI (this might change the home folder permissions, confirm it is 700)

curl -L https://docs.konghq.com/mesh/installer.sh | sh -

- add the CLI to the PATH (optional)

- copy the license to the home folder and start the mesh service

scp license.json ec2-user@<my-ec2vm.public.hostname>:~

- copy the configuration file

scp gateway-multizone/multizone-gcp-vm.conf.yaml ec2-user@<my-ec2vm.public.hostname>:~

- start the mesh

export KMESH_LICENSE_PATH=license.json
nohup kuma-cp run -c multizone-gcp-vm.conf.yaml &
echo $! > kong-cp-pid

- set up the mTLS

cat << EOF | kumactl apply -f -
type: Mesh
name: default
mtls:
  enabledBackend: ca-1
  backends:
    - name: ca-1
      type: builtin
EOF

- verify the installation

https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/config | jq .mode
"global"

https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/meshes/ | jq .
{
  "total": 1,
  "items": [
    {
      "type": "Mesh",
      "name": "default",
      "creationTime": "2022-06-07T14:44:34.371178619Z",
      "modificationTime": "2022-06-07T15:09:25.09694343Z",
      "mtls": {
        "enabledBackend": "ca-1",
        "backends": [
          {
            "name": "ca-1",
            "type": "builtin"
          }
        ]
      }
    }
  ],
  "next": null
}

- configure the [Remote control plane in OCP](../global-control-plane.md#install-the-mesh-control-plane-in-zone-1)

- validate the zone is added

https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/zones | jq .
{
  "total": 1,
  "items": [
    {
      "type": "Zone",
      "name": "kumadp1",
      "creationTime": "2022-06-07T14:54:13.430457198Z",
      "modificationTime": "2022-06-07T14:54:13.430457198Z",
      "enabled": true
    }
  ],
  "next": null
}

- deploy the [_magnanimo_ demo application](../global-control-plane.md#deploy-the-demo-apps)

- confirm the service is part of the mesh

https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/meshes/default/service-insights
HTTP/1.1 200 OK
Content-Length: 380
Content-Type: application/json
Date: Tue, 07 Jun 2022 15:17:00 GMT

{
    "items": [
        {
            "creationTime": "2022-06-07T14:44:53.321174721Z",
            "dataplanes": {
                "online": 1,
                "total": 1
            },
            "issuedBackends": {
                "ca-1": 1
            },
            "mesh": "default",
            "modificationTime": "2022-06-07T15:09:35.322566692Z",
            "name": "magnanimo_kuma-app_svc_4000",
            "status": "online",
            "type": "ServiceInsight"
        }
    ],
    "next": null,
    "total": 1
}

### Export the GLOBAL_SYNC var

The remote control planes need to know where the Global control plane is for that create the following environment variable
to be used during the remote control planes installation:

```bash
export GLOBAL_SYNC=ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5685
```

## Install Kong Gateway

- required ports

  - 22: SSH
  - 8444: Admin API TLS
  - 8445: Manager TLS
  - 8005: Cluster endpoint
  - 8006: Cluster Metrics endpoint

- Add Kong Repository

 curl https://download.konghq.com/gateway-2.x-amazonlinux-2/config.repo | sudo tee /etc/yum.repos.d/kong.repo

- Install kong

sudo yum install -y kong-enterprise-edition-2.8.1.1

- Install postgres 9.5 or greater

```bash
sudo yum install -y docker
sudo service docker enable
sudo service docker start
sudo docker run -d --rm -e POSTGRES_DB=kong -e POSTGRES_USER=kong -e POSTGRES_PASSWORD=kong123 -p 5432:5432 --name postgresql postgres

```

- Generate certificate

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
```

- Copy config file to the VM (kong.conf) to the root folder

```bash
scp gateway-multizone/kong.conf ec2-user@ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:~
```

- Bootstrap kong database

```bash
kong migrations bootstrap -c kong.conf 
```

- Start kong Gateway

```bash
kong start -c kong.conf
```

- Add license

```bash
$ https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8444/licenses payload=@license.json
HTTP/1.1 201 Created
...
```

- Check the API and Manager work

Open the Manager at https://ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8445/overview

```bash
https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8444 | jq .version
"2.8.1.1-enterprise-edition"
```

- Export the CLUSTER_URL and CLUSTER_TELEMETRY_URL to be used in the Data Plane installation

```bash
export CLUSTER_URL=ec2-13-38-19-167.eu-west-3.compute.amazonaws.com
export CLUSTER_TELEMETRY_URL=$CLUSTER_URL
```

## After installing the Data Plane

### Verify clustering is working

The Gateway should show the Data plane is part of the cluster

```bash
$ https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8444/clustering/status                                                                    
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

### Verify the mesh

The `kumadp1` zone should exist in the global control plane

```bash
https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/status/zones
HTTP/1.1 200 OK
Content-Length: 48
Content-Type: application/json
Date: Fri, 17 Jun 2022 12:20:41 GMT

[
    {
        "active": true,
        "name": "kumadp1"
    }
]
```

In the mesh you should also see the kong gateway as a service

```bash
$ https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:5682/meshes/default/service-insights | jq '.items[].name'
"kong-kong-proxy_kong-dp_svc_80"
"magnanimo_kuma-app_svc_4000"
```

### Access the application

- Create the service to access the `magnanimo` service

```bash
https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8444/services name=magnanimoservice url='http://magnanimo.kuma-app.svc.cluster.local:4000'
https --verify=false ec2-13-38-19-167.eu-west-3.compute.amazonaws.com:8444/services/magnanimoservice/routes name='magnanimoroute' paths:='["/magnanimo"]' 
```

- Try the service

```bash
https --verify=false `oc get route -n kong-dp kong-kong-proxy-tls --template='{{.spec.host}}'`/magnanimo                                                       
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

## Clean up

### Remove the Kong Gateway Control Plane

- Stop Kong

```bash
kong stop -p gateway/data/
```

- Uninstall kong rpm

```bash
sudo yum remove -y kong-enterprise-edition-2.8.1.1
```

- Delete the data directory

```bash
rm -rf gateway
```

- Delete the database (and dependencies)

```bash
sudo docker kill postgresql
sudo yum remove -y docker
```

### Remove the Kong Mesh Global Control Plane

- Stop the kuma-cp process

```bash
kill `cat kong-cp-pid`
rm kong-cp-pid
```

- Remove the mesh binaries

```bash
rm -rf kong-mesh-1.7.0
```
