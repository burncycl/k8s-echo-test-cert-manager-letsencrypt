### 2020/07 BuRnCycL

Setting up Cert-manager + Letsencrypt with a dummy echo web application.


References:
- https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes
- https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes
- https://medium.com/@balkaran.brar/configure-letsencrypt-and-cert-manager-with-kubernetes-3156981960d9
- https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-on-digitalocean-kubernetes-using-helm

### Potential Gotchya
I run my K8s cluster behind my home router/firewall. This router/firewall performs port-forwarding to the internal ingress 10.9.9.50.
The cert-manager health check API will not be able to hit the external endpoint to verify connectivity.
Thus, you have to perform some DNS trickery or Firewall trickery (using Iptables).

By using my internal DNS server, I can point echo1.fyzix.net and echo2.fyzix.net to the internal
IP address 10.9.9.50 where my Nginx Ingress is hosted. This will faclitate health checks passing. See also Troubleshooting section.

Note: This ended up having issue with helm chart installation of Nginx Ingress Controller, which I believe was due to externalTrafficPolicy setting (local vs cluster - see below Troubleshooting section).

To solve this, I pivoted to IPtables solution.

IPTables rules
```
EXTNET=`ifconfig ppp0 | grep "inet " | awk -F'[: ]+' '{ print $3 }'` # Primary IP Address
# eth1 - Internal Network - LAN 1
INTNET1="10.9.9.0/24"

# Expose internal network to via the external ip
INGRESS="10.9.9.50"
iptables -t nat -A PREROUTING -d ${EXTNET}/32 -p tcp -m multiport --dports 80,443 -j DNAT --to-destination $INGRESS
iptables -t nat -A POSTROUTING -s $INTNET1 -o ppp0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s $INTNET1 -d ${INGRESS}/32 -p tcp -m multiport --dports 80,443 -j MASQUERADE
```

### Add Helm repos for Nginx and cert-manager
```
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Helm Install Nginx Ingress & Cert-manager
Reference:
* https://hub.helm.sh/charts/jetstack/cert-manager

List versions
```
helm search repo -l nginx-stable/nginx-ingress
helm search repo -l jetstack/cert-manager
```
Can use `--version` argument below to specify a specific version of the above software (if needed).

*Install Nginx Ingress Controller*
```
helm install fyzix nginx-stable/nginx-ingress --set controller.service.externalTrafficPolicy=Cluster --set controller.service.loadBalancerIP=10.9.9.50
```

*Install Cert-manager*

Create Namespace and Helm Install cert-manager with CRDs 
```
kc create ns cert-manager
helm install cert-manager --namespace cert-manager jetstack/cert-manager --set installCRDs=true
```

### Echo Deployment (dummy app)

I setup port forwardng for both 80 & 443 on my router/firewall to my Internal Ingress Controller at the EXTERNAL-IP.

Fetch EXTERNAL-IP
```
kc get svc
```

Output
```
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
fyzix-nginx-ingress   LoadBalancer   10.110.29.219    10.9.9.50     80:31963/TCP,443:30209/TCP   17d
```

Fire up the apps and Test plain port 80 echoer
```
kc apply -f app-echo1.yml
kc apply -f app-echo2.yml
kc apply -f echo_ingress_plain80.yml
```

Should be able to browse to http://echo1.fyzix.net and http://echo2.fyzix.net (non-https) with both returning:

```
echoX Fyzix
```

#### Test Self-signed certificate issuer
```
kc apply -f test-self-signed.yml
```

Verify
```
kc describe certificate -n cert-manager-test
```

Should see Generated a new private key and sucessfully issued `selfsigned-cert-XXXXXXXX`

Can delete with
```
kc delete -f test-self-signed.yml
```

#### Create Staging & Prod certificate issuer

Create the Issuers
```
kc create -f staging_issuer.yml
kc create -f prod_issuer.yml
```

Verify
```
kc get clusterissuer -n cert-manager
```

Output
```
NAME                  READY   AGE
letsencrypt-prod      True    61s
letsencrypt-staging   True    64s
```

##### Staging

Testing can be facilitated using staging issuer. This keeps us from being rate limited by LetsEncrypt for
production level certs.

```
kc apply -f staging-echo_ingress.yml
```
Note the annotations which associate with the cluster cert issuer.

Verify
```
kubectl describe certificate le-staging
```

##### Prod

Be careful. LetsEncrypt rate limit applies to this deployment.
```
kc apply -f prod-echo_ingress.yml
```

Verify
```
kubectl describe certificate le-prod
```

Should see Generated new private key and Created new CertificateRequest resource `letsencrypt-env-XXXX`


### Troubleshooting

Note: When in doubt, use `decribe` on resource.

Surface information about certificates
```
kc get certificates
kc describe certificates le-prod
```

Troubleshooting Cert-Manager
```
kc get all -n cert-manager
```

Get the pod name e.g.
```
NAME                                           READY   STATUS    RESTARTS   AGE
pod/cert-manager-85db5c4c87-dql8j              1/1     Running   0          3h45m
```

View the logs using the Pod name
```
kubectl logs -f cert-manager-85db5c4c87-dql8j -n cert-manager
```

Should give detailed output to understand what is happening with Cert-Manager

### Issues
Reference:
* https://github.com/jetstack/cert-manager/issues/863
* https://github.com/jetstack/cert-manager/issues/2712
* https://github.com/jetstack/cert-manager/issues/2759

To Diagnose
```
kc get svc fyzix-nginx-ingress -o yaml
```

This can be handled with `--set controller.service.externalTrafficPolicy=Cluster` during Helm Installation of Nginx Ingress Controller.
```
# Modify from
externalTrafficPolicy: Local
# To
externalTrafficPolicy: Cluster
```

* https://github.com/jetstack/cert-manager/issues/2540

You might get the following error. This is indictive of a previous non-helm installation or the like. To resolve, delete the various CRDs and ClustRoles
```
Error: rendered manifests contain a resource that already exists. Unable to continue with install: ClusterRole "cert-manager-cainjector" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "cert-manager"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "cert-manager"
```

Output the template yaml, and run a delete
```
helm template cert-manager jetstack/cert-manager --namespace cert-manager --set installCRDs=true > output.yml
kc delete -f output.yml
rm output.yml
```

An additional solution for the failure
```
helm template cert-manager jetstack/cert-manager --namespace cert-manager | kubectl apply -f -
```
