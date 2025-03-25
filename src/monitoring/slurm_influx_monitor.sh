#!/bin/bash
# slurm_influx_monitor.sh - Monitor SLURM jobs and send to InfluxDB

# Load environment variables
source .env

# Function to query SLURM for job metrics
get_job_metrics() {
    local job_id=$1

    # Get job info
    job_info=$(scontrol show job $job_id -o)

    # Extract node list
    nodes=$(echo "$job_info" | grep -oP "NodeList=\K[^ ]+")

    # For each node, get metrics
    for node in $(scontrol show hostnames $nodes); do
        # Get CPU and memory usage for this job on this node
        cpu_usage=$(sstat --format=AveCPU -j $job_id -n | awk '{print $1}' | sed 's/%//')
        mem_usage=$(sstat --format=AveRSS -j $job_id -n | awk '{print $1}')

        # Send to InfluxDB
        timestamp=$(date +%s)000000000
        data="slurm_job_metrics,job_id=$job_id,node=$node cpu_pct=$cpu_usage,mem_usage=$mem_usage"

        curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
             -H "Authorization: Token $INFLUXDB_TOKEN" \
             -H "Content-Type: text/plain; charset=utf-8" \
             --data-binary "$data $timestamp"
    done
}

# Main monitoring loop
if [ -z "$1" ]; then
    echo "Usage: $0 <job_id>"
    exit 1
fi

job_id=$1
echo "Starting monitoring for SLURM job $job_id"

while true; do
    # Check if job is still running
    job_state=$(scontrol show job $job_id | grep -oP "JobState=\K[^ ]+")
    if [[ "$job_state" != "RUNNING" ]]; then
        echo "Job $job_id is no longer running (state: $job_state). Exiting."
        exit 0
    fi

    # Get and send metrics
    get_job_metrics $job_id

    # Wait for next interval
    sleep ${MONITOR_INTERVAL:-5}
done