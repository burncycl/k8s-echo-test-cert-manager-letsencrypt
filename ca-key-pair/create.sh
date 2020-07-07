#!/bin/bash

kubectl create secret tls tls-secret \
   --cert=ca.crt \
   --key=ca.key \
   --namespace=default
