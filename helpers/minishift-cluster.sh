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

arg_count=$#
VER="1.34.3"

main() {
    curl -L https://github.com/minishift/minishift/releases/download/v$VER/minishift-$VER-linux-amd64.tgz -o minishift-$VER-linux-amd64.tgz
    tar xvf minishift-$VER-linux-amd64.tgz

    #sudo mv minishift-$VER-linux-amd64/minishift /usr/local/bin 
    minishift=minishift-$VER-linux-amd64/minishift

    "$minishift" start --iso-url https://github.com/minishift/minishift-b2d-iso/releases/download/v1.3.0/minishift-b2d.iso

    eval $($minishift oc-env)

    oc login -u system:admin

}

do_cleanup() {
    minishift stop --froce
    minishift delete  --clear-cache --force
    rm -rf ~/.kube/
    rm -rf minishift-$VER-linux-amd64
    rm minishift-$VER-linux-amd64.tgz
    PATH=$(echo "$PATH" | sed -e 's/:\/d\/Programme\/cygwin\/bin$//')
}

print_help() {
    echo "usage: $0  [OPTIONS | --cleanup]"
    echo "Creates minishift cluster"
    echo ""
    echo "Prerequisites:"
    echo "  "
    echo "  kubectl"
    echo ""
    echo "-h,--help print this help"
    echo "--cleanup Instructs script to delete cluster and all related resourses "
    exit 0
}

for arg in "$@"
do
   case "$arg" in
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

if [ -n "$cleanup" ] && [ $arg_count == 1 ]; then
    do_cleanup
    exit
fi

main