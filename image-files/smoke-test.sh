#!/bin/bash

# Smoke-test script: Run some basic setup for OpenStack to make sure everything is ok


####################
# Input validation #
####################


for envvar in \
		VOLUME_TYPE VOLUME_BACKEND SA_USER SA_PASSWORD SA_PROJECT NET_TYPE NET_NAME DNS \
    CIDR GATEWAY POOL_START POOL_END IMAGE_NAME FLAVOR_NAME RAM CPU DISK; do
	if [[ "${!envvar}" == "" ]]; then
		echo "ERROR: env var $envvar must be set"
		exit 3
	fi
done

if [[ "$NET_TYPE" != "VLAN" && "$NET_TYPE" != "FLAT" ]]; then
  echo "ERROR: NET_TYPE must be VLAN or FLAT"
  exit 4
fi

if [[ "$NET_TYPE" == "VLAN" && "$VLAN_ID" == "" ]]; then
  echo "ERROR: VLAN_ID must be set when NET_TYPE=VLAN"
  exit 5
fi

if [[ ! -f /image.qcow2 ]]; then
  echo "ERROR: $IMAGE_NAME qcow2 file must be mounted to /image.qcow2"
  exit 6
fi

###########################
# Cloud environment setup #
###########################

# This script should try to be idempotent

# Define the storage type
# Configure the storage type
if [[ ! $(openstack volume type list | grep $VOLUME_TYPE) ]]; then
  echo "creating cinder volume type $VOLUME_TYPE"
  openstack volume type create --public \
    --property volume_backend_name="$VOLUME_BACKEND" $VOLUME_TYPE
fi

# Create the user
if [[ ! $(openstack user list | grep $SA_USER) ]]; then
  echo "Creating user $SA_USER"
  openstack user create --domain default --password $SA_PASSWORD arcusadmin
else
  echo "... user $SA_USER exists"
fi

# create the project
if [[ ! $(openstack project list | grep $SA_PROJECT) ]]; then
	echo "creating project $SA_PROJECT"
  openstack project create $SA_PROJECT
else
	echo "... project $SA_PROJECT exists"
fi

# assign admin roles to the service-account SA_USE
user_id=$(openstack user show $SA_USER -c id -f value)
admin_role_id=$(openstack role show admin -c id -f value)
if [[ ! $(openstack role assignment  list | grep $admin_role_id | grep $user_id) ]]; then
  echo "assinging admin roles to $SA_USER"
  openstack role add --project admin --user $SA_USER admin
  openstack role add --project $SA_PROJECT --user $SA_USER _member_
  openstack role add --domain default --user $SA_USER admin
else
  echo "... admin role is assigned"
fi


# Create an external network
if [[ ! $(openstack network list | grep $NET_NAME) ]]; then
  echo "creating $NET_TYPE network $NET_NAME"
  if [[ "$NET_TYPE" == "VLAN" ]]; then
		openstack network create \
			--share \
			--external \
			--provider-physical-network physnet1 \
			--provider-network-type vlan \
			--provider-segment $VLAN_ID \
			$NET_NAME
  else
    # NET_TYPE == FLAT
		openstack network create \
			--share \
			--external \
			--provider-physical-network physnet1 \
			--provider-network-type flat \
			$NET_NAME
  fi
else
  echo "... network $NET_NAME exists"
fi


# Create a subnet
SUBNET_NAME="$NET_NAME-subnet"
if [[ ! $(openstack subnet list | grep $SUBNET_NAME) ]]; then
  echo "creating subnet $SUBNET_NAME"
  openstack subnet create \
    --allocation-pool start=$POOL_START,end=$POOL_END \
    --no-dhcp \
    --dns-nameserver $DNS \
    --gateway $GATEWAY \
    --network $NET_NAME \
    --subnet-range $CIDR \
    $SUBNET_NAME
else
	echo "... subnet $SUBNET_NAME exists"
fi


# Create a flavor
if [[ ! $(openstack flavor list | grep $FLAVOR_NAME) ]]; then
  echo "creating flavor $FLAVOR_NAME"
  openstack flavor create tiny --id auto --ram $RAM  --disk $DISK --vcpus $CPU
else
  echo "... $FLAVOR_NAME flavor exists"
fi


# Upload the image
if [[ ! $(openstack image list | grep $IMAGE_NAME) ]]; then
  echo "Creating the image $IMAGE_NAME"
  openstack image create \
    --container-format bare \
    --disk-format qcow2 \
    --file /image.qcow2 \
    --property display_name=$IMAGE_NAME \
    --property architecture=x86_64 \
    --property os_distro=linux-server \
    --property ssh_required="false" \
    --property cost="0" \
    $IMAGE_NAME
else
  echo "... $IMAGE_NAME image exists"
fi

