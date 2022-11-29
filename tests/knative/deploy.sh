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

start=$1
count=$2

for (( i=$start; i<=$count; i++ ))
do
   yaml_str="
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: sp-svc-$i
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/initial-scale: \"1\"
        autoscaling.knative.dev/min-scale: \"1\"
    spec:
      runtimeClassName: kontain
      containers:
        - image: kontaintests.azurecr.io/sb-test-snap-fc:latest
          env:
            - name: SNAP_LISTEN_PORT
              value: \"i4 8080\"
            - name: SNAP_LISTEN_TIMEOUT
              value: \"1000\"
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /greeting
            initialDelaySeconds: 30
            periodSeconds: 30              
          livenessProbe:
            httpGet:
              path: /greeting
            initialDelaySeconds: 30
            periodSeconds: 30            
      imagePullSecrets:
        - name: cntr-registry-secret
" 
    echo "$yaml_str" > svc-$i.yaml
    kubectl apply -f svc-$i.yaml
done