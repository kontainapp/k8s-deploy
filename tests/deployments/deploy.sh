#!/bin/bash

start=$1
count=$2

for (( i=$start; i<=$count; i++ ))
do
   yaml_str="
apiVersion: v1
kind: Pod
metadata:
  name: sb-$i-$$
  labels:
    app.kubernetes.io/name: snap-test-$i
    app: faas
spec:
    runtimeClassName: kontain
    containers:
    - name: sb-pod
      image: kontaintests.azurecr.io/sb-test-snap-fc:latest
      imagePullPolicy: IfNotPresent
      env:
      - name: SNAP_LISTEN_PORT
        value: \"i4 8080\"
      - name: SNAP_LISTEN_TIMEOUT
        value: \"1000\"
      ports:
      - containerPort: 8080
        name: http-web-svc
    #   readinessProbe:
    #     httpGet:
    #         path: /
    #         port: 8080
    #     initialDelaySeconds: 15
    #     periodSeconds: 30
    #     failureThreshold: 1        
    #   livenessProbe:
    #     httpGet:
    #         path: /
    #         port: 8080
    #     initialDelaySeconds: 15
    #     periodSeconds: 30
    #     failureThreshold: 1        
---
apiVersion: v1
kind: Service
metadata:
  name: sb-$i-$$
spec:
  selector:
    app.kubernetes.io/name: snap-test-$i
  ports:
  - name: sb-service-port
    protocol: TCP
    port: 8080
    targetPort: http-web-svc
" 
    echo "$yaml_str" > dpl-$i.yaml
    kubectl apply -f dpl-$i.yaml
    rm dpl-$i.yaml
done
