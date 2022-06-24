# Gateway Usage

Render the Control Plane:

```bash
k kustomize controlpane --enable-helm

# or 

kustomize build /Users/cmwylie19/kong-discovery/validated-patterns/gateway/controlplane 
```

Render the Data Plane:

```bash
k kustomize dataplane --enable-helm
```
