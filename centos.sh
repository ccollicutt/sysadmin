#!/bin/bash

CONF_FILE="./centos.conf"

if [ ! -f $CONF_FILE ]; then
	echo "Configuration file $CONF_FILE does not exist."
	exit 1
else
	# Load conf file
	. $CONF_FILE
fi

# Must supply VMNAME to continue
if [ -z "$1" ]; then
        echo "Usage: $0 vmname"
        exit 1
else
	VMNAME=$1
	KICKSTART=$KICKSTART/$VMNAME.ks
fi

if [ -z "$DNS" -o -z "$GATEWAY" -o -z "$NETMASK" ]; then
	echo "One of the vars DNS, GATEWAY, or NETMASK was empty"
	exit 1
fi

# Much of this is based on there being a fqdn and IP associated with $VMNAME
if ! host $VMNAME > /dev/null; then
	echo "host $VMNAME did not return ok, is there a fqdn for $VMNAME?"
	exit 1
else
	# We're good, get the IP for that fqdn
	IP=`host $VMNAME | cut -f 4 -d " "`
fi

# Is the IP already in use?
if ping -c 1 -w 1 $IP > /dev/null; then
	echo "$IP seems to be up, is there a host with this IP already?"
	exit 1
fi

# Make sure the logical volume is there
if [ ! -e $POOL/$VMNAME ]; then
        echo "$POOL/$VMNAME does not exist, please create it."
        exit 1
fi

# Try to get the kickstart just to make sure it's been created
if ! wget $KICKSTART -O /tmp/ks.tmp; then
	echo "Could not download $KICKSTART, is it there?"
	exit 1
else
	# We got the ks so delete it
	# There's prob an option in wget not to download...
	rm /tmp/ks.tmp
fi 

if which xm > /dev/null; then
	# it's xen!
	HYPERVISOR="--paravirt"
	CONSOLE="xvc0"
	BRIDGE=$XEN_BRIDGE
else
	# it's kvm! prob.
	HYPERVISOR="-v"
	CONSOLE="ttyS0,115200"
	BRIDGE=$KVM_BRIDGE
fi

virt-install --accelerate --nographics  \
 $HYPERVISOR \
 --name $VMNAME --vcpus=1 --ram 512 \
 --os-type=linux --network bridge:$BRIDGE \
 --file=$POOL/$VMNAME  \
 --extra="console=$CONSOLE ks=$KICKSTART dns=$DNS ip=$IP netmask=$NETMASK gateway=$GATEWAY" \
 --location=$REPO_URL
