### 2020/07 BuRnCycL

Setting up Cert-manager + Letsencrypt with a dummy echo web application.


References:
- https://dev.to/chrisme/setting-up-nginx-ingress-w-automatically-generated-letsencrypt-certificates-on-kubernetes-4f1k
- https://www.digitalocean.com/community/tutorials/how-to-set-up-an-nginx-ingress-with-cert-manager-on-digitalocean-kubernetes
- https://medium.com/@balkaran.brar/configure-letsencrypt-and-cert-manager-with-kubernetes-3156981960d9


### Add Helm repos for Nginx and cert-manager
```
helm repo add nginx-stable https://helm.nginx.com/stable 
helm repo add jetstack https://charts.jetstack.io
helm repo update
```
### Helm Install Nginx Ingress & Cert-manager 
Reference: 
* https://hub.helm.sh/charts/jetstack/cert-manager
* https://github.com/jetstack/cert-manager/issues/2540

List versions
```
helm search repo -l nginx-stable/nginx-ingress 
helm search repo -l jetstack/cert-manager
```

```
helm install fyzix nginx-stable/nginx-ingress 
kc apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.15.2/cert-manager.crds.yaml
kc create ns cert-manager
helm install cert-manager --namespace cert-manager jetstack/cert-manager # This failed on fresh install
helm template cert-manager jetstack/cert-manager --namespace cert-manager | kubectl apply -f -
```

### Echo Deployment

I setup port forwardng for both 80 & 443 to my ingress at the External-IP
```
burncycl@tolin:~/xero/euclid/roles/kubectl$ kc get svc
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
fyzix-nginx-ingress   LoadBalancer   10.110.29.219    10.9.9.50     80:31963/TCP,443:30209/TCP   17d
```

Test plain port 80 echoer
```
kc apply -f app-echo1.yml
kc apply -f app-echo2.yml
kc apply -f echo_ingress_plain80.yml
```

Should be able to browse to http://echo1.fyzix.net and http://echo2.fyzix.net with both returning: 

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

Now we'll utilize these cert issuers. In the project root directory
```
kc apply -f staging-echo_ingress.yml
```
Note the annotations which associate with the cluster cert issuer.

Verify
```
kubectl describe certificate le-staging
```

##### Prod
```
kc apply -f prod-echo_ingress.yml
```

Verify
```
kubectl describe certificate le-prod
```

Should see Generated new private key and Created new CertificateRequest resource `letsencrypt-env-XXXX`


### Issues
Reference:
* https://github.com/jetstack/cert-manager/issues/2712
