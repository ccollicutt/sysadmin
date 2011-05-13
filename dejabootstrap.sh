#!/bin/bash

# Seq is essentially the number of vms to create
SEQ=2
HOSTPREFIX=test
# Kicker is required to create the kickstarts
K="/home/curtis/working/kicker/kicker.py"
# centos.sh is the script that actually creates the vms using virt-install
CENTOS_SCRIPTS_LOCATION="/home/curtis/working/sysadmin/"
CONF="$CENTOS_SCRIPTS_LOCATION/centos.conf"
DOMAIN="uatest.ca"
# We are building half the vms on kvm and the other half on xen
KVM_HOST="kvm.$DOMAIN"
XEN_HOST="xen.$DOMAIN"
# Where to put the resulting kickstart files to be made available to centos.sh 
KS_HOST="repos.$DOMAIN:/var/lib/kickstarts"

# Load conf
if [ -f $CONF ]; then
	. $CONF
else
	echo "Can't find $CONF"
	exit 1
fi

echo "This script going to destroy the following virtual machines and their logical volumes will be *overwritten*! Are you sure you want to do this?"

for s in $(seq 1 $SEQ); do
	SERVER=$HOSTPREFIX$s
	echo "$SERVER with a logical volume of $POOL/$SERVER"
done
echo -n "Type \"no\" or CTRL-C, otherwise any other answer will continue this process: "
read answer

if [ "$answer" == "no" ]; then
	echo "Exiting..."
	exit 1
fi

# Run through each server
for s in $(seq 1 $SEQ); do
	
	SERVER=$HOSTPREFIX$s

	# Does dns entry exist b/c we need it to set ip in kicker
	if ! host $SERVER > /dev/null; then
		echo "$SERVER does not resolve, check dns entry"
		exit 1
	fi

	IP=`host $SERVER | cut -f 4 -d " "` 

	# We have 2 dom0s, so even servers put on one and
	# odd put on the other. :)
	MOD=`expr $s % 2`

	if [ "$MOD" == "0" ]; then
		DOM0_HYPERVISOR="kvm"
		DOM0_HOST=$KVM_HOST
	else
		DOM0_HYPERVISOR="xen"
		DOM0_HOST=$XEN_HOST
	fi

	# Use kicker to create kickstarts for each system
	$K -i $IP -g $GATEWAY -d $DNS -n $NETMASK -m domU_$DOM0_HYPERVISOR -h $SERVER.$DOMAIN > /tmp/$SERVER.ks

	# Copy the kickstarts to the kickstart http server
	scp /tmp/$SERVER.ks root@$KS_HOST

	# Create the logical volume if it doesn't exist, warn if it does
	if ssh root@$DOM0_HOST ls $POOL/$SERVER ; then
		echo "$POOL/$SERVER already exists"
		#exit 1
	else
		# Create the logial volume
		ssh root@$DOM0_HOST lvcreate -n $SERVER -L20.0G $POOL
	fi	

	# Copy the centos.sh and centos.conf files to the servers so that we are working with the smae files
	# This doesn't need to happen $s times though...yeesh
	scp $CENTOS_SCRIPTS_LOCATION/centos.* root@$DOM0_HOST:/usr/local/sbin

	# If the domains are running alreayd they are getting killed and undefined and written over 
	ssh root@$DOM0_HOST virsh destroy $SERVER
	ssh root@$DOM0_HOST virsh undefine $SERVER
	
	ssh root@$DOM0_HOST /usr/local/sbin/centos.sh $SERVER
	#exit 1
	
done
