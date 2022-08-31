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

print_help() {
    echo "usage: $0 [options] prefix"
    echo "Creates k3s cluster"
    echo ""
    echo "-h,--help print this help"
    echo "--cleanup Instructs script to delete cluster and all related resourses."
    echo "--config print command to set KUBECONFIG environment variable."
    echo "  Use   source  <(./helpers/k3s-cluster.sh --config ez-test) to set enironment variable." 
    exit 0
}
main() {
    
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy traefik --disable servicelb" INSTALL_K3S_VERSION="v1.24.3+k3s1" sh -s - --write-kubeconfig-mode 666

    echo "waiting for k3s to become active"
    until systemctl is-active k3s; do echo -n "."; done
    echo ""

    echo "waiting for k3s server to establish connection"
    until netstat -nat | grep 644 | grep ESTABLISHED > /dev/null; do echo -n "."; done
    echo ""

    sleep 20

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    kubectl wait --for=condition=Ready pods --all -n kube-system

}

do_cleanup() {

    sudo systemctl stop k3s.service

    /usr/local/bin/k3s-uninstall.sh

    echo "waiting for all precesses to terminate and sockets to free"
    until ! netstat -nat |grep 644|grep TIME_WAIT > /dev/null; do echo -n "."; done
    echo ""
}

arg_count=$#
for arg in "$@"
do
   case "$arg" in
        --cleanup)
            cleanup='yes'
        ;;
        --help | -h)
            print_help
        ;;
        --config)
            echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
            do_exit=true
        ;;
        --* | -*)
            echo "unknown option ${1}"
            print_help
        ;; 
    esac
    shift
done

if [ -n "$cleanup" ] && [ ! $do_exit ] && [ $arg_count == 1 ]; then
    do_cleanup
    exit
fi

[[ ! $do_exit ]] && main
