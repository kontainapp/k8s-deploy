# k8s-deploy

K8s-deploy provides Kontain Kubernetes deployment configuration and helper files.

# Kubernetes quick start

Kontain currently supports AKS, EKS, minikube (docker, podman/containerd, crio), GCE, K3S

> **Note**
> Before you begin, make sure kubectl is installed and connected to your cluster

1. Download current version of kustomization script 

```
curl -o kontain-kustomize.sh -L https://raw.githubusercontent.com/kontainapp/k8s-deploy/current/kontain-kustomize.sh 
chmod +x kontain-kustomize.sh
```
2. Run script to use latest version of deployment 

```
./kontain-kustomize.sh [--deploy-version=version | --deploy-location=path] [--km-version=version | --km-url=url>] [--dry-run=strategy] [--download=path]

```

### Script options
|Option| Usage|
|----------------------------------|---|
|--deploy-version=\<tag> | Kontain Deployment version to use. Defaults to current release|
|--deploy-location=\<deployment location> | location of local kontain-deploy directory|
|--km-version=\<tag> | Kontain release to deploy. Defaults to current Kontain release|
|--km-url=\<url> | url to download kontain_bin.tar.gz. Development only|
|--help(-h) | prints this message|
|--dry-run=\<strategy> | If 'review' strategy, only generate resulting customization file. If 'client' strategy, only print the object that would be sent, without sending it. If 'server' strategy, submit server-side request without persisting the resource.|
|--download=\<path> | downloads kontain-deploy directory structure to specified location. After script completion overlay file tree can be found in this directory.|
| --remove | removes all the resources produced by overlay


