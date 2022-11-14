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

UNQ_POSTFIX=$(mktemp -u XXXXXX | tr '[:upper:]' '[:lower:]')-$$
KONTAIN_NAMESPACE="kontain-snapshot-ns-$UNQ_POSTFIX"
TARGET_POD_NAME="kontain-snaphot-target-$UNQ_POSTFIX"
MAKER_POD_NAME="kontain-snapshot-maker-$UNQ_POSTFIX"

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

SNAPSHOT_YAMLFILE=$DIR/snapshot-maker.yaml
MAKER_POD_ENTRYPOINT_YAML=$DIR/snapshot_entrypoint.yaml

# Files we derive for modifications
POD_YAMLFILE=$DIR/pod-original-$UNQ_POSTFIX.yaml
TARGET_POD_YAML=$DIR/kontain-target-$UNQ_POSTFIX.yaml
MAKER_POD_YAML=$DIR/kontain-maker-$UNQ_POSTFIX.yaml
MAKER_CONFIGMAP_YAML=$DIR/kontain-maker-script-$UNQ_POSTFIX.yaml

SNAP_DOCKER_FILE=$DIR/kmsnap-$UNQ_POSTFIX.dockerfile
# Snapshot directory names. In the container and outside the container
# What happens when we don't run this on the kubernetes node running the deployment?
SNAPDIR_HOST=/tmp/kontain-snapdir-$UNQ_POSTFIX
SNAPDIR_CONTAINER=/tmp/kontain-snapdir-$UNQ_POSTFIX
IMAGE_DIR=$DIR/image-$UNQ_POSTFIX

SUPPORTED_OBJECT_TYPES="deployment pod"

object_type=deployment
object_namespace=""
container_name=""
url_path=""

function cleanup() {
    echo "Cleaning up"
    # clean up all our stuff 
    kubectl delete namespace $KONTAIN_NAMESPACE >& /dev/null
    rm $POD_YAMLFILE >& /dev/null
    rm $TARGET_POD_YAML >& /dev/null
    rm $MAKER_POD_YAML >& /dev/null
    rm $MAKER_CONFIGMAP_YAML >& /dev/null
    rm -rf $IMAGE_DIR >& /dev/null
    rm $SNAP_DOCKER_FILE >& /dev/null

}

function print_help() {
    echo "usage: $0 --type=[deployment|pod] deployment-or-pod-name [--namespace=<namespace> of a pod]"
    echo ""
    echo "Create snapshot of a deployment or pod and apply if needed. "
    echo "Environment variable KONTAIN_SNAPSHOT_REGISTRY must be set prior to calling script in the format"
    echo " registry/account "
    echo " For example, export KONTAIN_SNAPSHOT_REGISTRY=docker.io/kontainapp."
    echo "If repository is private, make sure to login prior to calling the script"
    echo ""
    echo "Options:"
    echo "  deployment-or-pod-name Name of the deployment or pod as printed by command \
                kubectl get deployments \
            or \
                kubect get pods"
    echo " --type type of object. Possible values are deployment(default) or pod"
    echo " --namespace Optional namespace (if other then default) for pod. " 
    echo " --container Name of the pod container to snapshot"
    echo " --url-path / by default "
    exit 1
}

function load_tools() {
    # Get yq
    YQ=$DIR/yq
    if [ ! -f $YQ ] && [ ! -x $YQ ]; then 
        curl -o $YQ -L https://github.com/mikefarah/yq/releases/download/v4.28.1/yq_linux_amd64
        chmod +x YQ
    fi
}

