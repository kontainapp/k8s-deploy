# k8s-deploy

K8s-deploy provides Kontain Kubernetes deployment configuration and helper files.

# Kubernetes quick start

Kontain currently supports AKS, EKS, minikube (docker, podman/containerd, crio), GCE, K3S

> **Note**
> Before you begin, make sure kubectl is installed and connected to your cluster

1. To download current version of kustomization script 

```
curl -o kontain-kustomize.sh -L https://raw.githubusercontent.com/kontainapp/k8s-deploy/current/kontain-kustomize.sh 
chmod +x kontain-kustomize.sh
```

2. Run script to use latest version of deployment 

```
./kontain-kustomize.sh 

```

3. To apply current release of kontain-deployment 
```
curl -s https://raw.githubusercontent.com/kontainapp/k8s-deploy/current/kontain-kustomize.sh  | bash -s -
```

4. To download deployment files (here to /tmp directory) without applying 
```
curl -s https://raw.githubusercontent.com/kontainapp/k8s-deploy/current/kontain-kustomize.sh  | bash -s - -- --download=/tmp 
```

### Script options

kontain-kustomize.sh [--deploy-version=version | --deploy-location=path] [--km-version=version | --km-url=url>] [--dry-run=strategy] [--download=path] [--remove]
|Option| Usage|
|----------------------------------|---|
|--deploy-version=\<tag> | Kontain Deployment version to use. Defaults to current release|
|--deploy-location=\<deployment location> | location of local kontain-deploy directory. Use --download to download kontain-deploy directory to local path. |
|--km-version=\<tag> | Kontain release to deploy. Defaults to current Kontain release|
|--km-url=\<url> | url to download kontain_bin.tar.gz. Development only|
|--help(-h) | prints this message|
|--dry-run=\<strategy> | If 'review' strategy, only generate resulting customization file. If 'client' strategy, only print the object that would be sent, without sending it. If 'server' strategy, submit server-side request without persisting the resource.|
|--download=\<path> | downloads kontain-deploy directory structure to specified location. If directory down not exist, it will be created. This directory can be used as path for --deploy-location |
| --remove | removes all the resources produced by overlay


