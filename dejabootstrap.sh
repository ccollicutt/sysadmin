#!/bin/bash

SEQ=2
HOSTPREFIX=test
K="/home/curtis/working/kicker/kicker.py"
CENTOS_SCRIPTS_LOCATION="/home/curtis/working/sysadmin/"
CONF="$CENTOS_SCRIPTS_LOCATION/centos.conf"
DOMAIN="uatest.ca"
KVM_HOST="kvm.$DOMAIN"
XEN_HOST="xen.$DOMAIN"
KS_HOST="repos.$DOMAIN:/var/lib/kickstarts"

# Load conf
if [ -f $CONF ]; then
	. $CONF
else
	echo "Can't find $CONF"
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
		

	$K -i $IP -g $GATEWAY -d $DNS -n $NETMASK -m domU_$DOM0_HYPERVISOR -h $SERVER.$DOMAIN > /tmp/$SERVER.ks
	# Copy the kickstarts to the kickstart http server
	scp /tmp/$SERVER.ks root@$KS_HOST

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
	# If they are running they are getting killed and undefined
	ssh root@$DOM0_HOST virsh destroy $SERVER
	ssh root@$DOM0_HOST virsh undefine $SERVER
	
	ssh root@$DOM0_HOST /usr/local/sbin/centos.sh $SERVER
	#exit 1
	
done

