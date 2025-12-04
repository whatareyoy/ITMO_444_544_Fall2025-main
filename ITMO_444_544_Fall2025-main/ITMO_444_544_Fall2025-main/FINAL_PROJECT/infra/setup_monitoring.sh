#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Setting up CloudWatch monitoring..."

# Create Log Group
aws logs create-log-group --log-group-name "$CW_LOG_GROUP" --region "$REGION" 2>/dev/null || true
aws logs create-log-stream --log-group-name "$CW_LOG_GROUP" --log-stream-name "$CW_LOG_STREAM" --region "$REGION" 2>/dev/null || true

# Create SNS Topic for alarm notifications
SNS_TOPIC_NAME="ResumeAppAlerts"
SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --region "$REGION" --query "TopicArn" --output text)
echo "$SNS_TOPIC_ARN" > sns_topic_arn.txt
log_to_cw "SNS topic created: $SNS_TOPIC_ARN"

# Subscribe your email (replace with your address)
aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL" --region "$REGION" || true
log_to_cw "SNS subscription created for $ALERT_EMAIL"

# Step 2: Create CPU Alarms
if [ -f asg_name.txt ]; then
  # Monitor Auto Scaling Group average CPU
  ASG_NAME=$(cat asg_name.txt)
  aws cloudwatch put-metric-alarm \
      --alarm-name "HighCPUAlarm-ASG" \
      --metric-name CPUUtilization \
      --namespace "AWS/EC2" \
      --statistic Average \
      --period 300 \
      --threshold 70 \
      --comparison-operator GreaterThanThreshold \
      --dimensions Name=AutoScalingGroupName,Value=$ASG_NAME \
      --evaluation-periods 1 \
      --alarm-actions "$SNS_TOPIC_ARN" \
      --region "$REGION"
  log_to_cw "ASG CPU alarm created for $ASG_NAME"
else
  # Monitor each instance individually
  while read INSTANCE_ID; do
    aws cloudwatch put-metric-alarm \
        --alarm-name "HighCPUAlarm-$INSTANCE_ID" \
        --metric-name CPUUtilization \
        --namespace "AWS/EC2" \
        --statistic Average \
        --period 300 \
        --threshold 70 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=InstanceId,Value=$INSTANCE_ID \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --region "$REGION"
    log_to_cw "CPU alarm created for instance: $INSTANCE_ID"
  done < instance_id.txt
fi

log_to_cw "CloudWatch monitoring setup complete"
send_cw_metric 1

