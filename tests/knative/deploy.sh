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