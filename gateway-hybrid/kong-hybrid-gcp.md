- [Kong Konnect Enterprise Hybrid Mode](#kong-konnect-enterprise-hybrid-mode)
  - [Reference Architecture](#reference-architecture)
- [Google Cloud settings and OpenShift Installation](#google-cloud-settings-and-openshift-installation)
  - [Creating the OpenShift Cluster](#creating-the-openshift-cluster)
  - [Checking the cluster installation](#checking-the-cluster-installation)
- [Kong Konnect Enterprise Control Plane](#kong-konnect-enterprise-control-plane)
  - [Portainer installation](#portainer-installation)
  - [Checking Portainer container](#checking-portainer-container)
  - [Portainer UI checking](#portainer-ui-checking)
  - [Generating Private Key and Digital Certificate for CP/DP communications](#generating-private-key-and-digital-certificate-for-cpdp-communications)
  - [Configure PostgreSQL database](#configure-postgresql-database)
  - [Run bootstrapping](#run-bootstrapping)
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
  - [Configure Kong Konnect Enterprise Chart](#configure-kong-konnect-enterprise-chart)
  - [Apply the Kong declaration](#apply-the-kong-declaration)
  - [Checking the deployment](#checking-the-deployment)
  - [Checking pods](#checking-pods)
  - [Checking the Data Plane from the Control Plane](#checking-the-data-plane-from-the-control-plane)
  - [Defining a Service and a Route](#defining-a-service-and-a-route)
  - [Checking the Proxy](#checking-the-proxy)
  - [Data plane route test](#data-plane-route-test)
  - [Deleting Kong Konnect Data Plane](#deleting-kong-konnect-data-plane)
  - [Scaling the Deployment](#scaling-the-deployment)
- [Keycloak](#keycloak)
  - [Create a Project](#create-a-project)
  - [Installing Keycloak](#installing-keycloak)
  - [Keycloak configuration](#keycloak-configuration)
    - [Realm definition](#realm-definition)
    - [Client_Id/Client_Secret definition](#client_idclient_secret-definition)
    - [User creation](#user-creation)
  - [OpenId Connect (OIDC) plugin and Keycloak](#openid-connect-oidc-plugin-and-keycloak)
  - [Authorization Code](#authorization-code)
  - [Client Credentials](#client-credentials)
- [Redis](#redis)
  - [Create Redis Project](#create-redis-project)
  - [Installing Redis](#installing-redis)
  - [Checking Redis installation](#checking-redis-installation)
  - [Create a Service and Route](#create-a-service-and-route)
  - [Configure caching plugin](#configure-caching-plugin)
  - [Check caching configuration](#check-caching-configuration)
- [Elasticsearch, Kibana and Logstash](#elasticsearch-kibana-and-logstash)
  - [Elasticsearch](#elasticsearch)
    - [Install Elasticsearch](#install-elasticsearch)
    - [Configure permissions for service account](#configure-permissions-for-service-account)
    - [Install Helm chart](#install-helm-chart)
  - [Logstash](#logstash)
    - [Configure Logstash chart](#configure-logstash-chart)
    - [Install Logstash](#install-logstash)
  - [Kibana](#kibana)
    - [Install Kibana](#install-kibana)
  - [Checking ELK installation](#checking-elk-installation)
  - [Setting the TCP-Log Plugin](#setting-the-tcp-log-plugin)
    - [Apply the TCP-Log plugin](#apply-the-tcp-log-plugin)
    - [Apply TCP Log-plugin to the Ingress](#apply-tcp-log-plugin-to-the-ingress)
    - [Deleting Ingress annotation](#deleting-ingress-annotation)
- [Red Hat Fuse](#red-hat-fuse)
  - [Web Service App](#web-service-app)
  - [JDK 1.8](#jdk-18)
    - [Install AdoptOpenJDK](#install-adoptopenjdk)
    - [Maven](#maven)
    - [Build](#build)
    - [Checking Swagger UI](#checking-swagger-ui)
    - [Create service and route](#create-service-and-route)
    - [Enabling caching](#enabling-caching)
- [CXF ("Celtix" and "XFire")](#cxf-celtix-and-xfire)
- [GitHub & GitHub Actions](#github--github-actions)
  - [Create a new Repo](#create-a-new-repo)
  - [git push -u origin main](#git-push--u-origin-main)

# Kong Konnect Enterprise Hybrid Mode

One of the most powerful capabilities provided by Kong Konnect Enterprise is the support for Hybrid deployments. In other words, it implements distributed API Gateway Clusters with multiple instances running in several environments at the same time.

Moreover, Kong Konnect Enterprise provides a new topology option, named Hybrid Mode, with a total separation of the Control Plane (CP) and Data Plane (DP). While the Control Plane handles administration tasks, the Data Plane is only used by API Consumers

Please, refer to the following link to read more about the Hybrid deployment: <https://docs.konghq.com/enterprise/2.4.x/deployment/hybrid-mode/>

## Reference Architecture

Here's a Reference Architecture implemented with Red Hat products and services:

![Kong Konnect Enterprise Hybrid Mode](images/ref-arch-01.png)

The Control Plane runs as a Docker container on an RHEL instance.
The Data Plane runs on an OpenShift Cluster.

Considering the capabilities provided by the Kubernetes platform, running Data Planes on this platform delivers a powerful environment. Here are some capabilities leveraged by the Data Plane on Kubernetes:
High Availability: One of the main Kubernetes' capabilities is "Self-Healing". If a "pod" crashes, Kubernetes takes care of it, reinitializing the "pod".
Scalability/Elasticity: HPA ("Horizontal Pod Autoscaler") is the capability to initialize and terminate "pod" replicas based on previously defined policies. The policies define "thresholds" to tell Kubernetes the conditions where it should start a brand new "pod" replica or terminate a running one.
Load Balancing: The Kubernetes Service notion defines an abstraction level on top of the "pod" replicas that might have been up or down (due HPA policies, for instance). Kubernetes keeps all the "pod" replicas hidden from the "callers" through Services.

Important remark #1: this tutorial is intended to be used for labs and PoC only. There are many aspects and processes, typically implemented in production sites, not described here. For example: Digital Certificate issuing, Cluster monitoring, etc.

Important remark #2: the deployment is based on Kong Konnect Enterprise. Please contact Kong to get a Kong Konnect Enterprise trial license to run this lab.

# Google Cloud settings and OpenShift Installation

Login to gcloud or use Cloud Shell.

```bash
gcloud auth login
```

Create Google Cloud project

```bash
export GCP_PROJECT_NAME=konghq-public
export GCP_ZONE=us-central1-a
gcloud projects create $GCP_PROJECT_NAME --name $GCP_PROJECT_NAME
gcloud config set project $GCP_PROJECT_NAME
```

Creating GCP Public and Private Keys

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/google_rsa
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/google_rsa
```

## Creating the OpenShift Cluster

⚠️ WARNING

You must use OpenShift version <=4.8 because `apiextensions.k8s.io/v1beta1` [removed](https://docs.openshift.com/container-platform/4.9/release_notes/ocp-4-9-release-notes.html#ocp-4-9-removed-features) from version 4.9 and higher.
This guide was tested on version 4.8.

Please, use [Openshift docs](https://docs.openshift.com/container-platform/4.8/installing/installing_gcp/installing-gcp-default.html) for installing a cluster on GCP.

## Checking the cluster installation

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

Create a new Red Hat Enterprise Linux 7 VM Instance with the assigned tag `kong-konnect-cp`.

```bash
export GCP_VM_NAME=kong-konnect-cp
gcloud compute instances create $GCP_VM_NAME \
      --project=$GCP_PROJECT_NAME \
      --zone=$GCP_ZONE \
      --machine-type=e2-standard-2 \
      --network-interface=network-tier=PREMIUM,subnet=default \
      --maintenance-policy=MIGRATE \
      --provisioning-model=STANDARD \
      --tags=$GCP_VM_NAME \
      --create-disk=auto-delete=yes,boot=yes,device-name=$GCP_VM_NAME,image=projects/rhel-cloud/global/images/rhel-7-v20220519,mode=rw,size=20,type=projects/$GCP_PROJECT_NAME/zones/$GCP_ZONE/diskTypes/pd-balanced \
      --no-shielded-secure-boot \
      --shielded-vtpm \
      --shielded-integrity-monitoring \
      --reservation-affinity=any
```

The Control Plane will be running on a specific RHEL 7 VM as the Data Plane will be deployed on the OpenShift Cluster.

```bash
export KONG_CP_URL=$(gcloud compute instances describe $GCP_VM_NAME  \
      --format='get(networkInterfaces[0].accessConfigs[0].natIP)' \
      --zone=$GCP_ZONE)
```

Allow the following firewall rules for Control Plane VM

- 8001 Listens for calls from the command line over HTTP.
- 8002 Kong Manager (GUI). Listens for HTTP traffic.
- 8005 Hybrid mode only. Control Plane listens for traffic from Data Planes.
- 8006 Hybrid mode only. Control Plane listens for Vitals telemetry data from Data Planes.
- 9000 Portainer UI

```bash
gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create kong-admin-api-$GCP_VM_NAME \
    --description="Admin API HTTP" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:8001 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create kong-manager-gui-$GCP_VM_NAME \
    --description="Kong Manager (GUI) HTTP" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:8002 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create cp-dp-hybrid-$GCP_VM_NAME \
    --description="Traffic from Data Planes" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:8005 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create cp-dp-telemetry-$GCP_VM_NAME \
    --description="Vitals telemetry data from Data Planes" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:8006 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$GCP_VM_NAME

gcloud compute --project=$GCP_PROJECT_NAME firewall-rules create portainer-ui-api-$GCP_VM_NAME \
    --description="Portainer UI and API" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:9000 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$GCP_VM_NAME
```

Connecting to the VM

```bash
gcloud compute ssh --project=$GCP_PROJECT_NAME --zone=$GCP_ZONE $GCP_VM_NAME
```

Configure Environment and re-login to the session.

```bash
echo "LANG=en_US.utf-8" | sudo tee -a /etc/environment
echo "LC_ALL=en_US.utf-8" | sudo tee -a /etc/environment
sudo cat /etc/environment
```

Install utilities

```bash
sudo yum update -y
sudo yum install jq git wget python36 openssl -y
sudo pip3 install httpie
```

Install Docker

NOTES:
We are using CentOS repo because Docker provides packages only for RHEL on s390x (IBM Z)

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
sudo docker run --name portainer -d -p 9000:9000 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data portainer/portainer-ce:2.6.0-alpine
```

## Checking Portainer container

```bash
sudo docker ps
```

⚠️ WARNING

At the first access, Portainer asks to define the admin's password.
We have 5 minutes to finish the process, otherwise portainer container should be destroyed and created again.

Error log if we do not set a password in 5 minutes

```bash
[FATAL] [internal,init] No administrator account was created in 5.000000 mins. 
Shutting down the Portainer instance for security reasons
```

## Portainer UI checking

Using the GCP VM’s public address, check the installation <http://$KONG_CP_URL:9000>

Create a new password for the `admin` user and uncheck `Allow collection of anonymous statistics`.

Choose `Local` -> `Manage the local Docker environment`, and we'll see its home page.

## Generating Private Key and Digital Certificate for CP/DP communications

```bash
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout ./cluster.key -out ./cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"
export CERTIFICATE=$(readlink -e cluster.crt)
export PRIVATE_KEY=$(readlink -e cluster.key)
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
export KONG_LICENSE_DATA='<LICENSE_DATA>'
```

## Run bootstrapping

```bash
sudo docker run --rm --network kong-net --link kong-ee-database:kong-ee-database \
    -e "KONG_DATABASE=postgres" -e "KONG_PG_HOST=kong-ee-database" \
    -e "KONG_LICENSE_DATA=$KONG_LICENSE_DATA" \
    -e "KONG_PASSWORD=kong" \
    -e "POSTGRES_PASSWORD=kong" \
    kong-ee kong migrations bootstrap
```

Output

```text
<*> migrations processed
<*> executed
Database is up-to-date
```

## Configure Kong Control Plane

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
    -e "KONG_PORTAL_SESSION_CONF={\"cookie_name\": \"portal_session\", \"secret\": \"kong\", \"storage\":\"kong\", \"cookie_secure\": false}" \
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
    -v $CERTIFICATE:/etc/cluster.crt:ro \
    -v $PRIVATE_KEY:/etc/cluster.key:ro \
    kong-ee
```

## Configure Kong workspace

```bash
http patch :8001/workspaces/default config:='{"portal": true}'
```

## Check Kong Admin API and Proxy ports

⚠️ WARNING

Port `8443` won't work with error:

```bash
http: error: SSLError: HTTPSConnectionPool(host='localhost', port=8443): 
Max retries exceeded with url: / 
(Caused by SSLError(SSLEOFError(8, 'EOF occurred in violation of protocol (_ssl.c:877)'),)) 
while doing a GET request to URL: https://localhost:8443/
```

Port `8443` [takes](https://docs.konghq.com/enterprise/2.4.x/deployment/default-ports/) incoming HTTPS traffic from Consumers, and forwards it to upstream Services.

Maybe it works **only with Consumers**, but I'm not sure, need double check.

We have some mention from Kong docs (port `8000` have the same purpose, but only for HTTP)

```text
Notice that, although having the port 8000 exposed, we're not supposed to consume it, since this instance has been defined as a Control Plane:
```

```bash
http --verify=no https://localhost:8443
http --verify=no https://localhost:8444
```

## Restart container

ℹ️ Don't know why we need it.

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

```text
"2.4.1.1-enterprise-edition"
```

Notice that, although having the port 8000 exposed, we're not supposed to consume it, since this instance has been defined as a Control Plane:

```bash
http $KONG_CP_URL:8000
```

Output

```text
http: error: ConnectionError: HTTPConnectionPool(host='$KONG_CP_URL', port=8000): 
Max retries exceeded with url: / (Caused by NewConnectionError
('<urllib3.connection.HTTPConnection object at 0x7f585bb74198>: Failed to establish a new connection: 
[Errno 111] Connection refused',)) while doing a GET request to URL: http://$KONG_CP_URL:8000/
```

# Kong Konnect Enterprise Data Plane - OpenShift

The OpenShift Data Plane will use the same certificate/key file pair issued before.
Copy the certificate/key file pair from Control Plane to local laptop.

## Kubeconfig environment variable

Set the KUBECONFIG env variable to connect to the OpenShift Cluster.

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
oc create secret generic kong-enterprise-license \
    --from-file=license=./license.json -n $OCP_PROJECT_NAME
```

Create secret for the certificate/key pair using the same local files we exported before.

```bash
oc create secret tls kong-cluster-cert --cert=./cluster.crt \
    --key=./cluster.key -n $OCP_PROJECT_NAME
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

Output

```text
NAMESPACE               NAME                    DISPLAY               TYPE   PUBLISHER        AGE
openshift-marketplace   operatorhubio-catalog   Community Operators   grpc   OperatorHub.io   2s
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

```bash
oc get subscriptions.operators.coreos.com my-kong -n openshift-operators
```

Output:

```text
NAME      PACKAGE   SOURCE                  CHANNEL
my-kong   kong      operatorhubio-catalog   alpha
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

Output

```text
NAME          DISPLAY         VERSION   REPLACES      PHASE
kong.v0.8.0   Kong Operator   0.8.0     kong.v0.7.0   Succeeded
```

## Configure Kong Konnect Enterprise Chart

ℹ️ We will use `konnect-dp.yaml` as example of deployable Kong instance.

The `konnect-dp.yaml` contains following settings:

```yaml
env.role: data_plane
env.cluster_cert: /etc/secrets/kong-cluster-cert/tls.crt
env.cluster_cert_key: /etc/secrets/kong-cluster-cert/tls.key
env.lua_ssl_trusted_certificate: /etc/secrets/kong-cluster-cert/tls.crt
env.cluster_control_plane: $KONG_CP_URL:8005
env.cluster_telemetry_endpoint: $KONG_CP_URL:8006
env.status_listen: 0.0.0.0:8100
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

Run the following command to replace `$KONG_CP_URL`:

```bash
sed -i "s/KONG_CP_URL/$KONG_CP_URL/" konnect-dp.yaml
```

## Apply the Kong declaration

ℹ️ `autoscaling` enabled deployment won't work because of the [issue](https://github.com/Kong/kong-operator/pull/78)

You can apply the following command or manually add permissions to the ClusterRole `kong.v0.8.0-<some_symbols>` in OCP console.

```bash
oc patch clusterrole $(oc get clusterrole | awk '/kong.v0.8.0/{ print $1 }') --type='json' -p='[{"op": "add", "path": "/rules/0", "value":{ "apiGroups": ["autoscaling"], "resources": ["horizontalpodautoscalers"], "verbs": ["get", "list","watch","create","delete"]}}]'
```

Added permissions

```yaml
- verbs:
  - get
  - list
  - watch
  - create
  - delete
  apiGroups:
    - "autoscaling"
  resources:
    - horizontalpodautoscalers
```

```bash
oc apply -f konnect-dp.yaml
```

## Checking the deployment

```bash
oc get kong -n $OCP_PROJECT_NAME
```

Output

```text
NAME         AGE
konnect-dp   6m30s
```

## Checking pods

```bash
oc get pod -n $OCP_PROJECT_NAME
```

Output

```text
NAME                               READY   STATUS    RESTARTS   AGE
konnect-dp-kong-5956694595-vrw8j   1/1     Running   0          16s
```

```bash
oc get service -n $OCP_PROJECT_NAME
```

Output

```text
NAME                    TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)                      AGE
konnect-dp-kong-proxy   LoadBalancer   172.30.185.98   35.235.106.32   80:31786/TCP,443:30831/TCP   68s
```

## Checking the Data Plane from the Control Plane

The Control Plane should have deployed Data Planes

```bash
http $KONG_CP_URL:8001/clustering/status
```

Output

```text
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

The Route previously deployed and already available for consumption in the first Data Plane has been published to the Data Plane.
Use the Load Balancer created during the deployment to consume the Kong Route.

For Data Plane deployed on **AWS** please use the following command

```bash
export KONG_DP_URL=$(oc get service konnect-dp-kong-proxy -n $OCP_PROJECT_NAME --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')
http $KONG_DP_URL/httpbin/get
```

For Data Plane deployed on **GCP** please use the following command

```bash
export KONG_DP_URL=$(oc get service konnect-dp-kong-proxy -n $OCP_PROJECT_NAME --output jsonpath='{.status.loadBalancer.ingress[0].ip}')
http $KONG_DP_URL/httpbin/get
```

Output

```text
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

⚠️ WARNING

HPA enabled in our case, so maybe we can skip manual scaling. It will depend on `fortio` parameters.
To check HPA we need to reduce `averageUtilization` on HPA to `10`, for example.

To produce requests for our service, we're going to use [Fortio](https://www.fortio.org). Install `Fortio` under the instructions for the operating system used.

A simple load test can be done with the following command. Notice that we're using the Data Plane public IP/hostname.

```bash
fortio load -c 100 -qps 2000 -t 0 http://$KONG_DP_URL/httpbin/get
```

```bash
oc get deployment
```

Output

```text
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
konnect-dp-kong   1/1     1            1           38m
```

Edit the "konnect-dp.yaml" file updating the `replicaCount` configuration to 3

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

```text
NAME                               READY   STATUS    RESTARTS   AGE
konnect-dp-kong-5cf4696db7-hdmlc   1/1     Running   0          4m26s
konnect-dp-kong-5cf4696db7-kv6gd   1/1     Running   0          4m26s
konnect-dp-kong-5cf4696db7-pffrc   1/1     Running   0          37m
```

# Keycloak

<https://www.keycloak.org/getting-started/getting-started-openshift>

## Create a Project

```bash
oc new-project keycloak
```

## Installing Keycloak

```bash
oc process -f \
    https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/openshift-examples/keycloak.yaml \
    -p KEYCLOAK_ADMIN=admin \
    -p KEYCLOAK_ADMIN_PASSWORD=keycloak \
    -p NAMESPACE=keycloak \
| oc create -f -
```

Checking the installation

```bash
oc get pod -n keycloak
```

Output

```text
NAME                READY   STATUS    RESTARTS   AGE
keycloak-1-deploy   1/1     Running   0          37s
keycloak-1-wwmlm    1/1     Running   0          31s
```

```bash
oc get service -n keycloak
```

Output

```text
NAME       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
keycloak   ClusterIP   172.30.86.124   <none>        8443/TCP   19s
```

```bash
oc get route -n keycloak
```

Output

```text
NAME       HOST/PORT                                                PATH   SERVICES   PORT    TERMINATION   WILDCARD
keycloak   keycloak-keycloak.apps.kongcluster1.kong-acquaviva.com          keycloak   <all>   passthrough   None
```

Open browser with Keycloak route URL.

Click on `Administration Console`. Use your credentials `admin` and `keycloak` to login.

## Keycloak configuration

Before configuring Kong Konnect Enterprise to work together with Keycloak, let's define a `Client Id`.

### Realm definition

Passing the mouse over `Master` we can create a new realm. Create a realm called `kong`.

### Client_Id/Client_Secret definition

Clicking on `Clients` and `Create` we can define a new client representing Kong. This `client` is used in the OAuth grants implemented by the user authentication processes.
Choose `kong_id` for the new client. The configurations are below:

- `Access Type`: `confidential`
- `Service Accounts enabled`: `on` (this allows us to implement the OAuth Client Credentials Grant)
- `Valid Redirect URIs`: `http://$KONG_DP_URL/oidcroute/get`

This parameter is needed in the OAuth Authorization Code Grant. Notice we're using our Data Plane public IP.

Click on `Save`. The `Credentials` option is shown in the horizontal menu.

Click on `Credentials` and note of the `client_secret`.

```bash
export KEYCLOAK_CLIENT_SECRET=<OUT_VALUE_HERE>
```

### User creation

Clicking on `Users` and `Add User` we can define the user. This user is used in the OAuth grants implemented by the user authentication processes.
Choose `kong_user` for the `Username` and click on `Save`.

Click on `Credentials`. Type `kong` for both `New Password` and `Password Confirmation` fields. Turn `Temporary` to `Off` and click on `Set Password`.

## OpenId Connect (OIDC) plugin and Keycloak

Reference Architecture

![OIDC Reference Architecture](images/ref-arch-oidc.png)

We're going to apply the OIDC plugin to protect a specific route (`/oidcroute`) with the Authorization Code Grant. When the user tries to consume the route he is redirected to Keycloak login page in order to get authenticated. With a successful authentication and a token, the user is redirected back to the original endpoint that includes the route and then Kong allows the route consumption.

## Authorization Code

Go to Konnect Control Plane and create a Kong Service, Route and apply the OIDC plugin

```bash
http $KONG_CP_URL:8001/services name=oidcservice url='http://httpbin.org'
http $KONG_CP_URL:8001/services/oidcservice/routes name='oidcroute' paths:='["/oidcroute"]'
```

The Route can be consumed since it doesn't have the plugin enabled.

```bash
http $KONG_DP_URL/oidcroute/get
```

Output

```text
HTTP/1.1 200 OK
Access-Control-Allow-Credentials: true
Access-Control-Allow-Origin: *
Connection: keep-alive
Content-Length: 437
Content-Type: application/json
Date: Tue, 13 Apr 2021 22:00:52 GMT
Server: gunicorn/19.9.0
Via: kong/2.3.3.0-enterprise-edition
X-Kong-Proxy-Latency: 14
X-Kong-Upstream-Latency: 137

{
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate",
        "Host": "httpbin.org",
        "User-Agent": "HTTPie/2.4.0",
        "X-Amzn-Trace-Id": "Root=1-60761494-3832a06e12d82a0c74d147fa",
        "X-Forwarded-Host": "35.236.127.239",
        "X-Forwarded-Path": "/oidcroute/get",
        "X-Forwarded-Prefix": "/oidcroute"
    },
    "origin": "10.128.2.1, 34.94.145.16",
    "url": "http://35.236.127.239/get"
}
```

Get Keycloak's issuer clicking on `OpenID Endpoint Configuration` link of the new Realm.

Apply the plugin

Replace `client_secret` and `issuer` with `KEYCLOAK_CLIENT_SECRET` and Keycloak route URL.

```bash
http $KONG_CP_URL:8001/routes/oidcroute/plugins name=openid-connect config:='{"client_id": ["kong_id"], "client_secret": ["2e7c9d11-9076-4389-b070-e10cea7dc8fe"], "issuer": "https://keycloak-keycloak.apps.kongcluster1.kong-acquaviva.com/auth/realms/kong", "cache_ttl": 10 }'
```

Redirect your browser to the Data Plane to consume the Route <http://$KONG_DP_URL/oidcroute/get>

After accepting the Server Certificate, since you haven't been authenticated, you will be redirected to Keycloak's Authentication page.

Enter with the previously created credentials, `kong_user` and `kong` and click on `Sign In`. After getting authenticated, Keycloak will issue a Token and redirect you back to the original URL. Since you have the Token, the Gateway will allow you to consume the URL.

You can check the Token with <https://jwt.io>

## Client Credentials

Create another Kong Service and Route and apply the plugin again

Replace `client_secret` and `issuer` with `KEYCLOAK_CLIENT_SECRET` and Keycloak route URL.

```bash
http $KONG_CP_URL:8001/services name=oidcservice2 url='http://httpbin.org'
http $KONG_CP_URL:8001/services/oidcservice2/routes name='oidcroute2' paths:='["/oidcroute2"]'
http $KONG_CP_URL:8001/routes/oidcroute2/plugins name=openid-connect config:='{"client_id": ["kong_id"], "client_secret": 
["2e7c9d11-9076-4389-b070-e10cea7dc8fe"], "issuer": "https://keycloak-keycloak.apps.kongcluster1.kong-acquaviva.com/auth/realms/kong", "cache_ttl": 10 }'
```

Consume the Route with `client_id` and `client_secret`

```bash
http $KONG_DP_URL/oidcroute2/get -a kong_id:<CLIENT_SECRET>
```

Output

```text
HTTP/1.1 200 OK
Access-Control-Allow-Credentials: true
Access-Control-Allow-Origin: *
Connection: keep-alive
Content-Length: 1741
Content-Type: application/json
Date: Tue, 13 Apr 2021 22:35:46 GMT
Server: gunicorn/19.9.0
Set-Cookie: session=cyFP3ZI_mmKCprpp5WAk-w|1618356946|8xR_lGIcBZNaqMszvUu1ILnxtOTUk; Path=/; SameSite=Lax; HttpOnly
Via: kong/2.3.3.0-enterprise-edition
X-Kong-Proxy-Latency: 83
X-Kong-Upstream-Latency: 137

{
    "args": {},
    "headers": {
        "Accept": "*/*",
        "Accept-Encoding": "gzip, deflate",
        "Authorization": "Bearer eyJhbGciOiJSUzI1NiIsInR0yK89og",
        "Host": "httpbin.org",
        "User-Agent": "HTTPie/2.4.0",
        "X-Amzn-Trace-Id": "Root=1-60761cc2-4576723a7d8e90e1300e54c8",
        "X-Forwarded-Host": "35.236.127.239",
        "X-Forwarded-Path": "/oidcroute2/get",
        "X-Forwarded-Prefix": "/oidcroute2"
    },
    "origin": "10.129.2.1, 34.94.145.16",
    "url": "http://35.236.127.239/get"
}
```

If you provide the wrong credentials you get an error:

```bash
http http://$KONG_DP_URL/oidcroute2/get -a kong_id:2e7c9d11-9076-4389-b070-e10cea7dc8feasdadasda
```

Output

```text
HTTP/1.1 401 Unauthorized
Connection: keep-alive
Content-Length: 26
Content-Type: application/json; charset=utf-8
Date: Thu, 15 Apr 2021 22:45:05 GMT
Server: kong/2.3.3.0-enterprise-edition
WWW-Authenticate: Bearer realm="keycloak-keycloak.apps.kongcluster1.kong-acquaviva.com"
X-Kong-Response-Latency: 16

{
    "message": "Unauthorized"
}
```

# Redis

## Create Redis Project

```bash
oc new-project redis
```

## Installing Redis

```bash
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: redis
  labels:
    app: redis
spec:
  selector:
    matchLabels:
      app: redis
  replicas: 1
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: redis
  labels:
    app: redis
spec:
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
EOF
```

## Checking Redis installation

```bash
oc get pod
```

Output

```text
NAME                    READY   STATUS    RESTARTS   AGE
redis-fd794cd65-mqxlb   1/1     Running   0          46s
```

```bash
oc get service
```

Output

```text
NAME    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
redis   ClusterIP   172.30.114.146   <none>        6379/TCP   56s
```

## Create a Service and Route

```bash
http $KONG_CP_URL:8001/services name=cachingservice url='http://httpbin.org'
http $KONG_CP_URL:8001/services/cachingservice/routes name='cachingroute' paths:='["/cache"]'
```

## Configure caching plugin

```bash
curl -X POST http://$KONG_CP_URL:8001/routes/cachingroute/plugins \
    --data "name=proxy-cache-advanced"  \
    --data "config.cache_ttl=30" \
    --data "config.strategy=redis" \
    --data "config.redis.host=redis.redis.svc.cluster.local" \
    --data "config.redis.port=6379"
```

## Check caching configuration

```bash
http $KONG_DP_URL/cache/get
```

# Elasticsearch, Kibana and Logstash

NOTES: Should we suggest using native OCP Operator fit that?

<https://github.com/elastic/helm-charts>

From the Monitoring and Log Processing perspective, it's important to integrate Kong Konnect Enterprise with a best-of-breed product to externalize all information related to processed requests and allow users to define dashboard, alerts, reports, etc.

This part of the tutorial shows how to configure the real-time integration between Kong Enterprise and Elastic products: Elasticsearch, Kibana and Logstash.

## Elasticsearch

### Install Elasticsearch

```bash
oc new-project elk
oc describe project elk
```

Output:

```yaml
Name: elk
Created: About an hour ago
Labels: <none>
Annotations: openshift.io/description=
  openshift.io/display-name=
  openshift.io/requester=kube:admin
  openshift.io/sa.scc.mcs=s0:c26,c5
  openshift.io/sa.scc.supplemental-groups=1000660000/10000
  openshift.io/sa.scc.uid-range=1000660000/10000
Display Name: <none>
Description: <none>
Status: Active
Node Selector: <none>
Quota: <none>
Resource limits: <none>
```

### Configure permissions for service account

```bash
oc adm policy add-scc-to-user anyuid system:serviceaccount:elk:default
oc adm policy add-role-to-user admin default -n kong
oc adm policy add-cluster-role-to-user cluster-admin default
```

### Install Helm chart

```bash
helm repo add elastic https://helm.elastic.co
```

1. Replace `securityContext.runAsUser=null` and `podSecurityContext.runAsUser=null` with `openshift.io/sa.scc.uid-range` value
2. Replace `podSecurityContext.fsGroup=null` with `openshift.io/sa.scc.supplemental-groups value`

```bash
helm install elk elastic/elasticsearch -n elk \
      --set replicas=1 \
      --set minimumMasterNodes=1 \
      --set securityContext.runAsUser=null \
      --set securityContext.runAsNonRoot=true \
      --set podSecurityContext.runAsUser=null \
      --set podSecurityContext.fsGroup=null \
      --set sysctlInitContainer.enabled=false
```

## Logstash

### Configure Logstash chart

Fetch the chart and update `logstash-values.yaml` file

```bash
helm fetch elastic/logstash
tar xvfk logstash*
cd logstash
cp values.yaml logstash-values.yaml
```

Update `logstashPipeline` with

```yaml
logstashPipeline:
  logstash.conf: |
    input {
      tcp {
        port => 5044
        codec => "json"
      }
    }
    output {
      elasticsearch {
        hosts => ["http://elasticsearch-master.elk.svc.cluster.local:9200"]
        index => "kong"
      }
    }
```

Update `service` field with

```yaml
service:
  annotations:
  type: ClusterIP
  ports:
    - name: logstash
      port: 5044
      protocol: TCP
      targetPort: 5044
```

### Install Logstash

```bash
helm install logstash elastic/logstash -n elk -f logstash-values.yaml
```

## Kibana

### Install Kibana

```bash
helm install kibana elastic/kibana -n elk --set service.type=LoadBalancer
```

## Checking ELK installation

```bash
oc get pod -n elk
```

Output

```text
NAMESPACE     NAME                                   READY   STATUS      RESTARTS   AGE
elk           elasticsearch-master-0                 1/1     Running     0          3h38m
elk           kibana-kibana-54c46c54d6-dbbgm         1/1     Running     0          120m
elk           logstash-logstash-0                    1/1     Running     0          16m
```

```bash
oc get service --all-namespaces
```

Output

```text
elk           elasticsearch-master            ClusterIP      10.100.214.23    <none>                                                                       9200/TCP,9300/TCP               3h38m
elk           elasticsearch-master-headless   ClusterIP      None             <none>                                                                       9200/TCP,9300/TCP               3h38m
elk           kibana-kibana                   LoadBalancer   10.100.211.208   ac074ff862ed646f183f0477f92911dd-1990565081.eu-central-1.elb.amazonaws.com   5601:30493/TCP                  121m
elk           logstash-logstash               ClusterIP      10.100.221.114   <none>                                                                       5044/TCP                        16m
elk           logstash-logstash-headless      ClusterIP      None             <none>                                                                       9600/TCP                        16m
```

## Setting the TCP-Log Plugin

The externalization of all processed requests data to ELK is done by a TCP stream defined through the `TCP-Log` plugin.

### Apply the TCP-Log plugin

NOTES: Why namespace is `default`?

```bash
cat <<EOF | oc apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: tcp-log
  namespace: default
config:
  host: logstash-logstash.elk.svc.cluster.local
  port: 5044
plugin: tcp-log
EOF
```

### Apply TCP Log-plugin to the Ingress

NOTES: We didn't create Ingress before. How should it work?

```bash
oc patch ingress route1 -p '{"metadata":{"annotations":{"konghq.com/plugins":"tcp-log"}}}'
```

### Deleting Ingress annotation

In case you want to disapply the plugin to the ingress run:

```bash
oc annotate ingress route1 konghq.com/plugins-
```

# Red Hat Fuse

<https://spring.io/projects/spring-boot>

<https://spring.io/guides/gs/spring-boot/>

<https://docs.spring.io/spring-boot/docs/current/maven-plugin/reference/htmlsingle/>

<https://camel.apache.org/camel-spring-boot/latest/index.html>

<https://developers.redhat.com/products/fuse>

<https://developers.redhat.com/products/fuse/getting-started>

<https://access.redhat.com/documentation/en-us/red_hat_fuse/7.7/html/fuse_on_openshift_guide/index>

<https://github.com/AdoptOpenJDK/homebrew-openjdk>

## Web Service App

```bash
curl --location --request POST 'https://www.dataaccess.com/webservicesserver/numberconversion.wso' \
    --header 'Content-Type: text/xml; charset=utf-8' \
    --data-raw '<?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
            <soap:Body>
                <NumberToWords xmlns="http://www.dataaccess.com/webservicesserver/">
                    <ubiNum>111</ubiNum>
                </NumberToWords>
            </soap:Body>
        </soap:Envelope>'
```

Output:

```xml
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <m:NumberToWordsResponse xmlns:m="http://www.dataaccess.com/webservicesserver/">
      <m:NumberToWordsResult>one hundred and eleven </m:NumberToWordsResult>
    </m:NumberToWordsResponse>
  </soap:Body>
```

## JDK 1.8

### Install AdoptOpenJDK

NOTES: AdoptOpenJDK is no longer supported and it is recommended that all users move to Eclipse Temurin

<https://adoptopenjdk.net/>

```bash
jdk -version
```

Output

```text
openjdk version "1.8.0_292"
OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_292-b10)
OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.292-b10, mixed mode)
```

### Maven

[Reference](https://maven.apache.org/install.html)

```bash
mvn --version
```

### Build

```bash
mvn spring-boot:run
```

```bash
http :8080/camel/numbertowords/737373
```

Output

```text
HTTP/1.1 200 OK
Access-Control-Allow-Headers: Origin, Accept, X-Requested-With, Content-Type
Access-Control-Allow-Methods: GET, HEAD, POST, PUT, DELETE, TRACE, OPTIONS, CONNECT, PATCH
Access-Control-Allow-Origin: *
Access-Control-Max-Age: 3600
Connection: keep-alive
Content-Type: application/json
Date: Mon, 07 Jun 2021 12:39:57 GMT
Transfer-Encoding: chunked

{
    "item": "seven hundred and thirty seven thousand three hundred and seventy three "
}
```

### Checking Swagger UI

Replace domain with necessary value.

<http://rest-soap-transformation-fuse-soap-rest-proxy.apps.kongcluster1.kong-acquaviva.com/swagger-ui.html>

```bash
http rest-soap-transformation-fuse-soap-rest-proxy.apps.kongcluster1.kong-acquaviva.com/camel/numbertowords/333
```

Output

```text
HTTP/1.1 200 OK
Access-Control-Allow-Headers: Origin, Accept, X-Requested-With, Content-Type
Access-Control-Allow-Methods: GET, HEAD, POST, PUT, DELETE, TRACE, OPTIONS, CONNECT, PATCH
Access-Control-Allow-Origin: *
Access-Control-Max-Age: 3600
Cache-control: private
Content-Type: application/json
Date: Sat, 10 Jul 2021 21:12:15 GMT
Set-Cookie: 0298612c85935bcab043c7486d01e8d0=d721ed0aa9c92d823c6dee57a693866b; path=/; HttpOnly
Transfer-Encoding: chunked

{
    "item": "three hundred and thirty three "
}
```

### Create service and route

Replace domain with necessary value.

```bash
http $KONG_CP_URL:8001/services name=rest-soap-service url='http://rest-soap-transformation-fuse-soap-rest-proxy.apps.kongcluster1.kong-acquaviva.com/camel/numbertowords'

http $KONG_CP_URL:8001/services/rest-soap-service/routes name='rest-soap-route' paths:='["/numbertowords"]'
```

### Enabling caching

```bash
curl -X POST http://$KONG_CP_URL:8001/routes/cachingroute/plugins \
    --data "name=proxy-cache-advanced" \
    --data "config.cache_ttl=30" \
    --data "config.strategy=redis" \
    --data "config.redis.host=redis.redis.svc.cluster.local" \
    --data "config.redis.port=6379"
```

# CXF ("Celtix" and "XFire")

<https://github.com/apache/cxf>

<https://cxf.apache.org/>

<https://maven.apache.org/>

<https://mvnrepository.com/>

<https://search.maven.org/>

<https://documenter.getpostman.com/view/8854915/Szf26WHn>

<https://github.com/sigreen/rest-soap-transformation>

<https://github.com/sigreen/weather-station-apis>

<https://www.youtube.com/watch?v=TLOLWMeobuU>

<https://restlet.talend.com/>

<https://www.dataaccess.com/webservicesserver/numberconversion.wso>

<https://www.dataaccess.com/webservicesserver/numberconversion.wso?op=NumberToWords>

<https://www.dataaccess.com/webservicesserver/numberconversion.wso?WSDL>

```bash
mvn -s configuration/settings.xml spring-boot:run -Dspring.profiles.active=dev 
```

# GitHub & GitHub Actions

SSH Keys
<https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent>

```bash
ssh-keygen -t rsa -b 4096 -C "<EMAIL>"
```

```bash
cd $HOME/.ssh
vi config
```

Add the following lines

```bash
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_rsa
```

```bash
ssh-add -K ~/.ssh/id_rsa
```

Copy and paste public key in GitHub page and test the connection with GitHub

```bash
ssh -T git@github.com
```

<https://konghq.com/blog/gitops-for-kong-managing-kong-declaratively-with-deck-and-github-actions/>

<https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners>

## Create a new Repo

```bash
mkdir githubactions
mkdir runner
cd githubactions
mkdir github
chmod -R 777 github
cd github
git init
```

Add remote repo (replace remote name and remote URL)

```bash
git remote add origin git@github.com:cacquaviva/cicd.git
```

Checl remote connection to GitHub API

```bash
curl -u <TOKEN> https://api.github.com/user/repos -d '{"name":"cicd"}'
```

/*
echo "# kong-cicd" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin git@github.com:cacquaviva/cicd.git

//curl -u USERNAME:PASSWORD <https://api.github.com/user/repos> -d '{"name":"cicd"}'
curl -u dab1f2c1c80bf1d4a813aa0fd2cfed5905d5ac2b <https://api.github.com/user/repos> -d '{"name":"cicd"}'

//git remote add origin git@github.com:cacquaviva/cicd

git push -u origin main
*/

Configure Insomnia
Create a new Design Document "OpenShift"

<https://github.com/CAcquaviva/cicd.git>
cacquaviva
dab1f2c1c80bf1d4a813aa0fd2cfed5905d5ac2b

Create a new main branch
Commit and Push from Insomnia

Update local repo
git remote add origin git@github.com:cacquaviva/cicd.git
git pull origin main

echo "# kong-cicd" >> README.md

git add README.md

git commit -m "first commit"
git branch -M main

git push -u origin main

Include OpenAPI Spec
Go back to Insomnia and Pull. Include the following Spec. Commit it and push it.

openapi: 3.0.2
info:
  version: '1.0'
  title: httpbin-simplest
  license:
    name: Apache 2.0
  description: 'The simplest HTTP Request & Response Service.'
  contact:
    name: Kong
servers:

- url: 'http://httpbin.org'
    description: kongenterprise
paths:
  '/get':
    get:
      summary: Get HTTPbin
      tags:
        - get
      responses:
        '200':
          description: The request's query parameters.
          content:
            application/json
      description: "HTTPbin request"

Include OIDC settings:

openapi: 3.0.2
info:
  version: '1.0'
  title: httpbin-simplest
  license:
    name: Apache 2.0
  description: 'The simplest HTTP Request & Response Service.'
  contact:
    name: Kong
servers:

- url: 'http://httpbin.org'
    description: kongenterprise
paths:
  '/get':
    get:
      summary: Get HTTPbin
      tags:
        - get
      x-kong-plugin-openid-connect:
        enabled: true
        config:
          issuer: <https://keycloak-keycloak.apps.kongcluster1.kong-acquaviva.com/auth/realms/kong>
          cache_ttl: 10
      responses:
        '200':
          description: The request's query parameters.
          content:
            application/json
      description: "HTTPbin request"

------------
git pull origin main -q

git add
git commit -m "first commit"
git push -u origin main
------------

GitHub Actions
action.yaml, which states the basic definition of the action, including the base image it relies on and the parameters to run:

.github/actions/action.yaml

name: 'Kong OpenAPI Deployment'
description: 'Generates Kong configuration from OpenAPI specification and deploys it.'
inputs:
  openapi-spec:  # id of input
    description: 'OpenAPI specification file'
    required: false
    default: 'httpbin.yaml'
  openapi-spec-format:
    description: 'valid values are YAML or JSON'
    required: false
    default: 'YAML'
  kong-config-type:
    description: 'The type of Kong configuration to generate'
    required: false
    default: 'kong-for-kubernetes'
  k8s-namespace:
    description: 'Kubernetes namespace to deploy into'
    required: false
    default: 'kong'
  uid:
    description: 'System user id that will run processes'
    required: false
    default: 502
  gid:
    description: 'System group id that will run processes'
    required: false
    default: 20
  external-service:
    description: 'Name of external service to be created. Do not create one if this input is missing'
    required: false
  external-service-host:
    description: 'Host of external service to be created. Required is external-service is used.'
    required: false
outputs:
  time: # id of output
    description: 'The time we greeted you'
runs:
  using: "composite"
  steps:
    - run: sed -e '1,7d' .insomnia/ApiSpec/*.yml > apitmp.yaml
      shell: bash

Set Up Workflow on a Pull Request
cp -R /Users/claudio/kong/tech/DevPortal/kong-portal-templates /Users/claudio/kong/tech/RedHat/OpenShift/githubactions/runner/actions-runner/_work/cicd/cicd

.github/workflows/CI.yaml

name: CI

on: [push]

jobs:
  build:
    runs-on: self-hosted
    name: Kong
    steps:
    - name: GitHub repo
      run: |
        echo "Current repository: ${{ github.repository }}!"
    - name: checkout
      uses: actions/checkout@v2
    - name: Kong Deploy API Spec
      uses: ./.github/actions
    - name: Kong API deploy
      run: |
        pwd
        tac apitmp.yaml | sed -e 1,5d | tac > httpbin2.yaml
        rm apitmp.yaml
        inso generate config httpbin2.yaml --output kong.yaml
        deck --kong-addr <http://$KONG_CP_URL:8001> sync --headers "kong-admin-token:kong"
        cp httpbin2.yaml ./kong-portal-templates/workspaces/default/specs
        cd ./kong-portal-templates
        KONG_ADMIN_URL=<http://$KONG_CP_URL:8001> KONG_ADMIN_TOKEN=kong portal deploy default

mv CI.yaml .github/workflows

Next, let’s push all the files we created to GitHub now.

git add .
git commit -m "My first actions"
git push origin main
git push --set-upstream origin main

Add a new runner
<https://github.com/CAcquaviva/cicd/settings/actions/add-new-runner>

http $KONG_DP_URL/get -a kong_id:2e7c9d11-9076-4389-b070-e10cea7dc8fe

Uninstalling Kong Konnect Enterprise
If you want to uninstall K4K8S run:

helm uninstall elk -n elk
helm uninstall logstash -n elk
helm uninstall kibana -n elk

oc delete namespace elk

helm uninstall influxdb -n influxdb
oc delete namespace influxdb
oc delete pvc influxdb-data-influxdb-0 -n influxdb

oc delete kongclusterplugin prometheus-plugin
oc delete service kong-dp-monitoring -n kong-dp
oc delete servicemonitor kong-dp-service-monitor -n kong-dp
oc delete serviceaccount kong-prometheus -n kong-dp
oc delete clusterrole prometheus
oc delete clusterrolebinding prometheus
oc delete prometheus kong-dp-prometheus -n kong-dp
oc delete service prometheus-operated-kong -n kong-dp

helm uninstall grafana -n grafana
helm uninstall statsd -n prometheus
helm uninstall prometheus -n prometheus
oc delete namespace prometheus grafana
oc delete service prometheus-kube-prometheus-kubelet -n kube-system

oc annotate ingress sampleroute konghq.com/plugins-
oc delete ingress sampleroute
oc delete ingress route1

oc delete service route1-ext

oc delete service sample
oc delete deployment sample

oc delete kongplugin rl-by-minute
oc delete kongplugin apikey
oc delete secret consumerapikey
oc delete kongconsumer consumer1
oc delete kongplugin tcp-log

helm uninstall kong -n kong
helm uninstall kong-dp -n kong-dp
oc delete -f <https://bit.ly/kong-ingress-enterprise>

oc delete namespaces kong kong-dp

oc delete -f <https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml>

oc get namespaces
oc get crd
oc get pod --all-namespaces
oc get service --all-namespaces
oc get ingress --all-namespaces
oc get kongplugin --all-namespaces
oc get kongclusterplugin --all-namespaces

eksctl delete cluster --name K4K8S
