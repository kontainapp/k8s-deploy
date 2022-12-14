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

# all functions that return value do it via this variable, not via echo and subshell
declare func_retval

kontain_yaml=kontain-deploy.yaml
strategy="none"
input_errors=""
clean_dir=false
custom_config=false
command=apply
download_only=false

function print_help() {
    echo "usage: $0  [--deploy-version=version | --deploy-location=path] [--km-version=version | --km-url=url] [--dry-run=strategy] [--download=path]"
    echo ""
    echo "Deploys all kustomizations necessary to Kontain-enable your cluster"
    echo ""
    echo "Options:"
    echo "  --deploy-version=<tag> - Kontain Deployment version to use. Defaults to current release"
    echo "  --deploy-location=<deployment location> - location of kontain-deploy local directory"
    echo "  --km-version=<tag> - Kontain release to deploy. Defaults to current Kontain release"
    echo "  --km-url=<url> - url to download kontain_bin.tar.gz. Development only"
    echo "*** Note: only --release-tag or --location maybe specified but not both. "
    echo "         If no parametes are specifies, current release will be used"
    echo "Additional options"
    echo "  --help(-h) - prints this message"
    echo "  --dry-run=<strategy> If 'review' strategy, only generate resulting customization file. If 'client' strategy, only print the object that would be sent, without 
	sending it. If 'server' strategy, submit server-side request without persisting the resource."
    echo "  --download=<path> - downloads kontain-deploy directory structure to specified location. After script completion overlay file tree can be found in this directory. If needed, directory will be created"
    echo "  --remove - removes all the resources produced by overlay"
    exit 1
}

function cleanup() { 
    if [ $clean_dir = true ]; then
        rm -rf "$download_dir"
    elif [ $custom_config = true ]; then
        # restore original environment file
        mv "${overlay_dir}"/../../base/config.properties~ "${overlay_dir}"/../../base/config.properties
    fi
}

function read_parameter(){
    local key=$(echo "${1}" | cut -f1 -d=)
    local value=""

    if [ ${#key} -lt ${#1} ]; then 
        value=$(echo "${1}" | cut -f2 -d=)
    fi

    if [ -z "$value" ]; then
        input_errors="$input_errors\noption $key requires parameter in the format $key=value"
    fi

    #return value
    func_retval=$value
}

# Download overlays from github artifact refered to by tag. If download_dir is set, use it as target for tar 
# Parameters:
#   1 - tag
# return directory containing overlays via func_retval global 
function download_overlays() {
    tag=$1

    if [ -n "$download_dir" ]; then
        clean_dir=false
    else
        download_dir=./tmp
        clean_dir=true
    fi

    # make sure download_dir exists
    mkdir -p "${download_dir}"
    artifact="https://github.com/kontainapp/k8s-deploy/archive/refs/tags/${tag}.tar.gz"
    curl -sL "$artifact" | tar -xz --strip-components=1 -C "${download_dir}"

    func_retval="$download_dir/kontain-deploy"
}

function prepare_overlay() {
    local location=""

    if [ -n "$overlay_tag" ] && [ -n "$deploy_location" ]; then
        echo "Either --overlay-version or --deploy-location can be specified, but not both"
        exit 1;
    elif [ -n "$overlay_tag" ]; then         
        download_overlays "$overlay_tag"
        location="$func_retval"
    elif [ -n "$deploy_location" ]; then
        location="${deploy_location}"
    else 
        #neither tag nor location is specified for overlays - use current release
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
        download_overlays "$tag"
        location="$func_retval"
    fi

    location="${location}/overlays"

    if [ $custom_config = true ]; then
        # overwrite environment file
        cp --backup "custom.properties" "${location}"/../base/config.properties
    fi

    func_retval="$location"
}

function prepare_km() {
    if [ -n "$km_tag" ] && [ -n "$km_url" ]; then
        echo "Either --km-version or --km-url can be specified, but not both"
        exit 1;
    elif [ -n "$km_tag" ]; then 
        echo "TAG=$km_tag" > custom.properties
        echo "KONTAIN_RELEASE_URL=" >> custom.properties
        echo "TRACE=yes" >> custom.properties
        custom_config=true
    elif [ -n "$km_url" ]; then
        echo "TAG=" > custom.properties
        echo "KONTAIN_RELEASE_URL=$km_url" >> custom.properties
        echo "TRACE=yes" >> custom.properties
        custom_config=true
    else
        # no tag and no url - installing current release
        km_tag=$(curl -L -s https://raw.githubusercontent.com/kontainapp/km/current/km-releases/current_release.txt)
        echo "TAG=$km_tag" > custom.properties
        echo "KONTAIN_RELEASE_URL=" >> custom.properties
        echo "TRACE=yes" >> custom.properties
        custom_config=true
    fi
}

for arg in "$@"
do
   case "$arg" in
        --deploy-version*)
            read_parameter "${1}"
            overlay_tag="${func_retval}"
        ;;
        --deploy-location*)
            read_parameter "${1}"
            deploy_location="${func_retval}"
        ;;
        --km-version*)
            read_parameter "${1}"
            km_tag="${func_retval}"
        ;;
        --km-url*)
            read_parameter "${1}"
            km_url="${func_retval}"
        ;;
        --dry-run*)
            read_parameter "${1}"
            strategy="${func_retval}"
        ;;
        --download*)
            read_parameter "${1}"
            download_dir="${func_retval}"
            download_only=true
        ;;
        --remove)
            command=delete
        ;;
        --help | -h)
            print_help
        ;;
        *)
            echo "unknown option ${1}"
            print_help
        ;; 
            
    esac
    shift
