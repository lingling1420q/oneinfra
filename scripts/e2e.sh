#!/usr/bin/env bash

set -e

if [ -z "$CI" ]; then
    export PATH=${GOPATH}/bin:${PATH}
else
    export PATH=${PWD}/bin:${PATH}
fi

CLUSTER_CONF="${CLUSTER_CONF:-cluster.conf}"
CLUSTER_NAME="${CLUSTER_NAME:-cluster}"

mkdir -p ~/.kube

echo "Creating infrastructure"
oi-local-cluster cluster create > "${CLUSTER_CONF}"

echo "Hypervisor list"
docker ps -a

# Get all IP addresses from docker containers, we don't care being
# picky here. This is required because of how fake workers will
# connect to the infrastructure, read more on the
# `create-fake-worker.sh` script
APISERVER_EXTRA_SANS="$(docker ps -q | xargs docker inspect -f '{{ .NetworkSettings.IPAddress }}' | xargs -I{} echo "--apiserver-extra-sans {}" | paste -sd " " -)"

echo "Initializing the infrastructure"
cat "${CLUSTER_CONF}" | \
    oi cluster inject --name "${CLUSTER_NAME}" ${APISERVER_EXTRA_SANS} | \
    oi node inject --name controlplane --cluster "${CLUSTER_NAME}" --role controlplane | \
    oi node inject --name loadbalancer --cluster "${CLUSTER_NAME}" --role controlplane-ingress | \
    oi reconcile | \
    tee "${CLUSTER_CONF}" | \
    oi cluster kubeconfig --cluster "${CLUSTER_NAME}" > ~/.kube/config

# Tests

echo "Running tests"

set +e

RETRIES=1
MAX_RETRIES=5
while ! kubectl cluster-info &> /dev/null; do
    echo "API server not accessible; retrying..."
    if [ ${RETRIES} -eq ${MAX_RETRIES} ]; then
        exit 1
    fi
    ((RETRIES++))
    sleep 1
done

set -ex

kubectl cluster-info
kubectl version
