# Use OpenShift registry for Kong images

This document is intended to provide instructions for how to use the openshift image registry
to avoid depending on docker.io and its rate limits.

## Create a new project

I recommend using a dedicated namespace to better identify Kong resources, especially for cleanup.

```bash
oc new-project kong-image-registry
```

## Expose openshift-registry

From the [Openshift documentation](https://docs.openshift.com/container-platform/4.10/registry/securing-exposing-registry.html)

Check if the default route is already exposed:

```bash
oc get configs.imageregistry.operator.openshift.io/cluster --template='{{ .spec.defaultRoute }}'
```

If the result of the previous command is not `true`, run the following command:

```bash
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

The route to the external registry is:

```bash
OCP_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
```

## Trust the registry locally

In order to trust a container registry you first need to extract the certificate and save it to the ca-trust

```bash
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${OCP_REGISTRY}.crt  > /dev/null
sudo update-ca-trust enable
```

Login to the registry

```bash
$ podman login -u ruromero -p $(oc whoami -t) $OCP_REGISTRY
Login Succeeded!
```

## Trust the external registry URL

```bash
$ OCP_CERT=$(oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d)
oc create cm -n openshift-config registry-cas --from-literal="${OCP_REGISTRY}"="${OCP_CERT}"
$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge
```

## Tag and push the images

Identify all the images needed by the different Kong components and pull them from the original repository (i.e. docker.io), then tag and push
to the openshift registry.

To make this step simpler, there are different files for each component containing all the images that are used and an utility script that can
help you automating the process.

```bash
# Usage ./pull-tag-push.sh filename registry/kong-image-registry
./pull-tag-push.sh kong-mesh.properties $OCP_REGISTRY/kong-image-registry
```

## Allow other namespaces to pull from the kong-image-registry

From the [OpenShift documentation](https://docs.openshift.com/container-platform/4.10/openshift_images/managing_images/using-image-pull-secrets.html#images-allow-pods-to-reference-images-across-projects_using-image-pull-secrets)

```bash
for i in system metrics logging tracing
do
    oc policy add-role-to-group system:image-puller system:serviceaccounts:kong-mesh-$i --namespace=kong-image-registry
done
```