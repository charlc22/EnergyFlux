#!/bin/bash
# hpc_monitor.sh - Comprehensive HPC monitoring solution

# Load environment variables
source .env

# Check if we're in a SLURM job
if [ -n "$SLURM_JOB_ID" ]; then
    JOB_ID=$SLURM_JOB_ID
    NODE_LIST=$SLURM_JOB_NODELIST
    echo "Running within SLURM job $JOB_ID on nodes $NODE_LIST"
else
    # Generate a random ID if not in SLURM
    JOB_ID="manual_$(date +%s)"
    NODE_LIST=$(hostname)
    echo "Running outside SLURM, using ID $JOB_ID on node $NODE_LIST"
fi

# Setup experiment ID
EXPERIMENT_ID=${EXPERIMENT_ID:-"exp_${JOB_ID}"}

# Print configuration
echo "=== Monitoring Configuration ==="
echo "InfluxDB URL: $INFLUXDB_URL"
echo "InfluxDB Organization: $INFLUXDB_ORG"
echo "InfluxDB Bucket: $INFLUXDB_BUCKET"
echo "Monitoring Interval: ${MONITOR_INTERVAL}s"
echo "Experiment ID: $EXPERIMENT_ID"
echo "=============================="

# Function to monitor system metrics (CPU, memory, disk)
monitor_system() {
    timestamp=$(date +%s)000000000

    # CPU metrics
    cpu_pct=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')
    load_avg=$(cat /proc/loadavg | awk '{print $1}')

    # Memory metrics
    mem_total=$(free -m | grep Mem | awk '{print $2}')
    mem_used=$(free -m | grep Mem | awk '{print $3}')
    mem_pct=$(free | grep Mem | awk '{print $3/$2 * 100.0}')

    # Disk metrics
    disk_used=$(df -h / | grep / | awk '{print $3}' | sed 's/G//')
    disk_total=$(df -h / | grep / | awk '{print $2}' | sed 's/G//')
    disk_pct=$(df -h / | grep / | awk '{print $5}' | sed 's/%//')

    # Network metrics
    rx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    tx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

    # Create data point
    data="system_metrics,job_id=$JOB_ID,experiment_id=$EXPERIMENT_ID,node=$NODE_LIST "
    data+="cpu_percent=$cpu_pct,load_avg=$load_avg,mem_total=$mem_total,mem_used=$mem_used,"
    data+="mem_percent=$mem_pct,disk_used=$disk_used,disk_total=$disk_total,"
    data+="disk_percent=$disk_pct,network_rx=$rx_bytes,network_tx=$tx_bytes"

    # Send to InfluxDB
    curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
         -H "Authorization: Token $INFLUXDB_TOKEN" \
         -H "Content-Type: text/plain; charset=utf-8" \
         --data-binary "$data $timestamp"
}

# Function to monitor GPU metrics
monitor_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        return
    fi

    timestamp=$(date +%s)000000000
    gpu_count=$(nvidia-smi --list-gpus | wc -l)

    for gpu_id in $(seq 0 $((gpu_count-1))); do
        # Get detailed metrics
        gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_util=$(nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i $gpu_id)
        gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits -i $gpu_id)
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits -i $gpu_id)
        gpu_power=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits -i $gpu_id | sed 's/ W//')
        gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader -i $gpu_id | sed 's/ /_/g')

        # Create data point
        data="gpu_metrics,job_id=$JOB_ID,experiment_id=$EXPERIMENT_ID,gpu_id=$gpu_id,gpu_model=$gpu_model "
        data+="utilization=$gpu_util,memory_utilization=$gpu_mem_util,memory_used=$gpu_mem_used,"
        data+="memory_total=$gpu_mem_total,temperature=$gpu_temp,power_draw=$gpu_power"

        # Send to InfluxDB
        curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
             -H "Authorization: Token $INFLUXDB_TOKEN" \
             -H "Content-Type: text/plain; charset=utf-8" \
             --data-binary "$data $timestamp"
    done
}

# Function to monitor Python processes
monitor_processes() {
    # Look for Python processes running our research scripts
    pids=$(pgrep -f "python.*R(script1|script2).py")

    if [ -z "$pids" ]; then
        return
    fi

    timestamp=$(date +%s)000000000

    for pid in $pids; do
        if [ -d "/proc/$pid" ]; then
            # CPU & memory usage
            cpu_usage=$(ps -p $pid -o %cpu --no-headers)
            mem_usage=$(ps -p $