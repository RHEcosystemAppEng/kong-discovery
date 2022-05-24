- [Kong Konnect Enterprise Hybrid Mode](#kong-konnect-enterprise-hybrid-mode)
  - [Reference Architecture](#reference-architecture)
- [OpenShift Installation and Google Cloud settings](#openshift-installation-and-google-cloud-settings)
  - [Creating the OpenShift Cluster](#creating-the-openshift-cluster)
  - [Quotas](#quotas)
  - [Checking the Installation](#checking-the-installation)
- [Kong Konnect Enterprise Control Plane](#kong-konnect-enterprise-control-plane)
  - [Portainer installation](#portainer-installation)
  - [Portainer checking](#portainer-checking)
  - [Generating Private Key and Digital Certificate for CP/DP communications](#generating-private-key-and-digital-certificate-for-cpdp-communications)
  - [Configure PostgreSQL database](#configure-postgresql-database)
  - [Run bootstraping](#run-bootstraping)
  - [Configure Kong Control Plane](#configure-kong-control-plane)
  - [Configure Kong workspace](#configure-kong-workspace)
  - [Check Kong Admin API and Proxy ports](#check-kong-admin-api-and-proxy-ports)
  - [Restart container](#restart-container)
  - [Test the Control Plane](#test-the-control-plane)
- [Kong Konnect Enterprise Data Plane - OpenShift](#kong-konnect-enterprise-data-plane---openshift)
  - [Kubeconfig environment variable](#kubeconfig-environment-variable)
  - [Check Kubernetes context which should be pointed to OpenShift cluster](#check-kubernetes-context-which-should-be-pointed-to-openshift-cluster)
  - [Create OpenShift project](#create-openshift-project)
  - [Kong Enterprise Secrets](#kong-enterprise-secrets)
  - [Installing Kong Konnect Enterprise Data Plane with Kong Operator](#installing-kong-konnect-enterprise-data-plane-with-kong-operator)
  - [Create Catalog Source](#create-catalog-source)
  - [Check Catalog Source](#check-catalog-source)
  - [Create Subscription](#create-subscription)
  - [Download Kong Helm Charts](#download-kong-helm-charts)
  - [Configure Kong Konnect Enterprise Chart (konnect-dp.yaml)](#configure-kong-konnect-enterprise-chart-konnect-dpyaml)
  - [Apply the Kong declaration](#apply-the-kong-declaration)
  - [Checking the deployment](#checking-the-deployment)
  - [Checking pods](#checking-pods)
  - [Checking the Data Plane from the Control Plane](#checking-the-data-plane-from-the-control-plane)
  - [Defining a Service and a Route](#defining-a-service-and-a-route)
  - [Checking the Proxy](#checking-the-proxy)
  - [Data plane route test](#data-plane-route-test)
  - [Deleting Kong Konnect Data Plane](#deleting-kong-konnect-data-plane)
  - [Scaling the Deployment](#scaling-the-deployment)
- [ANOTHER SECTION WILL ADD LATER](#another-section-will-add-later)

# Kong Konnect Enterprise Hybrid Mode

One of the most powerful capabilities provided by Kong Konnect Enterprise is the support for Hybrid deployments. In other words, it implements distributed API Gateway Clusters with multiple instances running on several environments at the same time.

Moreover, Kong Konnect Enterprise provides a new topology option, named Hybrid Mode, with a total separation of the Control Plane (CP) and Data Plane (DP). That is, while Control Plane is responsible for administration tasks, the Data Plane is exclusively used by API Consumers.

Please, refer to the following link to read more about the Hybrid deployment: <https://docs.konghq.com/enterprise/2.4.x/deployment/hybrid-mode/>

## Reference Architecture

Here's a Reference Architecture implemented with Red Hat products and services:

The Control Plane runs as a Docker container on an RHEL instance.
The Data Plane runs on an OpenShift Cluster.

Considering the capabilities provided by the Kubernetes platform, running Data Planes on this platform delivers a powerful environment. Here are some capabilities leveraged by the Data Plane on Kubernetes:
High Availability: One of the main Kubernetes' capabilities is "Self-Healing". If a "pod" crashes, Kubernetes takes care of it, reinitializing the "pod".
Scalability/Elasticity: HPA ("Horizontal Pod Autoscaler") is the capability to initialize and terminate "pod" replicas based on previously defined policies. The policies define "thresholds" to tell Kubernetes the conditions where it should initiate a brand new "pod" replica or terminate a running one.
Load Balancing: The Kubernetes Service notion defines an abstraction level on top of the "pod" replicas that might have been up or down (due HPA policies, for instance). Kubernetes keeps all the "pod" replicas hidden from the "callers" through Services.

Important remark #1: this tutorial is intended to be used for labs and PoC only. There are many aspects and processes, typically implemented in production sites, not described here. For example: Digital Certificate issuing, Cluster monitoring, etc.

Important remark #2: the deployment is based on Kong Konnect Enterprise. Please contact Kong to get a Kong Konnect Enterprise trial license to run this lab.

# OpenShift Installation and Google Cloud settings

Login to gcloud or use Cloud Shell

```bash
gcloud auth login
```

Create Google Cloud project

```bash
export GCP_PROJECT_NAME=konghq-public
export GCP_ZONE=us-central1-a
export GCP_VM_NAME=kong-konnect-cp
gcloud projects create $GCP_PROJECT_NAME --name $GCP_PROJECT_NAME
gcloud config set project konghq-public
```

Creating GCP Public and Private Keys

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/google_rsa
```

```bash
eval "$(ssh-agent -s)"
```

```bash
ssh-add ~/.ssh/google_rsa
```

## Creating the OpenShift Cluster

Use Openshift docs for GCP

<https://docs.openshift.com/container-platform/latest/installing/installing_gcp/installing-gcp-default.html#installing-gcp-default>

## Quotas

You might need to set new quotas for Disks. Go to Quotas on the IAM & Admin page

## Checking the Installation

```bash
oc login -u kubeadmin -p <PASSWORD> <OCP_API_URL>
```

```bash
oc get nodes
oc get clusteroperators
```

# Kong Konnect Enterprise Control Plane

NOTES:
Check with [product life](https://access.redhat.com/support/policy/updates/errata/) cycle if we can use RHEL 8 or RHEL 9

Create a new Red Hat Enterprise Linux 7 VM Instance and assign tag `kong-konnect-cp` to VM' NIC.

The Control Plane will be running on a specific RHEL 7 VM as the Data Plane will be deployed on the OpenShift Cluster.

```bash
export KONG_CP_URL=$(gcloud compute instances describe $GCP_VM_NAME  --format='get(networkInterfaces[0].accessConfigs[0].natIP)' --zone=$GCP_ZONE)
```

Allow the following firewall rules for Control Plane VM

- 8001 Listens for calls from the command line over HTTP.
- 8002 Kong Manager (GUI). Listens for HTTP traffic.
- 8005 Hybrid mode only. Control Plane listens for traffic from Data Planes.
- 8006 Hybrid mode only. Control Plane listens for Vitals telemetry data from Data Planes.
- 9000 Portainer UI

```bash
gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create kong-admin-api --description="Admin API HTTP" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8001 --source-ranges=0.0.0.0/0 --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create kong-manager-gui --description="Kong Manager (GUI) HTTP" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8002 --source-ranges=0.0.0.0/0 --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create cp-dp-hybrid --description="Traffic from Data Planes" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8005 --source-ranges=0.0.0.0/0 --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create cp-dp-telemetry --description="Vitals telemetry data from Data Planes" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8006 --source-ranges=0.0.0.0/0 --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create portainer-ui-api --description="Portainer UI and API" --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:9000 --source-ranges=0.0.0.0/0 --target-tags=$GCP_VM_NAME
```

Connecting to the VM

```bash
gcloud compute ssh --project=$GCP_PROJECT_NAME --zone=$GCP_ZONE $GCP_VM_NAME
```

Configure Environment and re-login to the session.

```bash
echo "LANG=en_US.utf-8" | sudo tee -a /etc/environment
echo "LC_ALL=en_US.utf-8" | sudo tee -a /etc/environment
```

Install utilities

```bash
sudo yum update -y
sudo yum install jq git wget python36 openssl -y
sudo pip3 install httpie
```

Install Docker

NOTES:
We are using CentOS because Docker provide packages only for RHEL on s390x (IBM Z)

[Reference](https://docs.docker.com/engine/install/centos/)

```bash
sudo yum install yum-utils -y
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io -y
sudo systemctl enable --now docker.service
```

Check Docker installation

```bash
sudo docker info
```

## Portainer installation

```bash
sudo docker volume create portainer_data
sudo docker run --name portainer -d -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.6.0-alpine
```

## Portainer checking

Using the GCP VM’s public address, check the installation <http://$KONG_CP_URL:9000>

At the first access, Portainer asks to define the admin's password.
We have 5 minutes to finish the process, otherwise portainer container should be destroyed and created again.

Choose `Local` -> `Manage the local Docker environment`, we'll see its home page.

## Generating Private Key and Digital Certificate for CP/DP communications

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
```

## Configure PostgreSQL database

```bash
sudo docker network create kong-net
sudo docker pull kong/kong-gateway:2.4.1.1-alpine
sudo docker tag kong/kong-gateway:2.4.1.1-alpine kong-ee
sudo docker run -d --network kong-net --name kong-ee-database \
   -p 5432:5432 \
   -e "POSTGRES_USER=kong" \
   -e "POSTGRES_DB=kong" \
   -e "POSTGRES_HOST_AUTH_METHOD=trust" \
   postgres:latest
```

Replace KONG_LICENSE_DATA with correct license (don't remove single quotes)

```bash
export KONG_LICENSE_DATA='<LICENCE_DATA>'
```

## Run bootstraping

```bash
sudo docker run --rm --network kong-net --link kong-ee-database:kong-ee-database \
   -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-ee-database" \
   -e "KONG_LICENSE_DATA=$KONG_LICENSE_DATA" \
   -e "KONG_PASSWORD=kong" \
   -e "POSTGRES_PASSWORD=kong" \
   kong-ee kong migrations bootstrap
```

## Configure Kong Control Plane

Replace `/home/claudio/cluster.crt` with path to the generated cert and private key.

```bash
sudo docker run -d --network kong-net --name kong-ee --link kong-ee-database:kong-ee-database \
  -e "KONG_DATABASE=postgres" \
  -e "KONG_PG_HOST=kong-ee-database" \
  -e "KONG_PG_PASSWORD=kong" \
  -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
  -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PORTAL_API_ACCESS_LOG=/dev/stdout" \
  -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
  -e "KONG_PORTAL_API_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
  -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
  -e "KONG_ADMIN_GUI_LISTEN=0.0.0.0:8002, 0.0.0.0:8445 ssl" \
  -e "KONG_PORTAL=on" \
  -e "KONG_PORTAL_GUI_PROTOCOL=http" \
  -e "KONG_PORTAL_GUI_HOST=$KONG_CP_URL:8003" \
  -e "KONG_PORTAL_SESSION_CONF={\"cookie_name\": \"portal_session\", \"secret\": \"portal_secret\", \"storage\":\"kong\", \"cookie_secure\": false}" \
  -e "KONG_LICENSE_DATA=$KONG_LICENSE_DATA" \
  -e "KONG_ROLE=control_plane" \
  -e "KONG_CLUSTER_LISTEN=0.0.0.0:8005" \
  -e "KONG_CLUSTER_TELEMETRY_LISTEN=0.0.0.0:8006" \
  -e "KONG_VITALS=on" \
  -e "KONG_CLUSTER_CERT=/etc/cluster.crt" \
  -e "KONG_CLUSTER_CERT_KEY=/etc/cluster.key" \
  -p 8000:8000 \
  -p 8443:8443 \
  -p 8001:8001 \
  -p 8444:8444 \
  -p 8002:8002 \
  -p 8445:8445 \
  -p 8003:8003 \
  -p 8446:8446 \
  -p 8004:8004 \
  -p 8447:8447 \
  -p 8005:8005 \
  -p 8006:8006 \
  -v /home/claudio/cluster.crt:/etc/cluster.crt:ro \
  -v /home/claudio/cluster.key:/etc/cluster.key:ro \
  kong-ee
```

## Configure Kong workspace

```bash
http patch :8001/workspaces/default config:='{"portal": true}'
```

## Check Kong Admin API and Proxy ports

```bash
http --verify=no https://localhost:8443
http --verify=no https://localhost:8444
```

## Restart container

NOTES: Don't know why

```bash
sudo docker stop kong-ee
sudo docker stop kong-ee-database
sudo docker start kong-ee-database
sudo docker start kong-ee
```

## Test the Control Plane

Test the installation pointing your laptop browser to <http://$KONG_CP_URL:8002> to open Kong Manager or use httpie sending a request to port 8001:

```bash
http $KONG_CP_URL:8001 | jq .version
```

Output

```bash
"2.4.1.1-enterprise-edition"
```

Notice that, although having the port 8000 exposed, we're not supposed to consumed it, since this instance has been defined as a Control Plane:

```bash
http $KONG_CP_URL:8000
```

Output:

```bash
http: error: ConnectionError: HTTPConnectionPool(host='$KONG_CP_URL', port=8000): Max retries exceeded with url: / (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7f585bb74198>: Failed to establish a new connection: [Errno 111] Connection refused',)) while doing a GET request to URL: http://$KONG_CP_URL:8000/
```

# Kong Konnect Enterprise Data Plane - OpenShift

The OpenShift Data Plane will use the same certificate/key file pair issued before. Copy the certificate/key file pair from Control Plane to local laptop and then copy them to Data Plane.

Go to a local terminal and run the following command using `gcloud` compute command:

NOTES:

Replace `/home/claudio/` with correct path

```bash
gcloud compute scp --project=$GCP_PROJECT_NAME --zone=$GCP_ZONE konnect-cp:/home/claudio/cluster.crt .
gcloud compute scp --project=$GCP_PROJECT_NAME --zone=$GCP_ZONE konnect-cp:/home/claudio/cluster.key .
```

You should see both files in your local laptop.

## Kubeconfig environment variable

Set the KUBECONFIG env variable to connect to the OpenShift Cluster laptop use oc command to install the Data Plane.

```bash
export KUBECONFIG=<KUBECONFIG_PATH>
```

## Check Kubernetes context which should be pointed to OpenShift cluster

```bash
oc config get-contexts
```

## Create OpenShift project

```bash
export OCP_PROJECT_NAME=kong
oc new-project $OCP_PROJECT_NAME
```

## Kong Enterprise Secrets

From your laptop use `oc` command to install the Data Plane.

Create a secret with your license file

```bash
oc create secret generic kong-enterprise-license --from-file=license=./license.json -n $OCP_PROJECT_NAME
```

Create secret for the certificate/key pair using the same local files we exported before.

```bash
oc create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n $OCP_PROJECT_NAME
```

## Installing Kong Konnect Enterprise Data Plane with Kong Operator

Notice that our OpenShift deployment is also set as `db-less` and is also pointing to the Control Plane's port `8005`. To make our settings a little easier, we're using the Control Plane's Public IP. Besides, we have turned the Ingress Controller off.

## Create Catalog Source

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
 name: operatorhubio-catalog
 namespace: openshift-marketplace
spec:
 sourceType: grpc
 image: quay.io/operatorhubio/catalog:latest 
 displayName: Community Operators
 publisher: OperatorHub.io
EOF
```

## Check Catalog Source

```bash
oc get catalogsource --all-namespaces | grep 'operatorhubio-catalog'
```

Output:

```bash
NAMESPACE               NAME                    DISPLAY               TYPE   PUBLISHER        AGE
openshift-marketplace   operatorhubio-catalog   Community Operators   grpc   OperatorHub.io   2s
openshift-marketplace   redhat-operators        Red Hat Operators     grpc   Red Hat          47m
```

## Create Subscription

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-kong
  namespace: openshift-operators
spec:
  channel: alpha
  name: kong
  source: operatorhubio-catalog
  sourceNamespace: openshift-marketplace
EOF
```

If you want to delete `Subscription` and `CatalogSource` run the following commands:

```bash
oc delete subscription my-kong -n openshift-operators
oc delete csv kong.v0.8.0 -n openshift-operators
oc delete catalogsource operatorhubio-catalog -n openshift-marketplace
```

After install, watch your operator come up using the command.

```bash
oc get csv -n openshift-operators
```

Output:

```bash
NAME          DISPLAY         VERSION   REPLACES      PHASE
kong.v0.8.0   Kong Operator   0.8.0     kong.v0.7.0   Succeeded
```

## Download Kong Helm Charts

```bash
mkdir KongChart
cd KongChart
helm fetch kong/kong
tar xvf *
cd kong
```

## Configure Kong Konnect Enterprise Chart (konnect-dp.yaml)

Copy the original `values.yaml` provided by the Kong to `konnect-dp.yaml`

```bash
cp values.yaml konnect-dp.yaml
```

Use `konnect-dp.yaml` as an example or include the following settings.

```bash
sed -i "s/KONG_CP_URL/$KONG_CP_URL/" konnect-dp.yaml
```

```yaml
env.role: data_plane
env.cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
env.cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
env.lua_ssl_trusted_certificate: /etc/secrets/kong-cluster-cert/tls.crt
env.cluster_control_plane: $KONG_CP_URL:8005
env.cluster_telemetry_endpoint: $KONG_CP_URL:8006
env.status_listen: 0.0.0.0:8100
```

Change the following settings

```yaml
image.repository: kong/kong-gateway
image.tag: "2.4.1.1-alpine"
admin.enabled: false
proxy.type: LoadBalancer
secretVolumes: kong-cluster-cert
ingressController.enabled: false
enterprise.enabled: true
enterprise.license_secret: kong-enterprise-license
enterprise.portal.enabled: false
enterprise.rbac.enabled: false
enterprise.smtp.enabled: false
manager.enabled: false
portal.enabled: false
portalapi.enabled: false
resources.limits.cpu="1200m"
resources.limits.memory="800Mi"
resources.requests.cpu="300m"
resources.requests.memory="300Mi"
autoscaling.enabled=true
autoscaling.minReplicas=1
autoscaling.maxReplicas=20
autoscaling.metrics[0].type=Resource
autoscaling.metrics[0].resource.name=cpu
autoscaling.metrics[0].resource.target.type=Utilization
autoscaling.metrics[0].resource.target.averageUtilization=75
```

## Apply the Kong declaration

!!!!!!!!!!HUGE NOTES!!!!!!!!

When `autoscaling` enabled deployment potentially will not work because of [issue](https://github.com/Kong/kong-operator/pull/78)

If so you need to add following permissions to the ClusterRole `kong-<some_symbols>`  and then apply `konnect-dp.yaml`

```yaml
- apiGroups:
  - "autoscaling"
  resources:
  - horizontalpodautoscalers
  verbs:
  - get
  - create
  - delete
```

```bash
oc apply -f konnect-dp.yaml
```

## Checking the deployment

```bash
oc get kong -n $OCP_PROJECT_NAME
```

Output:

```bash
NAME         AGE
konnect-dp   6m30s
```

## Checking pods

```bash
oc get pod -n $OCP_PROJECT_NAME
```

Output:

```bash
NAME                               READY   STATUS    RESTARTS   AGE
konnect-dp-kong-5956694595-vrw8j   1/1     Running   0          16s
```

```bash
oc get service -n $OCP_PROJECT_NAME
```

Output:

```bash
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
konnect-dp-kong-proxy   LoadBalancer   172.30.185.98   35.235.106.32   80:31786/TCP,443:30831/TCP   68s
```

## Checking the Data Plane from the Control Plane

The Control Plane shoud have deployed Data Planes

```bash
http $KONG_CP_URL:8001/clustering/status
```

Output

```bash
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *
Connection: keep-alive
Content-Length: 180
Content-Type: application/json; charset=utf-8
Date: Sat, 10 Jul 2021 14:01:17 GMT
Deprecation: true
Server: kong/2.4.1.1-enterprise-edition
X-Kong-Admin-Latency: 4
X-Kong-Admin-Request-ID: L3bjkdG2bWsUwgFwYsoERIzxF5Thxx6r
vary: Origin

{
    "30748d64-3142-41ea-88ca-36a5a5b23262": {
        "config_hash": "00000000000000000000000000000000",
        "hostname": "konnect-dp-kong-5956694595-vjkxz",
        "ip": "34.94.145.16",
        "last_seen": 1625925655
    }
}
```

## Defining a Service and a Route

From your laptop define a service and a route sending requests to the Control Plane.

```bash
http $KONG_CP_URL:8001/services name=httpbinservice url='http://httpbin.org'
http $KONG_CP_URL:8001/services/httpbinservice/routes name='httpbinroute' paths:='["/httpbin"]'
```

## Checking the Proxy

The Route previously deployed, and already available for consumption in the first Data Plane has been published to the Data Plane.
Use the Load Balancer created during the deployment to consume the Kong Route:

```bash
export KONG_DP_URL=<REPLACE_WITH_DP_EXTERNAL_IP>
http $KONG_DP_URL/httpbin/get
```

Output:

```bash
HTTP/1.1 200 OK
Access-Control-Allow-Credentials: true
Access-Control-Allow-Origin: *
Connection: keep-alive
Content-Length: 431
Content-Type: application/json
Date: Thu, 15 Apr 2021 22:09:09 GMT
Server: gunicorn/19.9.0
Via: kong/2.3.3.0-enterprise-edition
X-Kong-Proxy-Latency: 25
X-Kong-Upstream-Latency: 137

{
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate",
        "Host": "httpbin.org",
        "User-Agent": "HTTPie/2.4.0",
        "X-Amzn-Trace-Id": "Root=1-6078b985-74ae217b6a2cb98c4d01b3eb",
        "X-Forwarded-Host": "35.235.106.32",
        "X-Forwarded-Path": "/httpbin/get",
        "X-Forwarded-Prefix": "/httpbin"
    },
    "origin": "10.129.0.1, 34.94.145.16",
    "url": "http://35.235.106.32/get"
}
```

## Data plane route test

```bash
while [ 1 ]; do curl http://$KONG_DP_URL/httpbin/get; echo; done
```

## Deleting Kong Konnect Data Plane

In case you want to uninstall Kong Konnect Data Plane run:

```bash
oc delete -f konnect-dp.yaml
oc delete kong konnect-dp
oc delete secret kong-enterprise-license
oc delete secret kong-enterprise-edition-docker
oc delete secret kong-cluster-cert
oc delete project kong
```

## Scaling the Deployment

!!!!!!!!!! HuGE NOTES !!!!!!!!!!!!

HPA enabled in our case so maybe we can skip manual scaling. It will depend on `fortio` parameters.
To check HPA we need to reduce `averageUtilization` on HPA to `10` for example.

To produce requests to our service we're going to use [Fortio](https://www.fortio.org). Install `Fortio` in accordance with the instructions for the operating system used.

A simple load test can be done with the following command. Notice that we're using the Public IP provided by GCP.

```bash
fortio load -c 100 -qps 2000 -t 0 http://$KONG_DP_URL/httpbin/get
```

```bash
oc get deployment
```

Output

```bash
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
konnect-dp-kong   1/1     1            1           38m
```

Edit the "konnect-dp.yaml" file updating the replicaCount configuration to 3

```yaml
  # Kong pod count.
  # It has no effect when autoscaling.enabled is set to true
  replicaCount: 3
```

Apply it again

```bash
oc apply -f konnect-dp.yaml
oc get pod -n $OCP_PROJECT_NAME
```

Output

```bash
NAME                               READY   STATUS    RESTARTS   AGE
konnect-dp-kong-5cf4696db7-hdmlc   1/1     Running   0          4m26s
konnect-dp-kong-5cf4696db7-kv6gd   1/1     Running   0          4m26s
konnect-dp-kong-5cf4696db7-pffrc   1/1     Running   0          37m
```

# ANOTHER SECTION WILL ADD LATER
