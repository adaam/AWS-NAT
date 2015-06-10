#!/bin/bash

#----------------------------------------------------------
#  AWS HA NAT Script
#
#  Desc: This script will config itself EC2 instance as
#        NAT at where AZ the instance located
#  Author: adaam
#  Date: 2015/06/09
#  version: 0.3
#  Note: Subnet should has Tag with Key=NeedNAT,Value=1
#        then script associate subnet to own route table
#        Security Group for NAT should allow OWN_VPC_CIDR all traffic
#  Dependency: jq, AWS CLI
#----------------------------------------------------------


function init_all_variable() {
	OWN_MAC=$(curl -s http://169.254.169.254/latest/meta-data/mac)
	OWN_VPC_ID=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$OWN_MAC/vpc-id)
	OWN_VPC_CIDR=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$OWN_MAC/vpc-ipv4-cidr-block)
	OWN_AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
	OWN_REGION=${OWN_AZ%?}
	#CHANGE_RT_ASS_SUBNET=$()
	INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

	ROUTE_TABLE_NAME="NAT_${OWN_REGION}"
	ROUTE_TABLE_ID=$(aws --region ${OWN_REGION} ec2 describe-route-tables | jq -r '.RouteTables[] | select(.Tags[].Value == "'NAT_${OWN_AZ}'") | .RouteTableId')
}

function check_create_table_and_route(){
	# Check table id, if null, then create
	if [ -z ${ROUTE_TABLE_ID} ];then
		# Create route table
		ROUTE_TABLE_ID=$(aws --region ${OWN_REGION} ec2 create-route-table --vpc-id ${OWN_VPC_ID} | jq -r .RouteTable.RouteTableId)
		# Set route table name
		aws --region ${OWN_REGION} ec2 create-tags --resources ${ROUTE_TABLE_ID} --tags Key=Name,Value=NAT_${OWN_AZ}
		# Set route to route table
		aws ec2 create-route \
			--region ${OWN_REGION} \
			--route-table-id "${ROUTE_TABLE_ID}" \
			--destination-cidr-block 0.0.0.0/0 \
			--instance-id "${INSTANCE_ID}"
	else
		# Set route at route table
		aws ec2 replace-route \
			--region ${OWN_REGION} \
			--route-table-id "${ROUTE_TABLE_ID}" \
			--destination-cidr-block 0.0.0.0/0 \
			--instance-id "${INSTANCE_ID}" || \
		aws ec2 create-route \
			--region ${OWN_REGION} \
			--route-table-id "${ROUTE_TABLE_ID}" \
			--destination-cidr-block 0.0.0.0/0 \
			--instance-id "${INSTANCE_ID}"
	fi
}
function disable_instance_srcdes_check() {
	# disable EC2 dource destnation check function
	aws ec2 modify-instance-attribute \
		--region ${OWN_REGION} \
		--instance-id "${INSTANCE_ID}" \
		--no-source-dest-check
}

function replcae_route_table_assocation()  {

	MAY_CHANGE_SUBNET_ID=($(aws --region ${OWN_REGION} ec2 describe-subnets |jq -r '.Subnets[] | select(.AvailabilityZone == "'${OWN_AZ}'") |select(.Tags[].Key == "NeedNAT")|select(.Tags[].Value == "1")|.SubnetId'))
	NO_CHANGE_SUBNET_ID=($(aws --region ${OWN_REGION} ec2 describe-route-tables|jq -r '.RouteTables[] |select(.RouteTableId == "'${ROUTE_TABLE_ID}'")|.Associations[].SubnetId'))

	if [ ${#NO_CHANGE_SUBNET_ID[@]} -gt 0 ];then
		for del in ${NO_CHANGE_SUBNET_ID[@]};do
			NEED_CHANGE_SUBNET_ID=(${MAY_CHANGE_SUBNET_ID[@]/${del}})
		done
	else
		NEED_CHANGE_SUBNET_ID=(${MAY_CHANGE_SUBNET_ID[@]})
	fi
	AssociationId=()
	if [ ${#NEED_CHANGE_SUBNET_ID[@]} -gt 0 ];then
		for net_id in ${NEED_CHANGE_SUBNET_ID[@]}; do
			AssociationId+=($(aws --region ${OWN_REGION} ec2 describe-route-tables|jq -r '.RouteTables[] |select(.Associations[].SubnetId == "'${net_id}'") | .Associations[] |select(.SubnetId == "'${net_id}'") | .RouteTableAssociationId'))
		done
		for ass_id in ${AssociationId[@]};do
			result=$(aws --region ${OWN_REGION} ec2 replace-route-table-association --association-id ${ass_id} --route-table-id ${ROUTE_TABLE_ID}| jq -r .NewAssociationId)
		done
	fi

}

function enable_ip_forward() {
	echo "1" > /proc/sys/net/ipv4/ip_forward
}
function iptables_nat(){
	iptables -t nat -A POSTROUTING -s ${OWN_VPC_CIDR} -j MASQUERADE
}
function main(){
	init_all_variable
	enable_ip_forward
	disable_instance_srcdes_check
	iptables_nat
	check_create_table_and_route
	replcae_route_table_assocation
}

main
