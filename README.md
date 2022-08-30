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
./kontain-kustomize.sh 
```

### Script options
|Option| Usage|
|---|---|
|--release-tag=\<tag> | Kontain release tag to use. Be default uses current release 
|--location=\<deployment location> | location of kontain-deploy directory 
|--help\(-h) | prints help information"
|--dry-run=<strategy>" |If 'review' strategy, only generate resulting customization file. If 'client' strategy, only print the object that would be sent, without sending it. If 'server' strategy, submit server-side request without persisting the resource.

> **Note**
> Either --release-tag or --location maybe specified but not both. 


