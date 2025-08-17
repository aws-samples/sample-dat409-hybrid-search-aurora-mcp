#!/usr/bin/env python3
"""
Fixed Dataset Generator for DAT409 Workshop
Version 4.0 - Fixed template variables and improved diversity
"""

import json
import random
import hashlib
from datetime import datetime, timedelta
import uuid
from typing import List, Dict, Any, Tuple
import re

class FixedIncidentGenerator:
    """Generate diverse, realistic incidents with proper variable substitution"""
    
    def __init__(self, target_logs: int = 1500):
        self.target_logs = target_logs
        self.num_incidents = int(target_logs / 4)
        self.black_friday_2024 = datetime(2024, 11, 29, 0, 0, 0)
        self.generated_incidents = []
        self.severity_counter = {'critical': 0, 'warning': 0, 'info': 0}
        self.incident_archetypes = self._define_enhanced_archetypes()
        self.variation_counter = 0
        self.used_content_hashes = set()  # Track used content to ensure diversity
        
    def _define_enhanced_archetypes(self) -> List[Dict]:
        """Define diverse incident types with complete variable mappings"""
        return [
            {
                'id': 'connection_exhaustion_spike',
                'category': 'connection',
                'base_metrics': {
                    'max_connections': 1000,
                    'active_connections_range': (950, 999),
                    'wait_time_ms_range': (5000, 30000),
                    'error_code': 'PG-53300',
                    'spike_duration_min_range': (5, 60),
                    'threshold_range': (85, 99)
                },
                'variations': {
                    'dba': [
                        "FATAL: remaining connection slots are reserved for non-replication superuser connections [{error_code}]",
                        "ERROR: too many connections for role 'app_user' (current: {active}, max: {max_connections})",
                        "PANIC: connection limit exceeded - {active}/{max_connections} after {spike_duration_min:.1f}min spike",
                        "Connection pool saturation: {active} active, {wait_count} waiting, threshold {threshold}% exceeded",
                        "Database refusing connections: SQLSTATE 53300 after {wait_ms}ms wait"
                    ],
                    'developer': [
                        "HikariPool-1 - Connection timeout after {wait_ms}ms during traffic surge",
                        "ConnectionPoolExhaustedException: All {max_connections} connections in use (waited {wait_ms}ms)",
                        "JDBC connection failed after {wait_ms}ms: FATAL: too many clients already",
                        "Connection pool exhausted - {wait_count} threads waiting, {active} active connections",
                        "Database unavailable after {wait_ms}ms wait - circuit breaker opened at {threshold}%"
                    ],
                    'sre': [
                        "CloudWatch: DatabaseConnections crossed {active} ({threshold}% utilization)",
                        "Alert: Connection saturation {active}/{max_connections} for {spike_duration_min:.0f} minutes",
                        "CRITICAL: Database connections at {threshold}% capacity ({active} connections)",
                        "Monitoring: Connection pool {threshold}% full, {wait_count} requests queued",
                        "AWS RDS Alert: Connection count {active}, wait time {wait_ms}ms"
                    ],
                    'data_engineer': [
                        "ETL job 'daily_aggregation' failed - connection timeout after {wait_ms}ms",
                        "Airflow DAG stalled: connection pool exhausted during {spike_duration_min:.1f}min window",
                        "DBT run failed: waited {wait_ms}ms for connection from saturated pool",
                        "Spark job waiting {wait_ms}ms for database connection - {wait_count} executors blocked",
                        "Data pipeline blocked: connection pool at {threshold}% capacity"
                    ]
                }
            },
            {
                'id': 'slow_connection_leak',
                'category': 'connection',
                'base_metrics': {
                    'leak_rate_per_hour': (5, 20),
                    'idle_connections_range': (100, 400),
                    'active_connections_range': (500, 700),
                    'leak_duration_hours_range': (2, 24),
                    'memory_usage_mb_range': (100, 500)
                },
                'variations': {
                    'dba': [
                        "WARNING: {idle_connections} idle connections detected (leak rate: {leak_rate_per_hour:.1f}/hour)",
                        "Connection leak: idle_in_transaction growing at {leak_rate_per_hour:.0f}/hour for {leak_duration_hours}h",
                        "pg_stat_activity shows {idle_connections} idle connections consuming {memory_usage_mb}MB",
                        "Resource leak: {idle_connections} connections idle, {active} active, total memory {memory_usage_mb}MB",
                        "Connection accumulation: {leak_rate_per_hour:.1f} connections/hour not released properly"
                    ],
                    'developer': [
                        "Connection pool: {idle_connections} idle, {active} active - possible {memory_usage_mb}MB leak",
                        "WARNING: {idle_connections} connections not returned to pool after {leak_duration_hours}h",
                        "Memory leak in connection handling - {leak_rate_per_hour:.0f} connections/hour, {memory_usage_mb}MB used",
                        "Application holding {idle_connections} unused connections for {leak_duration_hours} hours",
                        "Connection pool growing: {active} active + {idle_connections} idle = potential leak"
                    ],
                    'sre': [
                        "Grafana: Connection leak - {leak_rate_per_hour:.1f} connections/hour over {leak_duration_hours}h",
                        "Linear growth: {idle_connections} idle connections, {memory_usage_mb}MB memory consumed",
                        "Anomaly: Idle connections increasing {leak_rate_per_hour:.0f}/hour for past {leak_duration_hours} hours",
                        "Resource alert: {idle_connections} idle connections using {memory_usage_mb}MB RAM",
                        "Connection leak: {leak_rate_per_hour:.1f}/hr growth rate detected over {leak_duration_hours}h period"
                    ],
                    'data_engineer': [
                        "ETL connection pool: {idle_connections} idle connections leaking at {leak_rate_per_hour:.0f}/hour",
                        "Spark executors holding {idle_connections} idle connections, {memory_usage_mb}MB wasted",
                        "Batch job leak: {leak_rate_per_hour:.1f} connections/hour over {leak_duration_hours}h runtime",
                        "Pipeline issue: {idle_connections} connections idle after job completion",
                        "Data job resource leak: {leak_rate_per_hour:.0f}/hour accumulation rate"
                    ]
                }
            },
            {
                'id': 'query_performance_degradation',
                'category': 'performance',
                'base_metrics': {
                    'query_time_before_ms': (50, 200),
                    'query_time_after_ms': (5000, 60000),
                    'affected_query': ['user_dashboard', 'order_search', 'inventory_check', 'report_aggregate'],
                    'rows_scanned_range': (1000000, 50000000),
                    'index_name': ['idx_users_email', 'idx_orders_date', 'idx_products_sku', 'idx_sessions_user'],
                    'slowdown_factor_range': (10, 500),
                    'cpu_usage_range': (70, 99)
                },
                'variations': {
                    'dba': [
                        "Query regression: '{affected_query}' from {query_time_before_ms}ms to {query_time_after_ms}ms ({slowdown_factor}x slower)",
                        "Sequential scan on {rows_scanned} rows - index '{index_name}' not used, CPU at {cpu_usage}%",
                        "Query plan changed: '{affected_query}' now takes {query_time_after_ms}ms scanning {rows_scanned} rows",
                        "Performance alert: '{affected_query}' execution time {slowdown_factor}x slower at {cpu_usage}% CPU",
                        "Index scan taking {slowdown_factor}x longer on '{index_name}' - {rows_scanned} rows examined"
                    ],
                    'developer': [
                        "API timeout: '{affected_query}' taking {query_time_after_ms}ms (was {query_time_before_ms}ms)",
                        "User-facing slowdown: {affected_query} response time degraded {slowdown_factor}x",
                        "Application query '{affected_query}' timeout after {query_time_after_ms}ms at {cpu_usage}% CPU",
                        "Performance regression: '{affected_query}' now {slowdown_factor}x slower than baseline",
                        "Service degradation: '{affected_query}' exceeding SLA by {slowdown_factor}x factor"
                    ],
                    'sre': [
                        "P99 spike: {affected_query} from {query_time_before_ms}ms to {query_time_after_ms}ms",
                        "Service alert: {affected_query} queries {slowdown_factor}x slower, CPU {cpu_usage}%",
                        "Performance degradation: {slowdown_factor}x slowdown on '{affected_query}' queries",
                        "Latency alarm: '{affected_query}' breached {query_time_after_ms}ms threshold",
                        "CloudWatch: Query latency increased {slowdown_factor}x for '{affected_query}'"
                    ],
                    'data_engineer': [
                        "Report timeout: {affected_query} query exceeded {query_time_after_ms}ms",
                        "Dashboard failing: {affected_query} query {slowdown_factor}x slower than normal",
                        "ETL bottleneck: '{affected_query}' step taking {query_time_after_ms}ms",
                        "Batch job delayed: {affected_query} running {slowdown_factor}x slower",
                        "Data pipeline: '{affected_query}' degraded from {query_time_before_ms}ms to {query_time_after_ms}ms"
                    ]
                }
            },
            {
                'id': 'deadlock_cascade',
                'category': 'locking',
                'base_metrics': {
                    'deadlocks_per_minute_range': (5, 50),
                    'affected_tables': ['orders', 'inventory', 'payments', 'shipments', 'users'],
                    'blocked_queries_range': (10, 100),
                    'lock_wait_ms_range': (1000, 10000),
                    'cascade_duration_min_range': (1, 15),
                    'transaction_rollback_range': (20, 200)
                },
                'variations': {
                    'dba': [
                        "Deadlock cascade on '{affected_tables}' - {deadlocks_per_minute}/min for {cascade_duration_min}min",
                        "CRITICAL: {blocked_queries} queries waiting, deadlock rate: {deadlocks_per_minute}/min",
                        "Lock escalation: {transaction_rollback} transactions rolled back on '{affected_tables}'",
                        "Deadlock storm: {blocked_queries} blocked, {deadlocks_per_minute}/min rate",
                        "Circular wait on '{affected_tables}' - {lock_wait_ms}ms average wait time"
                    ],
                    'developer': [
                        "TransactionRollback: deadlock after {lock_wait_ms}ms on '{affected_tables}'",
                        "Application errors: {transaction_rollback} transactions failed in {cascade_duration_min}min",
                        "Deadlock rate {deadlocks_per_minute}/min causing {blocked_queries} request failures",
                        "Transaction retry exhausted - {deadlocks_per_minute} deadlocks/min on '{affected_tables}'",
                        "Database contention: {lock_wait_ms}ms lock wait, {transaction_rollback} rollbacks"
                    ],
                    'sre': [
                        "Alert: Deadlock storm - {deadlocks_per_minute}/min affecting {blocked_queries} queries",
                        "Service disruption: {transaction_rollback} failed transactions in {cascade_duration_min}min",
                        "Critical: {deadlocks_per_minute} deadlocks/min on production tables",
                        "Incident: Lock contention causing {blocked_queries} query backlog",
                        "System alert: {lock_wait_ms}ms lock wait impacting {transaction_rollback} transactions"
                    ],
                    'data_engineer': [
                        "ETL blocked by deadlocks on '{affected_tables}' ({deadlocks_per_minute}/min)",
                        "Data load failing: {transaction_rollback} operations rolled back",
                        "Pipeline stalled: {blocked_queries} queries waiting for {lock_wait_ms}ms",
                        "Batch process deadlocked - {cascade_duration_min}min duration",
                        "Ingestion blocked: {deadlocks_per_minute}/min deadlock rate on '{affected_tables}'"
                    ]
                }
            },
            {
                'id': 'memory_pressure',
                'category': 'resource',
                'base_metrics': {
                    'memory_usage_percent_range': (85, 99),
                    'oom_kills_range': (1, 10),
                    'swap_usage_gb_range': (1, 16),
                    'buffer_cache_hit_range': (30, 70),
                    'work_mem_mb_range': (4, 64)
                },
                'variations': {
                    'dba': [
                        "FATAL: out of memory - {oom_kills} processes killed, {memory_usage_percent}% memory used",
                        "Buffer cache hit ratio dropped to {buffer_cache_hit}% due to memory pressure",
                        "Memory exhaustion: {memory_usage_percent}% RAM, {swap_usage_gb}GB swap active",
                        "work_mem reduced to {work_mem_mb}MB - {oom_kills} OOM events occurred",
                        "Critical memory pressure: cache hit {buffer_cache_hit}%, swap {swap_usage_gb}GB"
                    ],
                    'developer': [
                        "Database OOM: {oom_kills} connections terminated at {memory_usage_percent}% memory",
                        "Application queries failing - database memory at {memory_usage_percent}%",
                        "Memory exhaustion causing slowdown - cache hit ratio {buffer_cache_hit}%",
                        "Database swapping {swap_usage_gb}GB - response times degraded",
                        "Out of memory errors after reaching {memory_usage_percent}% usage"
                    ],
                    'sre': [
                        "Memory alert: {memory_usage_percent}% utilized, {oom_kills} OOM kills",
                        "System swapping {swap_usage_gb}GB - performance degradation detected",
                        "Critical: Buffer cache efficiency {buffer_cache_hit}% (memory pressure)",
                        "AWS monitoring: Memory {memory_usage_percent}%, swap {swap_usage_gb}GB",
                        "Resource exhaustion: {oom_kills} processes killed due to memory limits"
                    ],
                    'data_engineer': [
                        "ETL job killed: OOM at {memory_usage_percent}% memory usage",
                        "Data processing failed - {oom_kills} tasks killed, {swap_usage_gb}GB swap",
                        "Pipeline memory issues: work_mem only {work_mem_mb}MB available",
                        "Batch job performance degraded - cache hit {buffer_cache_hit}%",
                        "Memory pressure: {memory_usage_percent}% used, jobs failing"
                    ]
                }
            },
            {
                'id': 'replication_lag',
                'category': 'replication',
                'base_metrics': {
                    'lag_seconds_range': (5, 300),
                    'lag_bytes_range': (1000000, 100000000),
                    'replica_count': (1, 5),
                    'wal_size_mb_range': (100, 5000),
                    'network_latency_ms_range': (1, 50)
                },
                'variations': {
                    'dba': [
                        "Replication lag: {lag_seconds}s behind primary, {lag_bytes} bytes pending",
                        "WARNING: Replica {replica_count} lagging {lag_seconds}s, WAL {wal_size_mb}MB",
                        "Streaming replication delayed {lag_seconds}s due to {network_latency_ms}ms network latency",
                        "Standby lag alert: {lag_bytes} bytes behind, {wal_size_mb}MB WAL accumulated",
                        "Read replica out of sync by {lag_seconds} seconds"
                    ],
                    'developer': [
                        "Read-after-write inconsistency - replica {lag_seconds}s behind",
                        "Stale data on read replicas - {lag_seconds}s replication delay",
                        "Data consistency issue: replicas lagging by {lag_bytes} bytes",
                        "Application seeing outdated data - {lag_seconds}s replication lag",
                        "Read replica delay causing user-visible inconsistencies"
                    ],
                    'sre': [
                        "Replication monitoring: {lag_seconds}s lag on {replica_count} replicas",
                        "Alert: WAL accumulation {wal_size_mb}MB, lag {lag_seconds}s",
                        "Network issue causing {network_latency_ms}ms latency, {lag_seconds}s replica lag",
                        "Critical: Replication lag exceeding SLA ({lag_seconds}s)",
                        "Replica health check: {lag_bytes} bytes behind primary"
                    ],
                    'data_engineer': [
                        "Analytics queries on stale data - replica {lag_seconds}s behind",
                        "Report inconsistencies due to {lag_seconds}s replication lag",
                        "Data freshness issue: {lag_bytes} bytes replication backlog",
                        "ETL reading outdated data from replica lagging {lag_seconds}s",
                        "Pipeline data quality affected by {lag_seconds}s replica delay"
                    ]
                }
            },
            {
                'id': 'autovacuum_issues',
                'category': 'maintenance',
                'base_metrics': {
                    'dead_tuples_range': (1000000, 100000000),
                    'table_bloat_percent_range': (20, 80),
                    'vacuum_duration_min_range': (30, 360),
                    'tables_affected': ['events', 'sessions', 'logs', 'metrics', 'orders'],
                    'io_usage_percent_range': (50, 95)
                },
                'variations': {
                    'dba': [
                        "Aggressive vacuum on '{tables_affected}' - {dead_tuples} dead tuples, {table_bloat_percent}% bloat",
                        "Autovacuum running {vacuum_duration_min}min on '{tables_affected}', IO at {io_usage_percent}%",
                        "Table bloat: '{tables_affected}' at {table_bloat_percent}% with {dead_tuples} dead rows",
                        "Long-running vacuum: {vacuum_duration_min}min, blocking DDL operations",
                        "Vacuum freeze on '{tables_affected}' - {io_usage_percent}% IO utilization"
                    ],
                    'developer': [
                        "Application slowdown during {vacuum_duration_min}min vacuum on '{tables_affected}'",
                        "Query performance degraded - table '{tables_affected}' {table_bloat_percent}% bloated",
                        "Database maintenance causing {io_usage_percent}% IO usage",
                        "User queries slow - autovacuum processing {dead_tuples} dead tuples",
                        "Service degradation during vacuum of '{tables_affected}' table"
                    ],
                    'sre': [
                        "IO spike: {io_usage_percent}% during vacuum of '{tables_affected}'",
                        "Performance impact: {vacuum_duration_min}min vacuum operation running",
                        "Disk usage alert: '{tables_affected}' table {table_bloat_percent}% bloated",
                        "Monitoring: Autovacuum causing {io_usage_percent}% IO saturation",
                        "Maintenance window exceeded - vacuum still running after {vacuum_duration_min}min"
                    ],
                    'data_engineer': [
                        "ETL performance impacted by vacuum on '{tables_affected}'",
                        "Data load competing with {vacuum_duration_min}min vacuum operation",
                        "Table '{tables_affected}' bloat ({table_bloat_percent}%) affecting query performance",
                        "Pipeline slowdown - {io_usage_percent}% IO used by maintenance",
                        "Batch job delayed by autovacuum processing {dead_tuples} rows"
                    ]
                }
            },
            {
                'id': 'disk_space_critical',
                'category': 'storage',
                'base_metrics': {
                    'disk_usage_percent_range': (85, 99),
                    'free_space_gb_range': (1, 50),
                    'growth_rate_gb_per_day_range': (10, 100),
                    'days_until_full_range': (1, 7),
                    'wal_size_gb_range': (10, 100)
                },
                'variations': {
                    'dba': [
                        "CRITICAL: Disk {disk_usage_percent}% full, only {free_space_gb}GB remaining",
                        "Storage alert: Growing {growth_rate_gb_per_day}GB/day, full in {days_until_full} days",
                        "WAL accumulation: {wal_size_gb}GB of logs, disk {disk_usage_percent}% utilized",
                        "Emergency: {free_space_gb}GB free, database will halt in {days_until_full} days",
                        "Disk space critical: {disk_usage_percent}% used, growth rate {growth_rate_gb_per_day}GB/day"
                    ],
                    'developer': [
                        "Database storage {disk_usage_percent}% full - writes may fail soon",
                        "Application at risk: only {free_space_gb}GB disk space remaining",
                        "Storage exhaustion in {days_until_full} days at current growth rate",
                        "Critical: Database disk {disk_usage_percent}% full, operations impacted",
                        "Write failures imminent - {free_space_gb}GB free space left"
                    ],
                    'sre': [
                        "Disk space alarm: {disk_usage_percent}% used, {free_space_gb}GB free",
                        "Projection: Storage full in {days_until_full} days ({growth_rate_gb_per_day}GB/day growth)",
                        "Critical infrastructure alert: WAL using {wal_size_gb}GB of disk",
                        "Emergency response needed: {disk_usage_percent}% disk utilization",
                        "Storage capacity: {days_until_full} days until exhaustion"
                    ],
                    'data_engineer': [
                        "ETL jobs at risk - disk {disk_usage_percent}% full",
                        "Data pipeline may fail: only {free_space_gb}GB space available",
                        "Batch processing consuming {growth_rate_gb_per_day}GB/day",
                        "Storage crisis: {days_until_full} days until pipeline failure",
                        "Data retention issue: {wal_size_gb}GB logs, {disk_usage_percent}% disk used"
                    ]
                }
            }
        ]
    
    def _generate_metric_value(self, range_tuple: Tuple[float, float]) -> float:
        """Generate a value within the specified range"""
        return random.uniform(range_tuple[0], range_tuple[1])
    
    def _create_comprehensive_metrics(self, archetype: Dict) -> Dict:
        """Create comprehensive metrics ensuring all template variables are available"""
        metrics = {}
        base_metrics = archetype['base_metrics']
        
        # Process base metrics
        for key, value in base_metrics.items():
            if isinstance(value, tuple):
                # Handle range values
                clean_key = key.replace('_range', '')
                metrics[clean_key] = self._generate_metric_value(value)
            elif isinstance(value, list):
                # Handle choice lists
                metrics[key] = random.choice(value)
            else:
                # Handle static values
                metrics[key] = value
        
        # Add commonly used derived metrics
        if 'active_connections' in metrics and 'max_connections' not in metrics:
            metrics['max_connections'] = 1000
        
        if 'active_connections' in metrics:
            metrics['active'] = int(metrics['active_connections'])
            
        if 'wait_time_ms' in metrics:
            metrics['wait_ms'] = int(metrics['wait_time_ms'])
            
        if 'spike_duration_min' in metrics:
            metrics['spike_duration_min'] = round(metrics['spike_duration_min'], 1)
            
        if 'threshold' in metrics:
            metrics['threshold'] = int(metrics['threshold'])
        elif 'active_connections' in metrics and 'max_connections' in metrics:
            metrics['threshold'] = int((metrics['active_connections'] / metrics['max_connections']) * 100)
            
        if 'idle_connections' in metrics:
            metrics['idle_connections'] = int(metrics['idle_connections'])
            
        if 'leak_rate_per_hour' in metrics:
            metrics['leak_rate_per_hour'] = round(metrics['leak_rate_per_hour'], 1)
            
        if 'leak_duration_hours' in metrics:
            metrics['leak_duration_hours'] = int(metrics['leak_duration_hours'])
            
        if 'memory_usage_mb' in metrics:
            metrics['memory_usage_mb'] = int(metrics['memory_usage_mb'])
            
        if 'rows_scanned' in metrics:
            metrics['rows_scanned'] = int(metrics['rows_scanned'])
            
        if 'slowdown_factor' in metrics:
            metrics['slowdown_factor'] = int(metrics['slowdown_factor'])
        elif 'query_time_before_ms' in metrics and 'query_time_after_ms' in metrics:
            metrics['slowdown_factor'] = int(metrics['query_time_after_ms'] / max(1, metrics['query_time_before_ms']))
            
        if 'cpu_usage' in metrics:
            metrics['cpu_usage'] = int(metrics['cpu_usage'])
            
        if 'deadlocks_per_minute' in metrics:
            metrics['deadlocks_per_minute'] = int(metrics['deadlocks_per_minute'])
            
        if 'blocked_queries' in metrics:
            metrics['blocked_queries'] = int(metrics['blocked_queries'])
            
        if 'lock_wait_ms' in metrics:
            metrics['lock_wait_ms'] = int(metrics['lock_wait_ms'])
            
        if 'cascade_duration_min' in metrics:
            metrics['cascade_duration_min'] = int(metrics['cascade_duration_min'])
            
        if 'transaction_rollback' in metrics:
            metrics['transaction_rollback'] = int(metrics['transaction_rollback'])
            
        # Add standard metrics that are always needed
        metrics['wait_count'] = random.randint(5, 50)
        
        # Memory metrics
        if 'memory_usage_percent' in metrics:
            metrics['memory_usage_percent'] = int(metrics['memory_usage_percent'])
        if 'oom_kills' in metrics:
            metrics['oom_kills'] = int(metrics['oom_kills'])
        if 'swap_usage_gb' in metrics:
            metrics['swap_usage_gb'] = round(metrics['swap_usage_gb'], 1)
        if 'buffer_cache_hit' in metrics:
            metrics['buffer_cache_hit'] = int(metrics['buffer_cache_hit'])
        if 'work_mem_mb' in metrics:
            metrics['work_mem_mb'] = int(metrics['work_mem_mb'])
            
        # Replication metrics
        if 'lag_seconds' in metrics:
            metrics['lag_seconds'] = int(metrics['lag_seconds'])
        if 'lag_bytes' in metrics:
            metrics['lag_bytes'] = int(metrics['lag_bytes'])
        if 'replica_count' in metrics:
            metrics['replica_count'] = int(metrics['replica_count'])
        if 'wal_size_mb' in metrics:
            metrics['wal_size_mb'] = int(metrics['wal_size_mb'])
        if 'network_latency_ms' in metrics:
            metrics['network_latency_ms'] = int(metrics['network_latency_ms'])
            
        # Vacuum metrics
        if 'dead_tuples' in metrics:
            metrics['dead_tuples'] = int(metrics['dead_tuples'])
        if 'table_bloat_percent' in metrics:
            metrics['table_bloat_percent'] = int(metrics['table_bloat_percent'])
        if 'vacuum_duration_min' in metrics:
            metrics['vacuum_duration_min'] = int(metrics['vacuum_duration_min'])
        if 'io_usage_percent' in metrics:
            metrics['io_usage_percent'] = int(metrics['io_usage_percent'])
            
        # Disk metrics
        if 'disk_usage_percent' in metrics:
            metrics['disk_usage_percent'] = int(metrics['disk_usage_percent'])
        if 'free_space_gb' in metrics:
            metrics['free_space_gb'] = int(metrics['free_space_gb'])
        if 'growth_rate_gb_per_day' in metrics:
            metrics['growth_rate_gb_per_day'] = int(metrics['growth_rate_gb_per_day'])
        if 'days_until_full' in metrics:
            metrics['days_until_full'] = int(metrics['days_until_full'])
        if 'wal_size_gb' in metrics:
            metrics['wal_size_gb'] = int(metrics['wal_size_gb'])
        
        return metrics
    
    def _create_incident_cluster(self, archetype: Dict, incident_time: datetime) -> List[Dict]:
        """Create a cluster of related log entries for a single incident"""
        incident_id = uuid.uuid4().hex[:8]
        cluster = []
        
        # Generate comprehensive metrics for this incident
        metrics = self._create_comprehensive_metrics(archetype)
        
        # Add unique identifiers and values
        self.variation_counter += 1
        metrics.update({
            'incident_id': incident_id,
            'timestamp_short': (incident_time + timedelta(seconds=random.randint(0, 59))).strftime('%H:%M:%S')
        })
        
        # Determine severity
        severity_weights = {
            'connection': {'critical': 0.3, 'warning': 0.4, 'info': 0.3},
            'performance': {'critical': 0.2, 'warning': 0.5, 'info': 0.3},
            'locking': {'critical': 0.3, 'warning': 0.4, 'info': 0.3},
            'resource': {'critical': 0.4, 'warning': 0.4, 'info': 0.2},
            'replication': {'critical': 0.2, 'warning': 0.5, 'info': 0.3},
            'maintenance': {'critical': 0.1, 'warning': 0.5, 'info': 0.4},
            'storage': {'critical': 0.5, 'warning': 0.3, 'info': 0.2}
        }
        
        category = archetype.get('category', 'default')
        weights = severity_weights.get(category, {'critical': 0.2, 'warning': 0.4, 'info': 0.4})
        base_severity = random.choices(
            list(weights.keys()),
            weights=list(weights.values())
        )[0]
        
        self.severity_counter[base_severity] += 1
        
        # Select personas for this incident
        personas = ['dba', 'developer', 'sre', 'data_engineer']
        num_personas = random.choices([2, 3, 4], weights=[0.3, 0.5, 0.2])[0]
        observing_personas = random.sample(personas, k=num_personas)
        
        for persona in observing_personas:
            if persona in archetype['variations']:
                patterns = archetype['variations'][persona]
                
                # Use variation to select different patterns
                pattern_index = (self.variation_counter + hash(persona)) % len(patterns)
                pattern = patterns[pattern_index]
                
                # Fill pattern with metrics
                content = self._fill_pattern(pattern, metrics)
                
                # Check for diversity
                content_hash = hashlib.md5(content.encode()).hexdigest()[:8]
                if content_hash in self.used_content_hashes:
                    # Try a different pattern
                    pattern = random.choice(patterns)
                    content = self._fill_pattern(pattern, metrics)
                    content_hash = hashlib.md5(content.encode()).hexdigest()[:8]
                
                self.used_content_hashes.add(content_hash)
                
                # Vary severity slightly
                if persona == 'developer' and base_severity == 'critical':
                    severity = random.choice(['critical', 'warning'])
                elif persona == 'data_engineer' and base_severity == 'info':
                    severity = random.choice(['info', 'warning'])
                else:
                    severity = base_severity
                
                # Add time variance
                time_offset = random.randint(-5, 15)
                observation_time = incident_time + timedelta(minutes=time_offset)
                
                doc_id = f"{incident_id}_{persona}_{uuid.uuid4().hex[:8]}"
                
                log_entry = {
                    'doc_id': doc_id,
                    'content': content,
                    'mcp_metadata': {
                        'persona': persona,
                        'timestamp': observation_time.isoformat() + 'Z',
                        'severity': severity,
                        'incident_id': incident_id,
                        'incident_type': archetype['id'],
                        'incident_category': archetype.get('category', 'general'),
                        'metrics': self._extract_relevant_metrics(metrics, persona),
                        'task_context': self._get_task_context(severity, archetype.get('category')),
                        'related_systems': self._get_related_systems(archetype['id']),
                        'temporal_marker': self._get_temporal_marker(observation_time.hour)
                    }
                }
                
                cluster.append(log_entry)
        
        return cluster
    
    def _fill_pattern(self, pattern: str, metrics: Dict) -> str:
        """Fill pattern with actual values, ensuring all variables are replaced"""
        
        def replacer(match):
            key = match.group(1)
            # Handle format specifiers
            if ':' in key:
                key, fmt = key.split(':', 1)
            else:
                fmt = None
                
            if key in metrics:
                value = metrics[key]
                if fmt:
                    # Apply format
                    if fmt.endswith('f'):
                        decimals = int(fmt[:-1].replace('.', ''))
                        return f"{float(value):.{decimals}f}"
                    elif fmt == '.0f':
                        return str(int(value))
                    elif fmt == '.1f':
                        return f"{float(value):.1f}"
                else:
                    # Default formatting
                    if isinstance(value, float):
                        if value >= 100:
                            return str(int(value))
                        else:
                            return f"{value:.1f}"
                    return str(value)
            
            # If key not found, log and return placeholder
            return f"[{key}]"
        
        # Replace all {variable} patterns
        result = re.sub(r'\{([^}]+)\}', replacer, pattern)
        
        # Verify no unreplaced variables remain
        if '{' in result and '}' in result:
            # Try to fix common missing variables
            result = result.replace('{', '[').replace('}', ']')
        
        return result
    
    def _extract_relevant_metrics(self, metrics: Dict, persona: str) -> Dict:
        """Extract metrics relevant to a specific persona"""
        relevant = {}
        
        # Select 3-5 relevant metrics
        num_metrics = random.randint(3, 5)
        available_keys = [k for k in metrics.keys() 
                         if not k.endswith('_id') and not k.endswith('_name')
                         and not k == 'incident_id' and not k == 'timestamp_short']
        
        if len(available_keys) > num_metrics:
            selected_keys = random.sample(available_keys, num_metrics)
        else:
            selected_keys = available_keys
            
        for key in selected_keys:
            relevant[key] = metrics[key]
        
        return relevant
    
    def _get_task_context(self, severity: str, category: str) -> str:
        """Get task context based on severity and category"""
        if severity == 'critical':
            return 'incident_response'
        elif severity == 'warning':
            return 'monitoring'
        else:
            return 'routine_check'
    
    def _get_related_systems(self, incident_type: str) -> List[str]:
        """Get systems related to an incident type"""
        base = ['postgresql', 'monitoring']
        if 'connection' in incident_type:
            return base + ['connection_pool', 'pgbouncer']
        elif 'performance' in incident_type or 'query' in incident_type:
            return base + ['query_optimizer', 'indexes']
        elif 'replication' in incident_type:
            return base + ['wal_shipping', 'streaming_replication']
        elif 'memory' in incident_type:
            return base + ['memory_manager', 'oom_killer']
        else:
            aws = random.sample(['rds', 'cloudwatch', 'ec2', 'aurora'], k=2)
            return base + aws
    
    def _get_temporal_marker(self, hour: int) -> str:
        """Get temporal marker based on hour"""
        if 0 <= hour < 6:
            return 'overnight'
        elif 6 <= hour < 12:
            return 'morning'
        elif 12 <= hour < 18:
            return 'afternoon'
        else:
            return 'evening'
    
    def _add_info_logs(self, num_logs: int) -> List[Dict]:
        """Add diverse normal operational info logs"""
        info_logs = []
        
        info_patterns = [
            "Database health check passed - response time {response_time}ms",
            "Connection pool stable at {connections} connections ({percent}% utilization)",
            "Query cache hit ratio: {ratio}% over last {period} minutes",
            "Checkpoint completed: {buffers} buffers written in {duration} seconds",
            "Autovacuum completed on table '{table}' - {rows} rows processed",
            "Index '{index}' rebuild completed - {size}MB size reduction",
            "Backup successful: {backup_size}GB completed in {backup_time} minutes",
            "Replication healthy - all {replicas} replicas in sync",
            "WAL archiving on schedule - {wal_count} segments archived",
            "Buffer cache warmed - {cache_size}GB loaded into memory",
            "SSL certificate valid for {cert_days} more days",
            "Monitoring agent heartbeat received - all systems operational",
            "Statistics updated for {tables_updated} tables",
            "Connection recycling: {recycled} connections refreshed",
            "Query performance within SLA - P99 latency {p99_latency}ms",
            "Disk I/O normal - {read_iops} read IOPS, {write_iops} write IOPS",
            "CPU utilization stable at {cpu_percent}%",
            "Memory usage normal - {memory_gb}GB of {total_memory_gb}GB used",
            "Network latency optimal - {network_ms}ms average RTT",
            "All scheduled maintenance tasks completed successfully"
        ]
        
        personas = ['dba', 'developer', 'sre', 'data_engineer']
        
        for i in range(num_logs):
            persona = random.choice(personas)
            pattern = random.choice(info_patterns)
            
            # Create metrics for info logs
            info_metrics = {
                'response_time': random.randint(10, 200),
                'connections': random.randint(50, 500),
                'percent': random.randint(10, 80),
                'ratio': random.randint(85, 99),
                'period': random.randint(5, 60),
                'buffers': random.randint(1000, 50000),
                'duration': round(random.uniform(0.5, 10), 1),
                'table': random.choice(['users', 'orders', 'products', 'events', 'sessions']),
                'rows': random.randint(10000, 1000000),
                'index': f"idx_{random.choice(['users', 'orders', 'products'])}_{random.choice(['id', 'date', 'status'])}",
                'size': random.randint(10, 500),
                'backup_size': round(random.uniform(1, 100), 1),
                'backup_time': random.randint(5, 60),
                'replicas': random.randint(2, 5),
                'wal_count': random.randint(10, 100),
                'cache_size': round(random.uniform(1, 32), 1),
                'cert_days': random.randint(30, 365),
                'tables_updated': random.randint(5, 50),
                'recycled': random.randint(10, 100),
                'p99_latency': random.randint(50, 500),
                'read_iops': random.randint(1000, 10000),
                'write_iops': random.randint(500, 5000),
                'cpu_percent': random.randint(20, 60),
                'memory_gb': round(random.uniform(10, 100), 1),
                'total_memory_gb': 128,
                'network_ms': round(random.uniform(0.5, 5), 1)
            }
            
            content = self._fill_pattern(pattern, info_metrics)
            
            # Generate timestamp
            days_offset = random.randint(-180, 180)
            hours_offset = random.randint(0, 23)
            timestamp = self.black_friday_2024 + timedelta(
                days=days_offset,
                hours=hours_offset,
                minutes=random.randint(0, 59),
                seconds=random.randint(0, 59)
            )
            
            doc_id = f"info_{uuid.uuid4().hex[:16]}"
            
            info_logs.append({
                'doc_id': doc_id,
                'content': content,
                'mcp_metadata': {
                    'persona': persona,
                    'timestamp': timestamp.isoformat() + 'Z',
                    'severity': 'info',
                    'task_context': 'monitoring',
                    'metrics': {},
                    'related_systems': ['postgresql', 'monitoring'],
                    'temporal_marker': self._get_temporal_marker(timestamp.hour)
                }
            })
        
        return info_logs
    
    def generate_dataset(self) -> List[Dict]:
        """Generate the complete dataset"""
        all_logs = []
        
        print(f"Generating ~{self.num_incidents} unique incidents...")
        
        # Use all archetypes evenly
        archetype_usage = {arch['id']: 0 for arch in self.incident_archetypes}
        
        for i in range(self.num_incidents):
            # Select archetype evenly
            min_used = min(archetype_usage.values())
            available_archetypes = [arch for arch in self.incident_archetypes 
                                   if archetype_usage[arch['id']] == min_used]
            archetype = random.choice(available_archetypes)
            archetype_usage[archetype['id']] += 1
            
            # Generate timestamp
            if i < self.num_incidents * 0.3:
                # 30% around Black Friday
                days_offset = random.randint(-7, 7)
                hours_offset = random.randint(6, 22)
            else:
                # 70% throughout the year
                days_offset = random.randint(-180, 180)
                hours_offset = random.randint(0, 23)
            
            incident_time = self.black_friday_2024 + timedelta(
                days=days_offset,
                hours=hours_offset,
                minutes=random.randint(0, 59)
            )
            
            # Generate incident cluster
            cluster = self._create_incident_cluster(archetype, incident_time)
            all_logs.extend(cluster)
            
            if (i + 1) % 100 == 0:
                print(f"  Generated {i + 1}/{self.num_incidents} incidents...")
        
        # Add info logs to reach target
        current_count = len(all_logs)
        info_logs_needed = max(0, self.target_logs - current_count)
        
        if info_logs_needed > 0:
            print(f"Adding {info_logs_needed} info logs...")
            info_logs = self._add_info_logs(info_logs_needed)
            all_logs.extend(info_logs)
        
        # Sort by timestamp
        all_logs.sort(key=lambda x: x['mcp_metadata']['timestamp'])
        
        print(f"Dataset generation complete: {len(all_logs)} total logs")
        print(f"  Unique content patterns: {len(self.used_content_hashes)}")
        
        return all_logs


