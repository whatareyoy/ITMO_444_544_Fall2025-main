#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "=== Deploying Application ==="

# Variables
INSTANCE_ID=$(cat instance_id.txt)
S3_ARTIFACT="s3://$RESUME_BUCKET_NAME/resume-app.zip"

# Step 1: Upload deployment artifact to S3
# (Assumes you already zipped your app locally: resume-app.zip)
aws s3 cp resume-app.zip "$S3_ARTIFACT" --region "$REGION"
log_to_cw "Deployment artifact uploaded to $S3_ARTIFACT"

# Step 2: Use SSM Run Command to deploy on EC2
COMMANDS=$(cat <<EOF
#!/bin/bash
set -e
cd /home/ubuntu
aws s3 cp $S3_ARTIFACT . --region $REGION
rm -rf resume-app && mkdir resume-app
unzip -o resume-app.zip -d resume-app
cd resume-app
pip3 install -r requirements.txt
sudo systemctl restart resume
EOF
)

aws ssm send-command \
    --targets "Key=instanceIds,Values=$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Deploy resume app" \
    --parameters "commands=$COMMANDS" \
    --region "$REGION"

log_to_cw "SSM deployment command sent to EC2: $INSTANCE_ID"
send_cw_metric 1
