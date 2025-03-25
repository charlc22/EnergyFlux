#!/bin/bash
#SBATCH --job-name=parallel_training
#SBATCH --output=parallel_training_%j.out
#SBATCH --error=parallel_training_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:2
#SBATCH --time=01:00:00

# Load required modules
module load python/3.9
module load cuda/11.7

# Set environment variables for InfluxDB
export INFLUXDB_URL="http://localhost:8086"
export INFLUXDB_TOKEN="63c35990748f6a8b06de086ad5c785b9d7da6d2c013d16cb4c3bd36963b953c1"
export INFLUXDB_ORG="hpc_monitoring"
export INFLUXDB_BUCKET="energy_metrics"
export MONITOR_INTERVAL=5

# Additional metadata for the experiment
export EXPERIMENT_ID="exp_$(date +%s)_${SLURM_JOB_ID}"
export PARALLEL_MODE="data"  # Options: none, data, model, pipeline
export PRECISION_MODE="amp"  # Options: fp32, amp, qat

# Start the monitoring script in the background
./monitor.sh &
MONITOR_PID=$!

# Record the start of the experiment
curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=s" \
     -H "Authorization: Token $INFLUXDB_TOKEN" \
     -H "Content-Type: text/plain; charset=utf-8" \
     --data-binary "experiment_events,job_id=$SLURM_JOB_ID,experiment_id=$EXPERIMENT_ID,parallel_mode=$PARALLEL_MODE,precision_mode=$PRECISION_MODE event=\"start\",node=\"$SLURM_JOB_NODELIST\" $(date +%s)"

# Run your Python script
python Rscript2.py --parallel-mode $PARALLEL_MODE --precision-mode $PRECISION_MODE

# Record the end of the experiment
curl -s -XPOST "$INFLUXDB_URL/api/v2/write?org=$INFLUXDB_ORG&bucket=$INFLUXDB_BUCKET&precision=s" \
     -H "Authorization: Token $INFLUXDB_TOKEN" \
     -H "Content-Type: text/plain; charset=utf-8" \
     --data-binary "experiment_events,job_id=$SLURM_JOB_ID,experiment_id=$EXPERIMENT_ID,parallel_mode=$PARALLEL_MODE,precision_mode=$PRECISION_MODE event=\"end\",node=\"$SLURM_JOB_NODELIST\" $(date +%s)"

# Kill the monitoring script
kill $MONITOR_PID

echo "Job completed"