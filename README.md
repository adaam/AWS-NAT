# AWS-NAT
This reposity is create for AWS HA-NAT use.

Now NAT step like below:
1. Give enough permission to your NAT EC2 instance
2. Tag your subnet with Key=NeedNAT, Value=1
3. Download jq at http://stedolan.github.io/jq/download/linux64/jq , chmod +x jq, cp jq /usr/bin
4. Download NAT.sh to your NAT instance
5. Run NAT.sh at your EC2, now your instance at same AZ as NAT instance should can access internet
 
Note: I not design cross-zone NAT at this script now, so you need place one NAT at one AZ, place this instance to auto-scale group, then we have HA-NAT now.
