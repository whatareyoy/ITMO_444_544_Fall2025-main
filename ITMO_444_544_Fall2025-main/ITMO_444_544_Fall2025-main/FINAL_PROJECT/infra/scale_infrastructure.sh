#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Scaling infrastructure: launching additional EC2 instance..."

# Load base instance ID
BASE_INSTANCE_ID=$(head -n 1 instance_id.txt)

# Create AMI from base instance
AMI_NAME="resume-app-ami-$(date +%Y%m%d%H%M%S)"
AMI_ID=$(aws ec2 create-image --instance-id "$BASE_INSTANCE_ID" \
    --name "$AMI_NAME" --no-reboot \
    --region "$REGION" --query "ImageId" --output text)
echo "$AMI_ID" > ami_id.txt
log_to_cw "AMI created from base instance: $AMI_ID"

# wait for AMI is available
aws ec2 wait image-available --image-ids "$AMI_ID" --region "$REGION"

# Create Launch Template
LT_NAME="resume-app-lt"
LT_ID=$(aws ec2 create-launch-template \
    --launch-template-name "$LT_NAME" \
    --version-description "v1" \
    --launch-template-data "{
        \"ImageId\": \"$AMI_ID\",
        \"InstanceType\": \"$INSTANCE_TYPE\",
        \"KeyName\": \"$KEY_NAME\",
        \"IamInstanceProfile\": {\"Name\": \"ResumeAppProfile\"},
        \"SecurityGroupIds\": [\"$(cat sg_id.txt)\"],
        \"UserData\": \"$(base64 -w0 < user_data_systemd.sh)\"
    }" \
    --region "$REGION" \
    --query "LaunchTemplate.LaunchTemplateId" --output text)
echo "$LT_ID" > launch_template_id.txt
log_to_cw "Launch Template created: $LT_ID"

# Step 3: Create Target Group
TG_NAME="resume-app-tg"
VPC_ID=$(cat vpc_id.txt)
TG_ARN=$(aws elbv2 create-target-group \
    --name "$TG_NAME" \
    --protocol HTTP --port 5000 \
    --vpc-id "$VPC_ID" \
    --target-type instance \
    --region "$REGION" \
    --query "TargetGroups[0].TargetGroupArn" --output text)
echo "$TG_ARN" > target_group_arn.txt
log_to_cw "Target Group created: $TG_ARN"

# Create Load Balancer
LB_NAME="resume-app-lb"
SUBNET1=$(cat subnet1_id.txt)
SUBNET2=$(cat subnet2_id.txt)
LB_ARN=$(aws elbv2 create-load-balancer \
    --name "$LB_NAME" \
    --subnets "$SUBNET1" "$SUBNET2" \
    --security-groups "$(cat sg_id.txt)" \
    --region "$REGION" \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)
echo "$LB_ARN" > lb_arn.txt
log_to_cw "Load Balancer created: $LB_ARN"

# Create Listener
aws elbv2 create-listener \
    --load-balancer-arn "$LB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
    --region "$REGION"
log_to_cw "Listener created for LB"

# Create Auto Scaling Group
ASG_NAME="resume-app-asg"
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name "$ASG_NAME" \
    --launch-template "LaunchTemplateId=$LT_ID,Version=1" \
    --min-size 1 --max-size 4 --desired-capacity 2 \
    --vpc-zone-identifier "$SUBNET1,$SUBNET2" \
    --target-group-arns "$TG_ARN" \
    --region "$REGION"
log_to_cw "Auto Scaling Group created: $ASG_NAME"

send_cw_metric 1
