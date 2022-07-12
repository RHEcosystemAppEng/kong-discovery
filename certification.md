# Certification Process

[Docs](https://access.redhat.com/documentation/en-us/red_hat_software_certification/8.45/html-single/red_hat_software_certification_workflow_guide/index#con_operator-certification_openshift-sw-cert-workflow-complete-pre-certification-checklist-for-containers)

## Create an account

Refer to [Red Hat Connect](https://connect.redhat.com/login) and sign up for a Technology Partner account.
The defaults should be fine.

## Create a project

* Create a Certification Project for a Container Image
* Choose a project name. e.g. rrm-kong-gateway
* Red Hat Universal Base Image
* Non-Red Hat Container Registry

## Create an api-key

Go to _My account -> My user profile -> API keys_ and create an api-key. Save the key as it will not be shown again.

## Submit the container for verification

You must use the [Preflight tool](https://github.com/redhat-openshift-ecosystem/openshift-preflight)
Run the Preflight tool and submit the results.

In the Overview or in the URL you can find the projectID

Run the preflight command. Use the `--submit` flag if you want to submit the results to Red Hat. Do this once the check passes locally.
If you find issues you can check the console output and the `preflight.log` file.

```bash
$ preflight check container --submit --pyxis-api-token=$API_TOKEN --certification-project-id=$PROJECTID docker.io/kong/kong-gateway:2.8-rhel7
time="2022-07-07T19:29:55+02:00" level=info msg="certification library version 1.3.1 <commit: 5a93a15aba8980fcf6184bb3134de4b6f0ca4b13>"
time="2022-07-07T19:30:18+02:00" level=info msg="check completed: HasLicense" result=PASSED
time="2022-07-07T19:30:20+02:00" level=info msg="check completed: HasUniqueTag" result=PASSED
time="2022-07-07T19:30:20+02:00" level=info msg="check completed: LayerCountAcceptable" result=PASSED
time="2022-07-07T19:30:20+02:00" level=info msg="check completed: HasNoProhibitedPackages" result=PASSED
time="2022-07-07T19:30:20+02:00" level=info msg="check completed: HasRequiredLabel" result=PASSED
time="2022-07-07T19:30:20+02:00" level=info msg="USER kong specified that is non-root"
time="2022-07-07T19:30:20+02:00" level=info msg="check completed: RunAsNonRoot" result=PASSED
time="2022-07-07T19:30:25+02:00" level=info msg="check completed: HasModifiedFiles" result=PASSED
time="2022-07-07T19:30:26+02:00" level=info msg="check completed: BasedOnUbi" result=PASSED
{
    "image": "docker.io/kong/kong-gateway:2.8-rhel7",
    "passed": true,
    "test_library": {
        "name": "github.com/redhat-openshift-ecosystem/openshift-preflight",
        "version": "1.3.1",
        "commit": "5a93a15aba8980fcf6184bb3134de4b6f0ca4b13"
    },
    "results": {
        "passed": [
            {
                "name": "HasLicense",
                "elapsed_time": 0,
                "description": "Checking if terms and conditions applicable to the software including open source licensing information are present. The license must be at /licenses"
            },
            {
                "name": "HasUniqueTag",
                "elapsed_time": 1404,
                "description": "Checking if container has a tag other than 'latest', so that the image can be uniquely identified."
            },
            {
                "name": "LayerCountAcceptable",
                "elapsed_time": 0,
                "description": "Checking if container has less than 40 layers.  Too many layers within the container images can degrade container performance."
            },
            {
                "name": "HasNoProhibitedPackages",
                "elapsed_time": 124,
                "description": "Checks to ensure that the image in use does not include prohibited packages, such as Red Hat Enterprise Linux (RHEL) kernel packages."
            },
            {
                "name": "HasRequiredLabel",
                "elapsed_time": 0,
                "description": "Checking if the required labels (name, vendor, version, release, summary, description) are present in the container metadata."
            },
            {
                "name": "RunAsNonRoot",
                "elapsed_time": 0,
                "description": "Checking if container runs as the root user because a container that does not specify a non-root user will fail the automatic certification, and will be subject to a manual review before the container can be approved for publication"
            },
            {
                "name": "HasModifiedFiles",
                "elapsed_time": 5595,
                "description": "Checks that no files installed via RPM in the base Red Hat layer have been modified"
            },
            {
                "name": "BasedOnUbi",
                "elapsed_time": 703,
                "description": "Checking if the container's base image is based upon the Red Hat Universal Base Image (UBI)"
            }
        ],
        "failed": [],
        "errors": []
    }
}
time="2022-07-07T19:30:26+02:00" level=info msg="preparing results that will be submitted to Red Hat"
time="2022-07-07T19:30:31+02:00" level=info msg="Test results have been submitted to Red Hat."
time="2022-07-07T19:30:31+02:00" level=info msg="These results will be reviewed by Red Hat for final certification."
time="2022-07-07T19:30:31+02:00" level=info msg="The container's image id is: 62c71834c9805503acd034ec."
time="2022-07-07T19:30:31+02:00" level=info msg="Please check https://connect.redhat.com/projects/62c714b4089234e0e036b1f0/images/62c71834c9805503acd034ec/scan-results to view scan results."
time="2022-07-07T19:30:31+02:00" level=info msg="Please check https://connect.redhat.com/projects/62c714b4089234e0e036b1f0/overview to monitor the progress."
time="2022-07-07T19:30:31+02:00" level=info msg="Preflight result: PASSED"
```

Check the results and if everything went fine, move to the next step.

## Provide details about your container

In the project page, fill in all the missing required fields.

I used the following for the Kong Gateway image.

* Summary/Description/Instructions: Not relevant
* Image Type: Component Image
* Application categories: API Management / Middleware
* Supported Platforms: OCP
* Host Lvl access: Unprivileged
* Release Category: GA

Submit the form.

## Repeat the process for all the images managed by the operator

### Gateway

#### Kong Gateway

```bash
preflight check container --pyxis-api-token=$API_TOKEN --certification-project-id=$PROJECTID docker.io/kong/kong-gateway:2.8-rhel7
...
time="2022-07-07T19:30:31+02:00" level=info msg="Preflight result: PASSED"
```

#### Kubernetes Ingress Controller

```bash
preflight check container --pyxis-api-token=$API_TOKEN --certification-project-id=$PROJECTID docker.io/kong/kubernetes-ingress-controller:2.4-redhat
time="2022-07-07T19:42:09+02:00" level=info msg="Preflight result: PASSED"
```

### Mesh

They are both not valid images

* docker.io/kong/kuma-cp:1.8.0
* docker.io/kong/kuma-dp:1.8.0

```log
time="2022-07-07T19:42:19+02:00" level=info msg="certification library version 1.3.1 <commit: 5a93a15aba8980fcf6184bb3134de4b6f0ca4b13>"
time="2022-07-07T19:42:27+02:00" level=error msg="could not get rpm list, continuing without it: stat /tmp/preflight-1210270993/fs/var/lib/rpm/Packages: no such file or directory"
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: HasLicense" result=FAILED
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: HasUniqueTag" result=PASSED
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: LayerCountAcceptable" result=PASSED
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: HasNoProhibitedPackages" err="unable to get a list of all packages in the image: could not get rpm list: stat /tmp/preflight-1210270993/fs/var/lib/rpm/Packages: no such file or directory" result=ERROR
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: HasRequiredLabel" result=FAILED
time="2022-07-07T19:42:27+02:00" level=info msg="USER kuma-cp specified that is non-root"
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: RunAsNonRoot" result=PASSED
time="2022-07-07T19:42:27+02:00" level=info msg="check completed: HasModifiedFiles" err="could not generate modified files list: could not get rpm list: stat /tmp/preflight-1210270993/fs/var/lib/rpm/Packages: no such file or directory" result=ERROR
time="2022-07-07T19:42:28+02:00" level=info msg="check completed: BasedOnUbi" result=FAILED
time="2022-07-07T19:42:28+02:00" level=info msg="Preflight result: FAILED"
```

## Certify the Operator

[Official Docs](https://access.redhat.com/documentation/en-us/red_hat_software_certification/8.45/html-single/red_hat_software_certification_workflow_guide/index#con_operator-certification_openshift-sw-cert-workflow-complete-pre-certification-checklist-for-containers)

Create another project of type _Operator Bundle Image_

Select a name e.g. `rrm-kong-gateway-operator` and set the type _Red Hat Certified_

You will only need to add the operator bundle details in the portal.

### Certify on my own OCP cluster

I followed the following instructions for the [Operator Certification CI Pipeline](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/4.9/ga/ci-pipeline.md)

* Install the [Operator Certification Operator](https://github.com/redhat-openshift-ecosystem/operator-certification-operator)
* Create a GitHub API Token so that the Pipeline can create a PR for you. The API token must have the Repo scope and all sub-scopes added.
* Fork the [Certified Operators Repo](https://github.com/redhat-openshift-ecosystem/certified-operators)
* Clone and create a branch. Then add the operator bundle

```bash
git clone git@github.com:ruromero/certified-operators.git
mkdir -p certified-operators/operators/kong-offline-operator/0.10.0
cp -r /path/to/kong-operator/bundle certified-operators/operators/kong-offline-operator/0.10.0
cd certified-operators
git checkout -b kong-operator
```

Create the operators/kong-offline-operator/ci.yaml file with the id of your project

```yaml
cert_project_id: 62c71c89089234e0e036b1f2
```

Add and commit all the changes

```bash
git add .
git commit -sm "Added kong-operator v0.10.0 bundle"
git push origin kong-operator
```

* Create the `oco` namespace
* Create secrets with the Kubeconfig, the API Token and the Red Hat Container API Access key.

```bash
oc create secret generic kubeconfig --from-file=kubeconfig=$KUBECONFIG
oc create secret generic github-api-token --from-literal GITHUB_TOKEN=<GH_TOKEN>
oc create secret generic pyxis-api-secret --from-literal pyxis_api_key=<RH_API_KEY>
```

* Add private key to access GH repo

```bash
base64 /path/to/private/key
```

Create a secret that contains the base64 encoded private key

```bash
oc create secret generic github-ssh-credentials --from-file=id_rsa=my.key                                 
secret/github-ssh-credentials created
```

* Install the certification pipeline and dependencies

```bash
git clone https://github.com/redhat-openshift-ecosystem/operator-pipelines
cd operator-pipelines
oc apply -R -f ansible/roles/operator-pipeline/templates/openshift/pipelines
oc apply -R -f ansible/roles/operator-pipeline/templates/openshift/tasks
```

* Create a secret for pull from the redhat registry. Find more info here [Registry Authentication](https://access.redhat.com/RegistryAuthentication)

```bash
oc create secret docker-registry registry-dockerconfig-secret \
    --docker-server=registry.connect.redhat.com \
    --docker-username=<registry username> \
    --docker-password=<registry password> \
    --docker-email=<registry email>
```

* Create the container repository for the `kong-offline-operator-bundle` and `kong-offline-operator-index` images.
I'm using my quay.io repository because it is where the bundle image is going to be pushed.
The repository must exist and the dockerconfig must include the token with permissions to push to it.

* Get a token that has write permissions and update the `registry-dockerconfig-secret`. The decoded secret `auths` is expected
to have `registry.connect.redhat.com` and `quay.io`.

```bash
$ oc get secrets registry-dockerconfig-secret -oyaml | yq '.data[.dockerconfigjson]' | base64 -d
{
  "auths": {
    "registry.connect.redhat.com": {
      "auth": "<redacted>"
    },
    "quay.io": {
      "auth": "<redacted>"
    }
  }
}
```

**NOTE**: You can use the internal OCP registry, for that you have to merge the `registry.connect.redhat.com` auth token with the pipeline service account secret into a new secret. example:

```bash
$ oc get secrets registry-dockerconfig-secret -oyaml | yq '.data[.dockerconfigjson]' | base64 -d
{
  "auths": {
    "registry.connect.redhat.com": {
      "auth": "<redacted>"
    },
    "image-registry.openshift-image-registry.svc:5000": {
      "username": "serviceaccount",
      "password": "<redacted>",
      "email": "serviceaccount@example.org",
      "auth": "<redacted>"
    },
    ...
  }
}
```

* Run the pipeline (using a quay.io)

```bash
GIT_REPO_URL=git@github.com:ruromero/certified-operators.git
BUNDLE_PATH=operators/kong-operator/0.10.0
GIT_BRANCH=kong-operator
GIT_USERNAME=ruromero
GIT_EMAIL=rromerom@redhat.com
REGISTRY=quay.io
IMAGE_NAMESPACE=ruben

tkn pipeline start operator-ci-pipeline \
  --param git_repo_url=$GIT_REPO_URL \
  --param git_branch=$GIT_BRANCH \
  --param bundle_path=$BUNDLE_PATH \
  --param git_username=$GIT_USERNAME \
  --param git_email=$GIT_EMAIL \
  --param pin_digests=true \
  --param registry=$REGISTRY \
  --param image_namespace=$IMAGE_NAMESPACE \
  --param env=prod \
  --param submit=true \
  --param upstream_repo_name=redhat-openshift-ecosystem/certified-operators \
  --workspace name=pipeline,volumeClaimTemplateFile=templates/workspace-template.yml \
  --workspace name=ssh-dir,secret=github-ssh-credentials \
  --workspace name=registry-credentials,secret=registry-dockerconfig-secret \
  --showlog
```

* Run the pipeline (using the default registry)

```bash
GIT_REPO_URL=git@github.com:ruromero/certified-operators.git
BUNDLE_PATH=operators/kong-operator/0.10.0
GIT_BRANCH=kong-operator
GIT_USERNAME=ruromero
GIT_EMAIL=rromerom@redhat.com

tkn pipeline start operator-ci-pipeline \
  --param git_repo_url=$GIT_REPO_URL \
  --param git_branch=$GIT_BRANCH \
  --param bundle_path=$BUNDLE_PATH \
  --param git_username=$GIT_USERNAME \
  --param git_email=$GIT_EMAIL \
  --param pin_digests=true \
  --param registry=$REGISTRY \
  --param env=prod \
  --param submit=true \
  --param upstream_repo_name=redhat-openshift-ecosystem/certified-operators \
  --workspace name=pipeline,volumeClaimTemplateFile=templates/workspace-template.yml \
  --workspace name=ssh-dir,secret=github-ssh-credentials \
  --workspace name=registry-credentials,secret=registry-dockerconfig-secret \
  --showlog
```

If everything went fine, there should be a PR created at https://github.com/redhat-openshift-ecosystem/certified-operators/pulls

And the status of the _Test your operator bundle data and submit a pull request_ should be green.

Wait until all the checks in the PR have finished and try to troubleshoot them if any fails.
