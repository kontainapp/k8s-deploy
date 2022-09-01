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
    echo "usage: $0  [OPTIONS | --cleanup]"
    echo "Creates minicube cluster"
    echo ""
    echo "Prerequisites:"
    echo "  minikube"
    echo "  kubectl"
    echo ""
    echo "--driver docker | podman (default)"
    echo "--runtime cri-o | containerd (default) "
    echo "-h,--help print this help"
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

main() {
    extra_options=""
    if [ "$driver" = "docker" ]; then
        extra_options="--base-image=kicbase:latest --preload=false"
    fi
    minikube start --container-runtime="$runtime" --driver="$driver" "$extra_options" --wait=all
}

do_cleanup() {
    minikube stop
    minikube delete
}

if [ -n "$cleanup" ] && [ $arg_count == 1 ]; then
    do_cleanup
    exit
fi

main