#!/bin/bash

# Copyright 2022 Kontain
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[ "$TRACE" ] && set -x

tag=""
location=""

print_help() {
    echo "usage: $0  [--release-tag | --location] [additional options]"
    echo ""
    echo "Deploys all kustomizations necessary for Kontain in your cluster"
    echo ""
    echo "Options:"
    echo "  --release-tag=<tag> - Kontain release tag to use"
    echo "  --location=<deployment location> - location of kontain-deploy directory"
    echo "*** Note: only --release-tag or --location maybe specified but not both. "
    echo "         If no parametes are specifies, current release will be used"
    echo "Additional options"
    echo "  --help(-h) - prints this message"
    echo "  --config=<file> - path properties file to overwrite special settings in kontain deployment. Currently supported settings are:"
    echo "          TAG - release tag to use to install kontain binaries. By default uses current release"
    echo "          KONTAIN_RELEASE_URL = url to download kontain_bin.tar.gz. Development only"
    echo "  --dry-run=<strategy>" If 'review' strategy, only generate resulting customization file. If 'client' strategy, only print the object that would be sent, without
	sending it. If 'server' strategy, submit server-side request without persisting the resource.
    exit 1
}

kontain_yaml=kontain-deploy.yaml
strategy="none"

for arg in "$@"
do
   case "$arg" in
        --release-tag=*)
            tag="${1#*=}"
        ;;
        --location=*)
            location="${1#*=}"
        ;;
        --dry-run=*)
            strategy="${1#*=}"
        ;;
        --config=*)
            config="${1#*=}"
        ;;
        --help | -h)
            print_help
        ;;
        --* | -*)
            echo "unknown option ${1}"
            print_help
        ;; 
        
    esac
    shift
done

if [ -n  "$tag" ] && [ -n "$location" ]; then 
    echo "Either release TAG or location of configuration files must be specified" 
    exit 1
fi

cloud_provider=$(kubectl get nodes -ojson | jq -r '.items[0] | .spec | .providerID ' | cut -d':' -f1)
if [ "$cloud_provider" = null ]; then
    cloud_provider=$(kubectl get node -ojson | jq -r '.items[0] | .metadata | .name')
fi
os=$(kubectl get nodes -ojson | jq -r '.items[0] | .status | .nodeInfo | .osImage')
runtime=$(kubectl get node -ojson | jq -r '.items[0] | .status | .nodeInfo | .containerRuntimeVersion')
post_process=""

if [ "$cloud_provider" = "azure" ]; then
    overlay=containerd
elif [ "$cloud_provider" = "aws" ]; then
    overlay=amazon-eks-custom
elif [ "$cloud_provider" = "gce" ]; then
    if [[ $os =~ Ubuntu* ]]; then 
        overlay=containerd
    elif [[ $os =~ Google ]]; then 
        echo "Container-Optimized OS from Google is unsupported"
        exit
    fi
elif [ "$cloud_provider" = "k3s" ]; then
    overlay=k3s
    post_process="sudo systemctl restart k3s"
elif [ "$cloud_provider" = "minikube" ]; then
    if [[ $runtime =~ crio* ]]; then 
        overlay=crio
    elif [[ $runtime =~ containerd ]]; then 
        overlay=containerd
    else
        echo "Unsupported runtime"
    fi
else
    echo "Unrecognized cluster provider $cloud_provider."
    echo ""
    echo "If you running K3s make sure to set export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    exit 1
fi

if [ -n "$location" ]; then
    location=${location}/overlays/${overlay}
else 
    if [ -z  "$tag" ]; then
        tags=$(curl -sL https://api.github.com/repos/kontainapp/k8s-deploy/tags | \
            jq  -r '(.[] |select(.name == "current") |.commit|.sha) as $sha | .[] | select(.commit.sha == $sha) | select(.name != "current")|.name')

        for tag in $tags
        do
            rel=$(curl -sL https://api.github.com/repos/kontainapp/k8s-deploy/releases/tags/"${tag}" | \
                jq -r 'select(.author.login == "github-actions[bot]") | .id')
            if [ "$rel" != "null" ]; then 
                break
            fi
        done    
    fi
    
    artifact="https://github.com/kontainapp/k8s-deploy/archive/refs/tags/${tag}.tar.gz"
    curl -sL "$artifact" | tar -xz --strip-components=1
    location=./kontain-deploy/overlays/"${overlay}"
fi

if [ -n "$config" ]; then
    # overwrite environment file
    cp --backup "$config" "${location}"/../../base/config.properties
fi

kubectl kustomize "$location" > "${kontain_yaml}"

if [ -n "$config" ]; then
    # restore original environment file
    mv "${location}"/../../base/config.properties~ "${location}"/../../base/config.properties
fi

if [ "$strategy" = "review" ]; then 
    exit
fi

kubectl apply --dry-run="$strategy" -f "${kontain_yaml}"

if [ "$strategy" == "none" ]; then 
    pod=$(kubectl get pods -A -ojson | jq -r '.items[] | .metadata | .name |select(. | startswith("kontain") )')

    echo "waiting for kontain deamonset to be running"
    kubectl wait --for=condition=Ready pod/"$pod" -n kube-system

    echo "Running post deployment"
    ${post_process}
fi
rm "${kontain_yaml}"