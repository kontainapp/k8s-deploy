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

#
# A script to take a customer supplied kubernetes pod or deployment yaml file, massage it to
# be able to be snapshotted.  We assume it is already using kontain runtime
# Then apply the deployment yaml file.
# Verify that the pod/deployment is accessible with curl.
# Then take a snapshot of the application running in the pod/deployment.
# Delete the pod/deployment.
# Then build a new container image that is running the snapshot.
# Then massage the deployment yaml file to run the snapshot instead of the application.
# Start the pod/deployment.
# Verify that the application works.
# Delete the deployment.
#
# Brokeness:
# - we don't operate on all containers in the pod/deployment, we should pick the one we want.
# - we don't handle .yaml files that contain multiple deployments or pods, reject them?
# - doesn't handle services with multiple ports, just use the first port.

# SNAPREPO, YAMLFILE, and YAMLKIND are assumed to be supplied by the user.
# Store our generated snapshot container image here
SNAPREPO=kontain8paulp
# The customer deployment definition
YAMLFILE=dweb-plain.yaml
# Allow some flexibility to deal with those yaml files that skip using the "kind: Deployment"
# The script should try to figure this out on its own.
export YAMLKIND="Pod"
#export YAMLKIND="Deployment"

KMCLI_PATH=../build/km_cli/km_cli
#KMCLI_PATH=/opt/kontain/bin/km_cli

# Get yq
#wget https://github.com/mikefarah/yq/releases/download/v4.28.1/yq_linux_amd64 -O yq
#chmod 755 yq
YQPATH=~/Downloads/yq_linux_amd64

# Files we derive from the customer's yaml file
KONTAIN_YAMLFILE=`dirname $YAMLFILE`/`basename $YAMLFILE .yaml`-kontain.yaml
RUNSNAP_YAMLFILE=`dirname $YAMLFILE`/`basename $YAMLFILE .yaml`-kontain-snap.yaml

# Snapshot directory names.  In the container and outside the container
# What happens when we don't run this on the kubernetes node running the deployment?
export SNAPDIR_HOST=/tmp/kontain-snapdir-$$
export SNAPDIR_CONTAINER=/tmp/kontain-snapdir

# Create the host dir for the km mgt pipe and to hold the snapshot
sudo rm -fr $SNAPDIR_HOST
mkdir -p $SNAPDIR_HOST
chmod 777 $SNAPDIR_HOST

# Extract some names from the customer yaml.
if test "$YAMLKIND" == "Deployment"; then
  DEPLOYMENT_NAME=`$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | $wanted.metadata.name' $YAMLFILE`
  POD_NAME=""
else
  DEPLOYMENT_NAME=""
  POD_NAME=`$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | $wanted.metadata.name' $YAMLFILE`
fi
SERVICE_NAME=`$YQPATH '. | select(.kind == "Service") as $wanted | $wanted.metadata.name' $YAMLFILE`
IMAGE_NAME=`$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | $wanted.spec.containers[].image' $YAMLFILE`
PORT_NUMBER=`$YQPATH '. | select(.kind == "Service") as $wanted | $wanted.spec.ports[0].port' $YAMLFILE`
COMMAND_PATH=`$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | $wanted.spec.containers[].command[0]' $YAMLFILE`
COMMAND_DIR=`dirname $COMMAND_PATH`
NAMESPACE=`$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | $wanted.metadata.namespace' $YAMLFILE`
if test "$NAMESPACE" = "" -o "$NAMESPACE" = "null"; then
  NAMESPACE="default"
fi
echo deployment=$DEPLOYMENT_NAME, pod=$POD_NAME, namespace=$NAMESPACE, service=$SERVICE_NAME, image=$IMAGE_NAME, port=$PORT_NUMBER, command-path=$COMMAND_PATH, command-dir=$COMMAND_DIR

# Add kontain snapshot related properties to the deployment yaml file in $KONTAIN_YAMLFILE
# KONTAIN_YAMLFILE usually contains a working deployment that is snapshot unaware.
# $KONTAIN_YAMLFILE will be modified.
function addsnapshotpropstoyaml()
{

  # Add KM_MGTDIR env var to the container
  RESULT=`$YQPATH '(.spec.containers[].env[] | select(.name == "KM_MGTDIR"))' $KONTAIN_YAMLFILE`
  if test "$RESULT" == ""; then 
    # env var is not there, add it
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[] .env += [{"name": "KM_MGTDIR", "value": strenv(SNAPDIR_CONTAINER)}] | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  else
    # env is there, add to it
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].env[] | select(.name == "KM_MGTDIR") | .value = strenv(SNAPDIR_CONTAINER) | ($wanted, $notwanted) ' -i $KONTAIN_YAMLFILE
  fi

  # Add KM_MGTPIPE env var to allow old km's to work.
  # Old km can tolerate KM_MGTDIR and KM_MGTPIPE, new km will abort if KM_MGTPIPE and KM_MGTDIR are both specified.
  export SNAPPIPE_CONTAINER=$SNAPDIR_CONTAINER/kmpipe.$$
  RESULT=`$YQPATH '(.spec.containers[].env[] | select(.name == "KM_MGTPIPE"))' $KONTAIN_YAMLFILE`
  if test "$RESULT" == ""; then 
    # env var is not there, add it
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[] .env += [{"name": "KM_MGTPIPE", "value": strenv(SNAPPIPE_CONTAINER)}] | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  else
    # env is there, add to it
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].env[] | select(.name == "KM_MGTPIPE") | .value = strenv(SNAPPIPE_CONTAINER) | ($wanted, $notwanted) ' -i $KONTAIN_YAMLFILE
  fi


  # Add snapshot volume to the pod or deployment
  RESULT=`$YQPATH '(.spec.volumes[] | select(.name == "kontain-snap-volume"))' $KONTAIN_YAMLFILE`
  if test "$RESULT" == ""; then 
    # kontain volume definition is not there
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec .volumes += [{"name": "kontain-snap-volume", "hostPath": {"path": strenv(SNAPDIR_HOST), "type": "DirectoryOrCreate"}}] | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  else
    # kontain volume is there, make sure the path is correct
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.volumes[] | select(.name == "kontain-snap-volume") | .hostPath.path = strenv(SNAPDIR_HOST) | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  fi


  # Add snapshot volumeMounts to the container
  RESULT=`$YQPATH '(.spec.containers[].volumeMounts[] | select(.name == "kontain-snap-volume"))' $KONTAIN_YAMLFILE`
  if test "$RESULT" == ""; then
    # the kontain volumeMounts entry is not there, add it
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[] .volumeMounts += [{"name": "kontain-snap-volume", "mountPath": strenv(SNAPDIR_CONTAINER)}] | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  else
    # the kontain volumeMounts entry is there, be sure the mountPath is correct
    $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].volumeMounts[] | select(.name == "kontain-snap-volume") | .mountPath = strenv(SNAPDIR_CONTAINER) | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
  fi

  # Add "runtimeClassName: kontain" to the pod or deployment.
  $YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.runtimeClassName = "kontain" | ($wanted, $notwanted)' -i $KONTAIN_YAMLFILE
}

