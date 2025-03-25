#!/bin/bash
# gpu_monitor.sh - Monitor GPU metrics and send to InfluxDB

# Get environment variables
INFLUXDB_URL=${INFLUXDB_URL:-"http://localhost:8086"}
INFLUXDB_TOKEN=${INFLUXDB_TOKEN:-"your_token_here"}
INFLUXDB_ORG=${INFLUXDB_ORG:-"hpc_monitoring"}
INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-"energy_metrics"}
INTERVAL=${MONITOR_INTERVAL:-5}
EXPERIMENT_ID=${EXPERIMENT_ID:-"unknown"}
JOB_ID=${SLURM_JOB_ID:-"unknown"}

# Function to send GPU metrics to InfluxDB
collect_and_send_gpu_metrics() {
    # Check if nvidia-smi is available
    if ! command -v nvidia-smi &> /dev/null; then
        echo "nvidia-smi not found, skipping GPU metrics"
        return
    }

    # Get GPU count
    gpu_count=$(nvidia-smi --list-gpus | wc -l)
    timestamp=$(date +%s)000000000

    # Iterate through each GPU
    for gpu_id in $(seq 0 $((gpu_count-1))); do
        # Get detailed metrics
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_util=$(nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i $gpu_id)
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits -i $gpu_id)
        gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits -i $gpu_id | sed 's/ W//')
        gpu_processes=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader -i $gpu_id | wc -l)

        # Get GPU model
        gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader -i $gpu_id | sed 's/ /_/g')

        # Create data point
        data="gpu_metrics,job_id=$JOB_ID,experiment_id=$EXPERIMENT_ID,gpu_id=$gpu_id,gpu_model=$gpu_model "
        data+="utilization=$gpu_util,memory_utilization=$gpu_mem_util,memory_used=$gpu_mem_used,"
        data+="memory_total=$gpu_mem_total,temperature=$gpu_temp,power_draw=$gpu_power,processes=$gpu_processes"

        # Send to InfluxDB
        curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
             -H "Authorization: Token $INFLUXDB_TOKEN" \
             -H "Content-Type: text/plain; charset=utf-8" \
             --data-binary "$data $timestamp"

        echo "Sent GPU $gpu_id metrics to InfluxDB"
    done
}

# Main loop
echo "Starting GPU monitoring for experiment $EXPERIMENT_ID"
while true; do
    collect_and_send_gpu_metrics
    sleep $INTERVAL
done