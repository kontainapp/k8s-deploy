KNATIVE_VERSION=1.8.0
# install serving 
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}/serving-core.yaml

kubectl wait --for=condition=Ready pods --all -n knative-serving

#install networking layer
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v${KNATIVE_VERSION}/kourier.yaml
# kubectl create namespace kourier-system
# kubectl apply -f kourier-k3s.yaml
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'


kubectl wait --for=condition=Ready pods --all -n knative-serving

#configure DNS (Magic DNS)
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v${KNATIVE_VERSION}/serving-default-domain.yaml
kubectl patch configmap/config-domain \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"127.0.0.1.sslip.io":""}}'

kubectl rollout status deployment domain-mapping -n knative-serving

# enable runtime 
kubectl patch configmap/config-features -n knative-serving --type merge -p '{"data":{"kubernetes.podspec-runtimeclassname": "enabled"}}'

# setup secret 
kubectl create secret docker-registry cntr-registry-secret --from-file=.dockerconfigjson=/home/leka/.docker/config.json 
kubectl patch serviceaccount default -p "{\"imagePullSecrets\": [{\"name\": \"cntr-registry-secret\"}]}"
kubectl patch cm config-deployment --patch '{"data":{"registriesSkippingTagResolving":"kontaintests.azurecr.io"}}' -n knative-serving
