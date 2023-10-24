
#****************************************************************Verify spire installation and health******************************************
kubectl get pods -n cilium-spire

#Run a health check as well
kubectl exec -n cilium-spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server healthcheck

#Verify the list of attested agents:
kubectl exec -n cilium-spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server agent list

#Verify SPIFFE Identities
# Verify that the Cilium agent and operator have Identities on the SPIRE server:
kubectl exec -n cilium-spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show -parentID spiffe://spiffe.cilium/ns/cilium-spire/sa/spire-agent

#***************************************************************************************************************************************************

#**************************************************Deploy test apps**********************************************************************************

#Create "server pod"
kubectl create deployment server --image=grostami/spring-boot-app:3.1.0
#Create a service for it
kubectl expose deployment server --port=8080 --target-port=8080 --type=NodePort
kubectl get service server
#Get its ClusterIP address
export CLUSTERIP=$(kubectl get service server  -o jsonpath='{ .spec.clusterIP }')
echo $CLUSTERIP
curl http://$CLUSTERIP:8080/health


#******Execute dynamic "cilium-policy-no-mutual-auth.yaml"

kubectl create deployment client --image=nginx
kubectl exec -it deployment/client -- curl http://$CLUSTERIP:8080/computer
kubectl exec -it deployment/client -- curl http://$CLUSTERIP:8080/health

# Next, verify that the server Pod has an Identity registered with the SPIRE server.
# To do this, you must first construct the Pod’s SPIFFE ID. The SPIFFE ID for a workload is based on the spiffe://spiffe.cilium/identity/$IDENTITY_ID format, where $IDENTITY_ID is a workload’s Cilium Identity.
# Grab the Cilium Identity for the server Pod;
IDENTITY_ID=$(kubectl get CiliumEndpoint  -l app=server -o=jsonpath='{.items[0].status.identity.id}')
  
kubectl exec -n cilium-spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show -spiffeID spiffe://spiffe.cilium/identity/$IDENTITY_ID
# You can see the that the cilium-operator was listed in the Parent ID. That is because the Cilium operator creates SPIRE entries for Cilium Identities as they are created.

# To get all registered entries, execute the following command:
kubectl exec -n cilium-spire spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show -selector cilium:mutual-auth

#There are as many entries as there are identities. Verify that these match by running the command:
kubectl get ciliumidentities
#*************************************************************************************************************************************

#*******************************************************Mutual auth*******************************************************************************************

#******Execute dynamic "cilium-policy-mutual-auth.yaml"


cilium config set debug true
    cilium config set debug false

#Verify cilium agent pods have strated
kubectl -n kube-system get pods -l k8s-app=cilium 

#Verify (should get same results)
kubectl exec -it deployment/client -- curl http://$CLUSTERIP:8080/computer
kubectl exec -it deployment/client -- curl http://$CLUSTERIP:8080/health

#Determine which agent is running on the same node as server pod
SERVER_NODE=$(kubectl get  pod -o wide  | grep server | awk '{ print $7}')
echo $SERVER_NODE
SERVER_AGENT=$( kubectl -n kube-system get pods -l k8s-app=cilium -o wide |  grep $SERVER_NODE | awk '{ print $1}')
echo $SERVER_AGENT

kubectl -n kube-system -c cilium-agent logs $SERVER_AGENT --timestamps=true | grep "Policy is requiring authentication\|Validating Server SNI\|Validated certificate\|Successfully authenticated"


#Clean up
kubectl delete deployment server
kubectl delete service server
kubectl delete deployment client
kubectl delete CiliumNetworkPolicy mutual-auth-sample