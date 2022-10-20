SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo $SCRIPT_DIR
kubectl apply -f $SCRIPT_DIR/test_app.yaml
kubectl expose deployment hello-world --type=LoadBalancer --name=hello-world-service