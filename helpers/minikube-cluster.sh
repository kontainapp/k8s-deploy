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
export MINIKUBE_IN_STYLE=false

arg_count=$#
runtime="containerd"
driver="podman"

print_help() {
    echo "usage: $0  [OPTIONS | --cleanup | --stop| --restart]"
    echo "Creates minikube cluster"
    echo ""
    echo "Prerequisites:"
    echo "  minikube"
    echo "  kubectl"
    echo ""
    echo "--driver=<driver> docker | podman (default)"
    echo "--runtime=<runtime>  cri-o | containerd (default) "
    echo "-h,--help print this help"
    echo "--stop stop cluster" 
    echo "--restart Restart minikube with previous configuration"
    echo "--cleanup Instructs script to delete cluster and all related resourses "
    exit 0
}

for arg in "$@"
do
   case "$arg" in
        --driver=*)
            driver="${1#*=}"
        ;;
        --runtime=*)
            runtime="${1#*=}"
        ;;
        --restart)
            restart='yes'
        ;;
        --stop)
            stop='yes'
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
    esac
    shift
done

create_cluster() {
    extra_options=""
    if [ "$driver" = "docker" ]; then
        extra_options="--preload=false"
    fi
    
    minikube start --container-runtime="$runtime" --driver="$driver" "$extra_options" --wait=all --logtostderr=true  -v=10 --wait-timeout=10m0s

    status=$(minikube status -ojson |jq -r '.APIServer')
    while [ $status != 'Running' ]
    do
        sleep 1s
        status=$(minikube status -ojson |jq -r '.APIServer')
    done

}

do_stop() {
    minikube stop
    status=$(minikube status -ojson |jq -r '.APIServer')
    while [ $status != 'Stopped' ]
    do
        sleep 1s
        status=$(minikube status -ojson |jq -r '.APIServer')
    done
}

do_restart() {

    driver=$(minikube profile list -o json | jq -r '.valid[0]|.Config|.Driver')
    runtime=$(minikube profile list -o json| jq -r '.valid[0]|.Config|.KubernetesConfig|.ContainerRuntime')
    if [ "$driver" = 'docker' ]; then 
        do_stop
        minikube start
    elif [ "$driver" = 'podman' ]; then
        do_cleanup
        minikube start --container-runtime="$runtime" --driver="$driver" --wait=all --logtostderr=true  --wait-timeout=10m0s --force-systemd=true
    fi
}

do_cleanup() {
    do_stop
    minikube delete --purge=true --all
}

if [ -n "$restart" ] && [ $arg_count == 1 ]; then
    do_restart
    exit
elif [ -n "$restart" ]; then 
    print_help
fi

if [ -n "$stop" ] && [ $arg_count == 1 ]; then
    do_stop
    exit
elif [ -n "$stop" ]; then 
    print_help
fi

if [ -n "$cleanup" ] && [ $arg_count == 1 ]; then
    do_cleanup
    exit
elif [ -n "$cleanup" ]; then 
    print_help
fi

create_cluster
