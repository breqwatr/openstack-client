FROM ubuntu:bionic

ARG RELEASE

RUN mkdir -p /var/repos/ \
 && apt-get update \
 && apt-get install -y \
    git \
    python-pip \
 && git clone \
    --single-branch \
    --branch stable/$RELEASE \
    https://github.com/openstack/python-openstackclient.git \
    /var/repos/python-openstackclient \
 && pip install /var/repos/python-openstackclient \
 && openstack --version 2>> /VERSIONS \
 && echo "nova $(nova --version 2>&1)" >> /VERSIONS \
 && echo "cinder $(cinder --version 2>&1)" >> /VERSIONS \
 && git clone \
    --single-branch \
    --branch stable/$RELEASE \
    https://github.com/openstack/python-neutronclient.git \
    /var/repos/python-neutronclient \
 && pip install /var/repos/python-neutronclient \
 && echo "neutron $(neutron --version 2>&1 | grep -v depr)" >> /VERSIONS \
 && cat /VERSIONS
