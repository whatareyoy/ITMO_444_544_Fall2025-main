#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "=== Creating Infrastructure ==="

if [ -z "$REGION" ]; then
  REGION="us-east-1"
  echo "REGION not set, defaulting to $REGION"
fi

# Create S3 bucket
aws s3api create-bucket --bucket $RESUME_BUCKET_NAME --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION 2>/dev/null || true
log_to_cw "S3 bucket created: $RESUME_BUCKET_NAME"

# VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --region "$REGION" \
    --query "Vpc.VpcId" --output text)
echo "$VPC_ID" > vpc_id.txt
log_to_cw "VPC created: $VPC_ID"

# Dynamic AZs
AZS=($(aws ec2 describe-availability-zones --region "$REGION" \
    --query "AvailabilityZones[].ZoneName" --output text)) 

SUBNET1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_1" \
    --availability-zone "${AZS[0]}" --query "Subnet.SubnetId" --output text)
SUBNET2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$SUBNET_CIDR_2" \
    --availability-zone "${AZS[1]}" --query "Subnet.SubnetId" --output text)
log_to_cw "Subnets created: $SUBNET1, $SUBNET2"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region "$REGION" \
    --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
log_to_cw "Internet Gateway attached: $IGW_ID"

# Route Table
RTB_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --region "$REGION" \
    --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET1" --region "$REGION"
aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET2" --region "$REGION"

# Security Group - Checking for Security Group that already exi>
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group->
    --region "$REGION" --query "SecurityGroups[0].GroupId" --ou>
if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    SG_ID=$(aws ec2 create-security-group --group-name "$SECURI>
        --description "$SECURITY_GROUP_DESC" --vpc-id "$VPC_ID">
        --query "GroupId" --output text)
    MY_IP=$(curl -s ifconfig.me)/32
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID>
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID>
fi
log_to_cw "Security Group ready: $SG_ID"

# Key Pair - Checking for key that already exists
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --regio>
    aws ec2 create-key-pair --key-name "$KEY_NAME" --key-type ">
        --query "KeyMaterial" --output text > "$KEY_FILE"
    chmod 400 "$KEY_FILE"
fi
log_to_cw "Key Pair ensured: $KEY_NAME"


log_to_cw "Subnets created: $SUBNET1, $SUBNET2"

# IAM Role + Instance Profile
ROLE_NAME="ResumeAppRole"
PROFILE_NAME="ResumeAppProfile"

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1;>
    aws iam create-role --role-name "$ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }'
    aws iam attach-role-policy --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
fi

if ! aws iam get-instance-profile --instance-profile-name "$PRO>
    aws iam create-instance-profile --instance-profile-name "$P>
    aws iam add-role-to-instance-profile --instance-profile-nam>
fi

# AMI
AMI_ID=$(aws ec2 describe-images --owners "$UBUNTU_OWNER" \
  --filters "Name=name,Values=$UBUNTU_FILTER" \
  --region "$REGION" \
  --query "Images | sort_by(@,&CreationDate) | [-1].ImageId" -->

echo $AMI_ID

# Launch EC2 via UserData
USER_DATA="#!/bin/bash
sudo apt update -y
sudo apt install -y python3-pip git
export RESUME_BUCKET_NAME=$RESUME_BUCKET_NAME

# Clone API and frontend
https://github.com/whatareyoy/ITMO_444_544_Fall2025-main/tree/main/ITMO_444_544_Fall2025-main/ITMO_444_544_Fall2025-main/FINAL_PROJECT/api
https://github.com/whatareyoy/ITMO_444_544_Fall2025-main/tree/main/ITMO_444_544_Fall2025-main/ITMO_444_544_Fall2025-main/FINAL_PROJECT/frontend

# Install dependencies
cd /home/ubuntu/resume-flask-api
pip3 install -r requirements.txt

# Copy frontend to Flask static folder
rm -rf /home/ubuntu/resume-flask-api/frontend
cp -r /home/ubuntu/resume-flask-frontend /home/ubuntu/resume-fl>

# Start Flask API
nohup gunicorn -b 0.0.0.0:5000 app:app &"

# Launch EC2 with IAM role
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --coun>
    --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" --subnet-id "$SUBNET1" \
    --associate-public-ip-address \
    --iam-instance-profile Name="$PROFILE_NAME" \
    --user-data "$USER_DATA" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --r>
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANC>
    --query "Reservations[0].Instances[0].PublicIpAddress" --ou>

echo "$INSTANCE_ID" > instance_id.txt
echo "$PUBLIC_IP" > instance_ip.txt
log_to_cw "EC2 instance created: $INSTANCE_ID ($PUBLIC_IP)"
send_cw_metric 1