# Convert the deployment's yaml file into one that allows a snapshot
cp $YAMLFILE $KONTAIN_YAMLFILE
addsnapshotpropstoyaml

# Start the deployment and wait for it to be ready
kubectl apply -f $KONTAIN_YAMLFILE
sleep 5

# Verify that the deployment is operational
DWEBIP=`kubectl get -n $NAMESPACE -o template service/$SERVICE_NAME --template={{.spec.clusterIP}}`
curl $DWEBIP:$PORT_NUMBER >/dev/null

# Take the snapshot
# How do we do this once we are no longer running on "the" node in the kubernetes cluster?
# The kubectl exec cp should not be needed when an up to date kontain distribution is being
# installed in the kubersnottys cluster.
sudo $KMCLI_PATH -r -s $SNAPDIR_HOST/kmpipe.*
# Older versions of km don't understand the KM_MGTDIR env var, so the following command
# compensates for this and puts the snapshot into the KM_MGTDIR.
kubectl exec -n $NAMESPACE $POD_NAME -- /bin/cp kmsnap $SNAPDIR_CONTAINER

ls -l $SNAPDIR_HOST

# Delete the deployment we snapped
kubectl delete -f $KONTAIN_YAMLFILE

# Create a new container image to run the snapshot
# This needs to handle differing snapshot filenanes kmsnap vs kmsnap.XXX.NNN
# Build dockerfile
# Build container image
# Push the container to a remote repository
SNAPFILE=`basename $SNAPDIR_HOST/kmsnap*`
cat <<EOF >kmsnap.dockerfile
FROM $IMAGE_NAME
COPY $SNAPFILE /$COMMAND_DIR/kmsnap
EOF
export SNAP_COMMAND_PATH=/$COMMAND_DIR/kmsnap
export SNAP_IMAGE_NAME=$SNAPREPO/`basename $IMAGE_NAME`:latest
IMAGE_DIR=./image
mkdir -p $IMAGE_DIR
sudo cp $SNAPDIR_HOST/$SNAPFILE $IMAGE_DIR
sudo chown `id -u`:`id -g` $IMAGE_DIR/$SNAPFILE
chmod 755 $IMAGE_DIR/$SNAPFILE
docker build -t $SNAP_IMAGE_NAME -f kmsnap.dockerfile $IMAGE_DIR
#docker login ????
docker push $SNAP_IMAGE_NAME

# Massage the customer deployment file to run the new container image with the kontain runtime
# and and the snapshot.
# We need to add:
#   spec.runtimeClassName: kontain
#   spec.containers[x].image: $SNAPREPO/$IMAGE_NAME:latest
#   sprc.containers[x].command: [ "/where/kmsnap" ]
#   delete - spec.containers.args
# Snapshot does not accept arguments
cp $YAMLFILE $RUNSNAP_YAMLFILE
$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.runtimeClassName = "kontain" | ($wanted, $notwanted)' -i $RUNSNAP_YAMLFILE
$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].image = strenv(SNAP_IMAGE_NAME) | ($wanted, $notwanted)' -i $RUNSNAP_YAMLFILE
$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].command[0] = strenv(SNAP_COMMAND_PATH) | ($wanted, $notwanted)' -i $RUNSNAP_YAMLFILE
$YQPATH '. | select(.kind == strenv(YAMLKIND)) as $wanted | select(.kind != strenv(YAMLKIND)) as $notwanted | $wanted.spec.containers[].args = [] | ($wanted, $notwanted)' -i $RUNSNAP_YAMLFILE

# Start the deployment that runs the snapshot, wait for it to be active
kubectl apply -f $RUNSNAP_YAMLFILE
sleep 5

# Verify that the snapshot deployment works
DWEBIP=`kubectl get -n $NAMESPACE -o template service/$SERVICE_NAME --template={{.spec.clusterIP}}`
curl $DWEBIP:$PORT_NUMBER >/dev/null
echo curl says: $?

# Delete the deployment
kubectl delete -f $RUNSNAP_YAMLFILE

# Cleanup our mess
rm -fr $SNAPDIR_HOST
rm -fr image
