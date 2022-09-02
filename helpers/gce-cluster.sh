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

region=us-central1-a
arg_count=$#

print_help() {
    echo "usage: $0  [options] --project=<project id> prefix"
    echo "Creates AKS cluster with the name <prefix>-aks-cluster. All other associated recource names are prefixes with <prefix> "
    echo ""
    echo "Prerequisites:"
    echo "  GKE CLI"
    echo "  GKE Accout and Project"
    echo "  gke-gcloud-auth-plugin installed"
    echo ""
    echo "-h,--help print this help"
    echo "--project project id"
    echo "--key-file path to file containing your key"
    echo "--region Sets aws region. Default to us-central1-a"
    echo "--cleanup Instructs script to delete cluster and all related resourses "
    exit 0
}

for arg in "$@"
do
   case "$arg" in
        --project=*)
            project_name="${1#*=}"
        ;;
        --key-file=*)
            key_file="${1#*=}"
        ;;
        --region=*)
            region="${1#*=}"
            arg_count=$((arg_count-1))
        ;;
        --cleanup)
            cleanup='yes'
        ;;
        --help | -h)
            print_help
        ;;
        --* | -*)
            echo "unknown option ${1}"
            print_help
        ;; 
        *)
            if [[ -z "${prefix}" ]]; then 
                prefix=$arg 
                arg_count=$((arg_count-1))
            else
                echo "Too many arguments"
                print_help
            fi
        ;;
    esac
    shift
done

if [ -z "${prefix}" ]; then
    echo "Prefix is required "
    exit 1
fi

readonly cluster_name="${prefix}"-cluster

do_cleanup() {
    #Delete our GKE cluster
    gcloud container clusters delete "${cluster_name}" --region="$region" 

}

main() {

    # if key file provided - authenticate with google cloud, otherwise assume it has already been done  
    if [ -n "${key_file}" ]; then
        gcloud auth activate-service-account --key-file "${key_file}"
    fi

    #Set our current project context
    gcloud config set project "${project_name}"

    #Enable GKE services in our current project
    gcloud services enable container.googleapis.com

    #Tell GKE to create a single zone, single node cluster for us. 
    #https://cloud.google.com/compute/quotas#checking_your_quota
    gcloud container clusters create "${cluster_name}" --region "${region}" --num-nodes=1 --image-type=UBUNTU_CONTAINERD

}

if [ -n "$cleanup" ] && [ $arg_count == 1 ]; then
    do_cleanup
    exit
fi

if [ -z "$project_name" ]; then
    echo "Project is required "
    exit 1
fi

main