#!/bin/bash
set -e
source config.txt
source cloudwatch_utils.sh

log_to_cw "Scheduling automatic teardown in $AUTO_TEARDOWN_HOURS hours..."

# Calculate hour and minute separately
HOUR=$(date -d "+$AUTO_TEARDOWN_HOURS hours" +"%H")
MIN=$(date -d "+$AUTO_TEARDOWN_HOURS hours" +"%M")

# Build cron job line
CRON_JOB="$MIN $HOUR * * * /bin/bash $(pwd)/destroy_infrastructure.sh >> $(pwd)/teardown.log 2>&1"

# Overwrite crontab with just this job
echo "$CRON_JOB" | crontab -

# Document timezone
SERVER_TZ=$(date +"%Z")
SCHEDULED_TIME=$(date -d "+$AUTO_TEARDOWN_HOURS hours")
log_to_cw "Automatic teardown scheduled at $SCHEDULED_TIME ($SERVER_TZ time zone)"
send_cw_metric 1
