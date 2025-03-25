#!/bin/bash
# process_monitor.sh - Monitor specific Python processes

# Get environment variables
INFLUXDB_URL=${INFLUXDB_URL:-"http://localhost:8086"}
INFLUXDB_TOKEN=${INFLUXDB_TOKEN:-"your_token_here"}
INFLUXDB_ORG=${INFLUXDB_ORG:-"hpc_monitoring"}
INFLUXDB_BUCKET=${INFLUXDB_BUCKET:-"energy_metrics"}
INTERVAL=${MONITOR_INTERVAL:-5}
EXPERIMENT_ID=${EXPERIMENT_ID:-"unknown"}
JOB_ID=${SLURM_JOB_ID:-"unknown"}

# Find Python processes related to our training
find_python_processes() {
    # Look for Python processes running the specified script
    pids=$(pgrep -f "python.*Rscript[12].py")
    echo $pids
}

# Monitor specific processes
monitor_processes() {
    pids=$(find_python_processes)
    timestamp=$(date +%s)000000000

    if [ -z "$pids" ]; then
        echo "No matching Python processes found"
        return
    fi

    for pid in $pids; do
        # Get process stats
        if [ -d "/proc/$pid" ]; then
            # CPU usage
            cpu_usage=$(ps -p $pid -o %cpu --no-headers)

            # Memory usage
            mem_usage=$(ps -p $pid -o %mem --no-headers)
            mem_rss=$(ps -p $pid -o rss --no-headers)

            # Process name and command
            cmd=$(ps -p $pid -o cmd --no-headers | sed 's/ /_/g' | cut -c 1-50)
            proc_name=$(ps -p $pid -o comm --no-headers)

            # Create data point
            data="process_metrics,job_id=$JOB_ID,experiment_id=$EXPERIMENT_ID,pid=$pid,process=$proc_name "
            data+="cpu_percent=$cpu_usage,memory_percent=$mem_usage,memory_rss=$mem_rss,command=\"$cmd\""

            # Send to InfluxDB
            curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=ns" \
                 -H "Authorization: Token $INFLUXDB_TOKEN" \
                 -H "Content-Type: text/plain; charset=utf-8" \
                 --data-binary "$data $timestamp"

            echo "Sent process $pid ($proc_name) metrics to InfluxDB"
        fi
    done
}

# Main loop
echo "Starting process monitoring"
while true; do
    monitor_processes
    sleep $INTERVAL
done