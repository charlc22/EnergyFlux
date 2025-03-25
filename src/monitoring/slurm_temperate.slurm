#!/bin/bash
# submit_job.sh - Submit a SLURM job with monitoring

# Default values
PARALLEL_MODE=${1:-"none"}
PRECISION_MODE=${2:-"fp32"}
NUM_GPUS=${3:-1}
JOB_NAME=${4:-"parallel_training"}

# Generate SLURM script
cat > temp_job.slurm << EOF
#!/bin/bash
#SBATCH --job-name=${JOB_NAME}
#SBATCH --output=${JOB_NAME}_%j.out
#SBATCH --error=${JOB_NAME}_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:${NUM_GPUS}
#SBATCH --time=01:00:00

# Load modules
module load python/3.9
module load cuda/11.7

# Set environment variables
export INFLUXDB_URL="http://localhost:8086"
export INFLUXDB_TOKEN="63c35990748f6a8b06de086ad5c785b9d7da6d2c013d16cb4c3bd36963b953c1"
export INFLUXDB_ORG="hpc_monitoring"
export INFLUXDB_BUCKET="energy_metrics"
export MONITOR_INTERVAL=5

# Create a unique experiment ID
export EXPERIMENT_ID="${JOB_NAME}_${PARALLEL_MODE}_${PRECISION_MODE}_$(date +%s)"

echo "Starting job with configuration:"
echo "Parallel Mode: $PARALLEL_MODE"
echo "Precision Mode: $PRECISION_MODE"
echo "Experiment ID: $EXPERIMENT_ID"

# Start the monitoring script in the background
./monitor.sh &
MONITOR_PID=\$!

# Record the start of the experiment
curl -s -XPOST "\$INFLUXDB_URL/api/v2/write?org=\$INFLUXDB_ORG&bucket=\$INFLUXDB_BUCKET&precision=s" \\
     -H "Authorization: Token \$INFLUXDB_TOKEN" \\
     -H "Content-Type: text/plain; charset=utf-8" \\
     --data-binary "experiment_events,job_id=\$SLURM_JOB_ID,experiment_id=\$EXPERIMENT_ID,parallel_mode=$PARALLEL_MODE,precision_mode=$PRECISION_MODE event=\"start\",node=\"\$SLURM_JOB_NODELIST\" \$(date +%s)"

# Run your Python script
python Rscript2.py --parallel-mode $PARALLEL_MODE --precision-mode $PRECISION_MODE

# Record the end of the experiment
curl -s -XPOST "\$INFLUXDB_URL/api/v2/write?org=\$INFLUXDB_ORG&bucket=\$INFLUXDB_BUCKET&precision=s" \\
     -H "Authorization: Token \$INFLUXDB_TOKEN" \\
     -H "Content-Type: text/plain; charset=utf-8" \\
     --data-binary "experiment_events,job_id=\$SLURM_JOB_ID,experiment_id=\$EXPERIMENT_ID,parallel_mode=$PARALLEL_MODE,precision_mode=$PRECISION_MODE event=\"end\",node=\"\$SLURM_JOB_NODELIST\" \$(date +%s)"

# Kill the monitoring script
kill \$MONITOR_PID

echo "Job completed"
EOF

# Submit the job
sbatch temp_job.slurm

# Clean up
rm temp_job.slurm