# Kong Logging on OCP

The purpose of this document is to explain how to integrate Kong Gateway with OpenShift Logging.

## Deploy Kong Gateway

Refer to one of the existing deployments, depending on your needs:

- [All in one - DB Full](./gateway-plugins/README.md)
- [Control Plane + Data Plane](./gateway/README.md)

## Deploy a sample app

- Apply scc of anyuid to kuma-demo

```bash
oc adm policy add-scc-to-group anyuid system:serviceaccounts:kuma-demo
```

- Install resources on kuma-demo ns

```bash
kubectl apply -f https://raw.githubusercontent.com/kumahq/kuma-demo/master/kubernetes/kuma-demo-aio.yaml
```

## Install OpenShift

For detailed instructions refer to the [OpenShift Logging documentation](https://docs.openshift.com/container-platform/4.10/logging/cluster-logging-deploying.html)

- Install the Openshift Elasticsearch Operator in all namespaces
- Install the Openshift Logging in the default namespaces `openshift-logging`
- Create a `clusterlogging` resource. Given that I am running a test environment, I have reduced the required resources and the replicas.

```bash
oc apply -f -<<EOF
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  collection:
    logs:
      fluentd: {}
      type: fluentd
  logStore:
    elasticsearch:
      resources:
        limits:
          memory: 8Gi # Instead of the default 16Gi
        requests:
          memory: 8Gi # Instead of the default 16Gi
      storage:
        storageClassName: gp2
        size: 200G
      nodeCount: 1 # Instead of the default 3 replicas
      redundancyPolicy: ZeroRedundancy # Instead of the SingleRedundancy because there is no replication
    retentionPolicy:
      application:
        maxAge: 7d
    type: elasticsearch
  visualization:
    kibana:
      replicas: 1
    type: kibana
  managementState: Managed
EOF
```

- Wait for pods to be ready

```bash
oc wait --for=condition=ready pod -l component=elasticsearch -n openshift-logging --timeout=180s
oc wait --for=condition=ready pod -l component=kibana -n openshift-logging --timeout=180s
```

- Open Kibana

```bash
oc get routes -n openshift-logging kibana --template={{.spec.host}}
```

- Configure the indices.

Create the index named `app` and use the `@timestamp` time field to view all the non-infra container logs.

If you also need to monitor the infra logs, do the same for the `infra` index also using the `@timestamp` time field.

- Browse the logs

Go to the Discover tab and you will see all the logs from any namespace

## Clean up

### Remove the OpenShift logging and uninstall the operators

```bash
oc delete ClusterLogging -n openshift-logging instance
oc delete subscriptions.operators.coreos.com cluster-logging -n openshift-logging
oc delete subscriptions.operators.coreos.com elasticsearch-operator -n openshift-operators-redhat
```

### Remove the demo application

```bash
oc delete ns kuma-demo
oc adm policy remove-scc-from-group anyuid system:serviceaccounts:kuma-demo
```

### Remove the Gateway

Refer to the same clean up instructions depending on the installed Kong Gateway
