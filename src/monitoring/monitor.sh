#!/bin/bash
# monitor.sh - Send SLURM job metrics to InfluxDB

# Get environment variables
INFLUXDB_URL=${INFLUXDB_URL:-"http://localhost:8086"}
INFLUXDB_TOKEN=${INFLUXDB_TOKEN:-"your_token_here"}
INFLUXDB_ORG=${INFLUXDB_ORG:-"hpc_monitoring"}
INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-"energy_metrics"}
INTERVAL=${MONITOR_INTERVAL:-5}

# Get SLURM job info
JOB_ID=$SLURM_JOB_ID
NODE_LIST=$SLURM_JOB_NODELIST
USER=$USER
JOB_NAME=$SLURM_JOB_NAME

# Function to send data to InfluxDB
send_to_influx() {
    local timestamp=$(date +%s)000000000
    local data="slurm_metrics,job_id=$JOB_ID,user=$USER,job_name=$JOB_NAME,node=$NODE $@"

    curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
         -H "Authorization: Token $INFLUXDB_TOKEN" \
         -H "Content-Type: text/plain; charset=utf-8" \
         --data-binary "$data $timestamp"

    echo "Data sent: $data"
}

# Monitor loop
echo "Starting monitoring for SLURM job $JOB_ID on $NODE_LIST"
while true; do
    # Get CPU usage
    CPU_PCT=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')

    # Get memory usage
    MEM_PCT=$(free | grep Mem | awk '{print $3/$2 * 100.0}')

    # Get GPU metrics if nvidia-smi is available
    if command -v nvidia-smi &> /dev/null; then
        # GPU utilization
        GPU_UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | paste -sd "," -)

        # GPU memory usage
        GPU_MEM=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | paste -sd "," -)

        # GPU power usage
        GPU_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits | paste -sd "," -)

        # GPU temperature
        GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | paste -sd "," -)

        # Send GPU metrics
        send_to_influx "cpu_pct=$CPU_PCT,mem_pct=$MEM_PCT,gpu_util=$GPU_UTIL,gpu_mem=$GPU_MEM,gpu_power=$GPU_POWER,gpu_temp=$GPU_TEMP"
    else
        # Send CPU/memory metrics only
        send_to_influx "cpu_pct=$CPU_PCT,mem_pct=$MEM_PCT"
    fi

    sleep $INTERVAL
done