def main():
    """Generate and save the dataset"""
    
    print("🚀 Generating Fixed Dataset for DAT409 Workshop v4.0")
    print("=" * 60)
    
    # Generate dataset
    generator = FixedIncidentGenerator(target_logs=1500)
    logs = generator.generate_dataset()
    
    # Save to file
    output_file = 'incident_logs_v2.json'
    with open(output_file, 'w') as f:
        json.dump(logs, f, indent=2)
    
    # Calculate statistics
    stats = {
        'total': len(logs),
        'by_severity': {},
        'by_persona': {},
        'by_incident_type': {},
        'unique_incidents': set(),
        'unique_content': set()
    }
    
    for log in logs:
        metadata = log['mcp_metadata']
        
        severity = metadata['severity']
        stats['by_severity'][severity] = stats['by_severity'].get(severity, 0) + 1
        
        persona = metadata['persona']
        stats['by_persona'][persona] = stats['by_persona'].get(persona, 0) + 1
        
        incident_type = metadata.get('incident_type', 'info')
        stats['by_incident_type'][incident_type] = stats['by_incident_type'].get(incident_type, 0) + 1
        
        if 'incident_id' in metadata:
            stats['unique_incidents'].add(metadata['incident_id'])
            
        # Check content uniqueness
        content_hash = hashlib.md5(log['content'].encode()).hexdigest()[:8]
        stats['unique_content'].add(content_hash)
    
    # Print summary
    print(f"\n📊 Dataset Statistics:")
    print(f"  Total logs: {stats['total']:,}")
    print(f"  Unique incidents: {len(stats['unique_incidents']):,}")
    print(f"  Unique content patterns: {len(stats['unique_content']):,}")
    
    print("\n📈 By Severity:")
    for severity in ['critical', 'warning', 'info']:
        count = stats['by_severity'].get(severity, 0)
        percentage = (100 * count / stats['total']) if stats['total'] > 0 else 0
        print(f"  {severity:8}: {count:5,} ({percentage:5.1f}%)")
    
    print("\n👥 By Persona:")
    for persona in sorted(stats['by_persona'].keys()):
        count = stats['by_persona'][persona]
        percentage = (100 * count / stats['total']) if stats['total'] > 0 else 0
        print(f"  {persona:15}: {count:5,} ({percentage:5.1f}%)")
    
    # Verify template replacement
    print("\n✅ Template Variable Verification:")
    unresolved_count = 0
    sample_unresolved = []
    for log in logs[:100]:  # Check first 100 logs
        if '[' in log['content'] and ']' in log['content']:
            unresolved_count += 1
            if len(sample_unresolved) < 3:
                sample_unresolved.append(log['content'][:100])
    
    if unresolved_count > 0:
        print(f"  ⚠️ Found {unresolved_count} logs with potential unresolved variables")
        for sample in sample_unresolved:
            print(f"    {sample}...")
    else:
        print(f"  ✅ All template variables properly resolved!")
    
    print(f"\n✅ Saved to: {output_file}")
    print(f"🎯 Successfully generated {len(logs)} diverse logs with fixed template variables!")


if __name__ == "__main__":
    main()