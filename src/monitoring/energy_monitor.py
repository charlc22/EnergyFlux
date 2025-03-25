from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from influxdb_client.client.delete_api import DeleteApi
import random
import time
import datetime

# Configuration from .env file
INFLUXDB_URL = "http://localhost:8086"
INFLUXDB_TOKEN = "63c35990748f6a8b06de086ad5c785b9d7da6d2c013d16cb4c3bd36963b953c1"
INFLUXDB_ORG = "hpc_monitoring"
INFLUXDB_BUCKET = "energy_metrics"

def clear_bucket(client, bucket, org):
    """
    Clear existing data from the bucket
    """
    delete_api = client.delete_api()

    # Get current time and start of the day
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(days=30)  # Clear last 30 days

    try:
        delete_api.delete(
            start_time,
            end_time,
            '_measurement="system_metrics"',
            bucket,
            org
        )
        print(f"Cleared existing 'system_metrics' data from bucket: {bucket}")
    except Exception as e:
        print(f"Warning: Could not clear bucket - {e}")

def generate_realistic_metrics():
    """
    Generate comprehensive and realistic sample metrics
    """
    # Create InfluxDB client
    client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)

    # Clear existing data to avoid type conflicts
    clear_bucket(client, INFLUXDB_BUCKET, INFLUXDB_ORG)

    # Write client
    write_api = client.write_api(write_options=SYNCHRONOUS)

    try:
        # Simulate metrics over a longer period with more data points
        start_time = time.time()

        # Generate metrics every minute for 4 hours
        for minute in range(0, 240, 1):
            # Calculate timestamp
            current_time = start_time + (minute * 60)
            timestamp = int(current_time * 1_000_000_000)  # Convert to nanoseconds

            # Create more dynamic and varied metrics
            # Use sine wave to create more natural-looking variations
            time_factor = minute / 240 * (2 * 3.14159)

            # CPU Metrics with sinusoidal variation
            base_cpu_usage = max(10, min(90, 50 + 30 * math.sin(time_factor)))
            cpu_point = Point("system_metrics") \
                .tag("metric_type", "cpu") \
                .tag("run", str(minute)) \
                .field("usage_percent", round(base_cpu_usage, 2)) \
                .field("frequency_mhz", round(base_cpu_usage * 15, 2)) \
                .time(timestamp)

            # Memory Metrics
            base_memory_usage = max(30, min(90, 60 + 20 * math.sin(time_factor + 1)))
            memory_point = Point("system_metrics") \
                .tag("metric_type", "memory") \
                .tag("run", str(minute)) \
                .field("usage_percent", round(base_memory_usage, 2)) \
                .field("used_mb", round(base_memory_usage * 320, 2)) \
                .field("total_mb", 32768.0) \
                .time(timestamp)

            # GPU Metrics
            base_gpu_util = max(10, min(95, 50 + 35 * math.sin(time_factor + 2)))
            base_temp = max(35, min(85, 60 + 20 * math.sin(time_factor + 3)))
            gpu_point = Point("system_metrics") \
                .tag("metric_type", "gpu") \
                .tag("run", str(minute)) \
                .field("utilization_percent", round(base_gpu_util, 2)) \
                .field("temperature_celsius", round(base_temp, 2)) \
                .field("memory_used_mb", round(base_gpu_util * 80, 2)) \
                .field("power_watts", round(base_gpu_util * 2.5, 2)) \
                .time(timestamp)

            # Power Metrics
            power_point = Point("system_metrics") \
                .tag("metric_type", "power") \
                .tag("run", str(minute)) \
                .field("gpu_power_watts", round(base_gpu_util * 2.5, 2)) \
                .field("cpu_power_watts", round(base_cpu_usage, 2)) \
                .time(timestamp)

            # Write points to InfluxDB
            write_api.write(bucket=INFLUXDB_BUCKET, org=INFLUXDB_ORG, record=[
                cpu_point,
                memory_point,
                gpu_point,
                power_point
            ])

        print("Comprehensive system metrics successfully written to InfluxDB!")

    except Exception as e:
        print(f"Error writing to InfluxDB: {e}")

    finally:
        # Close the client
        client.close()

# Import math for sine wave generation
import math

# Run the script
if __name__ == "__main__":
    generate_realistic_metrics()