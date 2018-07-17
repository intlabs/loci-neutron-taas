#!/bin/bash
set -ex
OPENSTACK_VERSION="stable/ocata"
IMAGE_TAG="${OPENSTACK_VERSION#*/}"

sudo docker run -d \
  --name docker-in-docker \
  --privileged=true \
  --net=host \
  -v /var/lib/docker \
  -v ${HOME}/.docker/config.json:/root/.docker/config.json:ro\
  docker.io/docker:17.07.0-dind \
  dockerd \
    --pidfile=/var/run/docker.pid \
    --host=unix:///var/run/docker.sock \
    --storage-driver=overlay2
sudo docker exec docker-in-docker apk update
sudo docker exec docker-in-docker apk add git

sudo docker exec docker-in-docker docker build --force-rm --pull --no-cache \
    https://git.openstack.org/openstack/loci.git \
    --build-arg PROJECT=neutron \
    --build-arg FROM=docker.io/ubuntu:18.04 \
    --build-arg PROJECT_REF=${OPENSTACK_VERSION} \
    --build-arg PROFILES="neutron linuxbridge openvswitch" \
    --build-arg PIP_PACKAGES="pycrypto" \
    --build-arg DIST_PACKAGES="ethtool lshw" \
    --build-arg WHEELS=openstackhelm/requirements:${IMAGE_TAG} \
    --tag docker.io/port/neutron:${IMAGE_TAG}-sriov-1804
sudo docker exec docker-in-docker docker push docker.io/port/neutron:${IMAGE_TAG}-sriov-1804

tee > /tmp/Dockerfile.neutron-taas <<EOF
FROM docker.io/port/neutron:${IMAGE_TAG}-sriov-1804
RUN set -ex ;\
    apt-get update ;\
    apt-get upgrade -y ;\
    apt-get install -y --no-install-recommends \
        git \
        python \
        virtualenv ;\
    . /var/lib/openstack/bin/activate ;\
    git clone https://github.com/openstack/tap-as-a-service.git /opt/tap-as-a-service ;\
    cd /opt/tap-as-a-service/ ;\
    pip install --editable .
EOF


NEUTRON_TAAS_DOCKERFILE=$(base64 -w0 /tmp/Dockerfile.neutron-taas)
sudo docker exec docker-in-docker sh -c "echo $NEUTRON_TAAS_DOCKERFILE | base64 -d > /tmp/Dockerfile.neutron-taas"
sudo docker exec docker-in-docker docker build --file /tmp/Dockerfile.neutron-taas /tmp --tag docker.io/port/neutron:${IMAGE_TAG}-sriov-taas-1804
sudo docker exec docker-in-docker docker push docker.io/port/neutron:${IMAGE_TAG}-sriov-taas-1804