done

if  [ -n "${input_errors}" ]; then
    echo -e "${input_errors}"
    exit 1
fi

# prepare cleanup
trap cleanup EXIT

# handle this first as it may produce custom config
prepare_km

prepare_overlay
overlay_dir="${func_retval}"

if [ $download_only = true ]; then
    #download requested - no application
    exit
fi

cloud_provider=$(kubectl get nodes -ojson | jq -r '.items[0] | .spec | .providerID ' | cut -d':' -f1)
if [ "$cloud_provider" = null ]; then
    cloud_provider=$(kubectl get namespaces -ojson |jq -r '.items[] | .metadata | select(.name=="openshift").name')
    if [ -z "$cloud_provider" ]; then 
        cloud_provider=$(kubectl get node -ojson | jq -r '.items[0] | .metadata | .name')
    fi    
fi
os=$(kubectl get nodes -ojson | jq -r '.items[0] | .status | .nodeInfo | .osImage')
runtime=$(kubectl get node -ojson | jq -r '.items[0] | .status | .nodeInfo | .containerRuntimeVersion')
post_process=""

if [ "$cloud_provider" = "knative" ]; then
    labels=$(kubectl get nodes -ojson | jq '.items[0] | .metadata | .labels')
    # we have to figure out which cluster is was applied to all over again via labels
    if [[ "$labels" =~ .*"azure".* ]]; then
        cloud_provider="azure"
    elif [[ "$labels" =~ .*"minikube".* ]]; then
        cloud_provider="minikube"
    elif [[ "$labels" =~ .*"aws".* ]]; then
        cloud_provider="aws"
    elif [[ "$labels" =~ .*"gce".* ]]; then
        cloud_provider="gce"
    elif [[ "$labels" =~ .*"k3s".* ]]; then
        cloud_provider="k3s"
    else 
        echo "Unrecognized cluster provider $cloud_provider."
        exit 1
    fi
fi    

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
    post_process="echo -e 'Make sure to restart k3s by using the following command\n\tsudo systemctl restart k3s'"
elif [ "$cloud_provider" = "minikube" ]; then
    driver=$(minikube profile list -o json | jq -r '.valid[0]|.Config|.Driver')
    if [[ $runtime =~ crio* ]]; then 
        overlay=crio
    elif [[ $runtime =~ containerd ]]; then 
        overlay=containerd
    else
        echo "Unsupported runtime"
        exit 1
    fi
elif [ "$cloud_provider" = "openshift" ]; then
    echo "In OpenShift"
    overlay=containerd
else
    echo "Unrecognized cluster provider $cloud_provider."
    echo ""
    echo "If you running K3s make sure to set export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    exit 1
fi

config_file=${overlay_dir}/../base/config.properties
if grep -q "K8S_FLAVOUR=" ${config_file}; then
    sed -i "s/\(K8S_FLAVOUR=\)\(.*\)/\1$cloud_provider/" ${config_file}
else
    echo -e "\nK8S_FLAVOUR=$cloud_provider" >> ${config_file}
fi

overlay_dir=${overlay_dir}/${overlay}

kubectl kustomize "$overlay_dir" > "${kontain_yaml}"

if [ "$strategy" = "review" ]; then 
    exit
fi

kubectl "$command" --dry-run="$strategy" -f "${kontain_yaml}"

if [ "$strategy" == "none" ] && [ "$command" == "apply" ]; then 
    echo "waiting for kontain deamonset to be running"
     
    kubectl wait --for=condition=Ready pods -n kube-system -l app=kontain-init --timeout=120s

    eval ${post_process}
fi
rm "${kontain_yaml}"