function add_envs()
{    
    filename=$1
    # Add KM_MGTDIR env var to the container
    # Add KM_MGTPIPE env var to allow old km's to work.
    declare -A kontain_envs
    kontain_envs[KM_MGTDIR]=$SNAPDIR_CONTAINER
    kontain_envs[SNAPDIR_HOST]=$SNAPDIR_HOST
    kontain_envs[SNAPDIR_CONTAINER]=$SNAPDIR_CONTAINER
    
    if [ $# -eq 2 ]; then
        # declare a local **reference variable** (hence `-n`) named `data_ref`
        # which is a reference to the value stored in the first parameter
        # passed in
        local -n data_ref="$2"
        for k in "${!data_ref[@]}"; do
            kontain_envs["$k"]="${data_ref["$k"]}"
        done
    fi

    # check for every key and add or update it 
    for i in "${!kontain_envs[@]}"
    do
        has_key=$(key=$i $YQ '.spec.containers[0].env[]|select(.name == strenv(key)).name' $filename)
        if [ "$has_key" = "$i" ]; then 
            key=$i value="${kontain_envs[$i]}" $YQ -i '(.spec.containers[0].env[]|select(.name == strenv(key)).value)|=strenv(value)' $filename
        else
            key=$i value="${kontain_envs[$i]}" $YQ -i '.spec.containers[0].env = [{"name": strenv(key), "value": strenv(value)}] + .spec.containers[0].env' $filename
        fi
    done
}

function set_node_selector() {
    filename=$1

    #delete nodeName if any
    $YQ -i 'del(.spec.nodeName)' $filename

    #add node selector
    host=$NODE_NAME $YQ -i '.spec.nodeSelector += {"kubernetes.io/hostname": strenv(host)}' $filename

}

function get_pod() {

    echo -n "Reading $object_type information....."

    if [ "$object_type" = "deployment" ]; then
        # find a pod that belongs to the deployment and get its yaml

        local selector=$(kubectl get deployment $object_name -o wide | tail -n 1 | awk '{print $8}')
        if [ -z $selector ]; then 
            # kubectl will report error, so we just exit
            exit 1
        fi

        local pod=$(kubectl get pods -l $selector | tail -1 | awk '{print $1}')
        object_namespace="-n $(kubectl get pod $pod -o yaml | $YQ '.metadata.namespace')"

        if [ -z $pod ]; then 
            # kubectl will report error, so we just exit
            exit 1
        fi
    else 
        local pod=$object_name
    fi

    kubectl get pod $object_namespace $pod -o yaml > $POD_YAMLFILE
    local result=$?
    if [ $result -ne 0 ]; then 
        # kubectl will report error, so we just exit
        exit 1
    fi

    # we do NOT support multiple containers per pod - check for that
    local container_count=$($YQ '.spec.containers|length' $POD_YAMLFILE)
    if [ $container_count -gt 1 ]; then
        if [ -z "$container_name"]; then 
            echo "Pod has multiple container, please provide container name"
            exit 1
        else
            # select names of containers to remove   
            declare -a remove_containers=($(cnt=$container_name $YQ '.spec.containers[].name | select (. != strenv(cnt))' $POD_YAMLFILE))
        fi
    else
        container_name=$($YQ '.spec.containers[0].name' $POD_YAMLFILE)
    fi

    # find container id
    # read image the pod was created from
    IMAGE_NAME=$(cnt=$container_name $YQ '.spec.containers[] | select(.name==strenv(cnt)).image' $POD_YAMLFILE)
    NODE_NAME=$($YQ '.spec.nodeName' $POD_YAMLFILE)

    echo "done"
}

function prepare_pod() {

    echo -n "Preparing target pod....."
    cp $POD_YAMLFILE $TARGET_POD_YAML


    # remove extra fields 
    $YQ -i 'del(.status)' $TARGET_POD_YAML
    $YQ -i 'del(.metadata.uid)' $TARGET_POD_YAML
    $YQ -i 'del(.metadata.generateName)' $TARGET_POD_YAML
    $YQ -i 'del(.metadata.ownerReferences)' $TARGET_POD_YAML
    $YQ -i 'del(.metadata.creationTimestamp)' $TARGET_POD_YAML
    $YQ -i 'del(.metadata.labels.pod-template-hash)' $TARGET_POD_YAML
    for i in $remove_containers 
    do
        cnt=$i $YQ -i 'del(.spec.containers[] | select (.name == strenv(cnt)))' $POD_YAMLFILE
    done

    # give pod a name
    pod=$TARGET_POD_NAME $YQ -i '(.metadata.name=strenv(pod))' $TARGET_POD_YAML


    # change namespace to avoid being used by original deployment
    ns=$KONTAIN_NAMESPACE $YQ -i '(.metadata.namespace=strenv(ns))' $TARGET_POD_YAML

    # Add kontain snapshot related properties to the deployment yaml file in $TARGET_POD_YAML
    add_envs $TARGET_POD_YAML
    set_node_selector $TARGET_POD_YAML

    # Add or update snapshot volume
    has_key=$($YQ '.spec.volumes[]|select(.name == "kontain-snap-volume").name' $TARGET_POD_YAML)
    # Add snapshot volume to the pod or deployment
    if [ "$has_key" = "kontain-snap-volume" ]; then 
        # kontain volume is there, make sure the path is correct
        host_path=$SNAPDIR_HOST $YQ -i '(.spec.volumes[]|select(.name == "kontain-snap-volume").hostPath.path=strenv(host_path))' $TARGET_POD_YAML
    else
        # kontain volume definition is not there
        host_path=$SNAPDIR_HOST $YQ -i '.spec.volumes = [{"name": "kontain-snap-volume", "hostPath": {"path": strenv(host_path), "type": "DirectoryOrCreate"}}] + .spec.volumes' $TARGET_POD_YAML
    fi

    # Add snapshot volumeMounts to the container
    has_key=$($YQ '.spec.containers[0].volumeMounts[]|select(.name == "kontain-snap-volume").name' $TARGET_POD_YAML)
    if [ "$has_key" = "kontain-snap-volume" ]; then 
        # the kontain volumeMounts entry is there, be sure the mountPath is correct
        container_path=$SNAPDIR_CONTAINER $YQ -i '(.spec.containers[0].volumeMounts|select(.name == "kontain-snap-volume").mountPath = strenv(container_path))' $TARGET_POD_YAML
    else 
        # kontain volume mount definition is not there
        container_path=$SNAPDIR_CONTAINER $YQ -i '.spec.containers[0].volumeMounts = [{"name": "kontain-snap-volume", "mountPath": strenv(container_path)}] + .spec.containers[0].volumeMounts' $TARGET_POD_YAML
    fi

    # Add "runtimeClassName: kontain" to the pod or deployment.
    $YQ '(.spec.runtimeClassName = "kontain")' -i $TARGET_POD_YAML
 
    # kubectl apply always succeeds, so pointless to test, that is why we use wait and analize kubectl output
    # we wait for pod to be ready before assuming it works in the prepare_snapshot_pod function
    kubectl apply -f $TARGET_POD_YAML >& /dev/null

    echo "done"
}

function prepare_snapshot_pod() {

    echo -n "Preparing snapshot maker....."
    cp $SNAPSHOT_YAMLFILE $MAKER_POD_YAML
    cp $MAKER_POD_ENTRYPOINT_YAML $MAKER_CONFIGMAP_YAML

    #make sure pod name is what this script expects 
    pod=$MAKER_POD_NAME $YQ -i '(.metadata.name=strenv(pod))' $MAKER_POD_YAML
    #assign generated namespace name to both maker pod and maker configmaps
    ns=$KONTAIN_NAMESPACE $YQ -i '(.metadata.namespace=strenv(ns))' $MAKER_POD_YAML
    ns=$KONTAIN_NAMESPACE $YQ -i '(.metadata.namespace=strenv(ns))' $MAKER_CONFIGMAP_YAML


    # pass port and ip to the control pod 
    kubectl wait --for=condition=Ready pod -n $KONTAIN_NAMESPACE $TARGET_POD_NAME >& /dev/null
    status=$(kubectl get pod -n $KONTAIN_NAMESPACE $TARGET_POD_NAME -o jsonpath="{.status.phase}")
    if [ "$status" != "Running" ]; then 
        echo "Error starting target pod"
        exit 1
    fi

    ip=$(kubectl get pod -n $KONTAIN_NAMESPACE $TARGET_POD_NAME -o jsonpath='{.status.podIP}')
    port=$(kubectl get pod -n $KONTAIN_NAMESPACE $TARGET_POD_NAME -o jsonpath='{.spec.containers[0].ports[0].containerPort}')
    port=${port:=80}

    if [ -z $ip ] || [ -z $port ]; then
        echo "Target pod does not have IP or port - no entrypoint"
        exit 1
    fi

    declare -A extra_kontain_envs
    extra_kontain_envs[URL]="http://$ip:$port/$url_path"

    add_envs $MAKER_POD_YAML extra_kontain_envs

    # assign pod to specific node
    set_node_selector $MAKER_POD_YAML

    kubectl apply -f $MAKER_CONFIGMAP_YAML >& /dev/null
    kubectl apply -f $MAKER_POD_YAML >& /dev/null

    # wait for manager pod to be ready, i.e until snapshot is made 
    kubectl wait --for=condition=Ready pod -n $KONTAIN_NAMESPACE $MAKER_POD_NAME >& /dev/null
    status=$(kubectl get pod -n $KONTAIN_NAMESPACE $MAKER_POD_NAME -o jsonpath="{.status.phase}")
    if [ "$status" != "Running" ]; then 
        echo "Error starting maker pod"
        exit 1
    fi

    echo "done"
}

function make_image() {

    echo -n "Generating a new snapshot-based image....."

    mkdir -p $IMAGE_DIR
    kubectl cp $KONTAIN_NAMESPACE/$MAKER_POD_NAME:$SNAPDIR_CONTAINER $IMAGE_DIR >& /dev/null
    
    if ! compgen -G "$IMAGE_DIR/kmsnap*" > /dev/null; then
        echo "Snapshot file could not be made or retrieved"
        exit 1
    fi

    # Create a new container image to run the snapshot
    # This needs to handle differing snapshot filenanes kmsnap vs kmsnap.XXX.NNN
    # Build dockerfile
    # Build container image
    # Push the container to a remote repository
    SNAPFILE=$(basename $IMAGE_DIR/kmsnap*)

    cat <<EOF >$SNAP_DOCKER_FILE
FROM $IMAGE_NAME
COPY $SNAPFILE /kmsnap
CMD ["/kmsnap"]
EOF

    
    SNAP_IMAGE_NAME=$KONTAIN_SNAPSHOT_REGISTRY/$(basename "${IMAGE_NAME%%:*}")-kmsnap

    chown $(id -u):$(id -g) $IMAGE_DIR/$SNAPFILE
    chmod 755 $IMAGE_DIR/$SNAPFILE

    result=$(docker build -t $SNAP_IMAGE_NAME -f $SNAP_DOCKER_FILE $IMAGE_DIR 2>&1 > /dev/null)
    if [ $? != 0 ]; then
        echo "Failed to build snapshot image"
        echo "docker: $result"
        exit 1
    fi
    echo "done"
}

function upload_image() {
    echo -n "Uploading image to Container Registry $KONTAIN_SNAPSHOT_REGISTRY ....."

    result=$(docker push $SNAP_IMAGE_NAME 2>&1 > /dev/null)
    if [ $? != 0 ]; then
        echo "Failed to push image to the repository"
        echo "Make sure container registry $KONTAIN_SNAPSHOT_REGISTRY exists and you are logged into it with necessary permissions"
        echo "docker: $result"
        exit 1
    fi
    echo "Image $SNAP_IMAGE_NAME has been uploaded"

}
function update_pods() {

    echo -n "Updating $object_type with new image ....."

    # kubectl set image is just assignment and since we already cheked deployment exists it will perform teh assignment
    # if image is broken, the only way to see it is to review status of deployment pods 
    kubectl set image $object_type/$object_name $CONTAINER_NAME=$SNAP_IMAGE_NAME >& /dev/null

    echo "done"

    if [ "$object_type" = "deployment" ]; then 
        echo -n "Waiting for rollout to finish"
        while kubectl rollout status $object_type/$object_name | grep -q Waiting
        do 
            echo -n .
            sleep 3s
        done
        echo ""
        # print final status of deployment 
        kubectl rollout status $object_type/$object_name
    else 
        # wait for pod to become ready 
        kubectl wait --for=condition=Ready pod -n $KONTAIN_NAMESPACE $object_name >& /dev/null
    fi

}

function main() {

    load_tools

    kubectl create namespace $KONTAIN_NAMESPACE >& /dev/null

    get_pod
    prepare_pod
    prepare_snapshot_pod
    make_image
    upload_image 

    echo "Do you wish to update relevant pods?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes )
            update_pods 
            exit
            ;;
            No ) 
            exit
            ;;
        esac
    done
}

for arg in "$@"
do
case "$arg" in
        --help|-h)
            print_help
            exit
        ;;
        --type=*)
            object_type=${1#*=}
        ;;
        --namespace=*)
            object_namespace="-n ${1#*=}"
        ;;
        --container=*)
            container_name="${1#*=}"
        ;;
        --url-path=*)
            url_path="${1#*=}"
        ;;
        *)
            object_name="${1#*=}"
        ;;
    esac
    shift
done

if [ -z "$object_name" ]; then 
    echo "${object_type^} name is required"

    exit 1;
fi

if  [[ ! "$SUPPORTED_OBJECT_TYPES" =~ "$object_type" ]]; then
    echo "Unsupported object type to snapshot"
    exit 1
fi

if [ -z "$KONTAIN_SNAPSHOT_REGISTRY" ]; then 
    echo "Environment variable KONTAIN_SNAPSHOT_REGISTRY must be set in the format"
    echo " registry/account "
    echo " For example, export KONTAIN_SNAPSHOT_REGISTRY=docker.io/kontainapp "
    echo " and you must be logged in to it to push snapshot image"
    exit 1;
fi

trap cleanup EXIT

main
