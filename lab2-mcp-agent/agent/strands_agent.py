#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Strands Agent with Custom Tools
Using @tool decorator pattern for Black Friday analysis
"""

import os
import sys
from typing import List, Dict, Optional
from datetime import datetime, timedelta
from pathlib import Path
import json
import boto3
import psycopg
from strands import Agent, tool

# Load environment variables
def load_env():
    locations = [Path('.env'), Path('../setup/.env'), Path('../../.env')]
    for loc in locations:
        if loc.exists():
            try:
                from dotenv import load_dotenv
                load_dotenv(loc)
                print(f"Loaded .env from {loc}")
                return True
            except ImportError:
                pass
    return False

load_env()

# Database configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'apgpg-pgvector.cluster-chygmprofdnr.us-west-2.rds.amazonaws.com'),
    'port': os.getenv('DB_PORT', '5432'),
    'dbname': os.getenv('DB_NAME', 'postgres'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD')
}

# RDS Data API configuration
DATA_API_CONFIG = {
    'resource_arn': 'arn:aws:rds:us-west-2:619763002613:cluster:apgpg-pgvector',
    'secret_arn': 'arn:aws:secretsmanager:us-west-2:619763002613:secret:apgpg-pgvector-secret-l847Vi',
    'database': 'postgres',
    'region': 'us-west-2'
}

# ============================================================================
# CUSTOM TOOLS USING @tool DECORATOR
# ============================================================================

@tool
def query_incidents(severity: str = None, date_from: str = None, date_to: str = None, limit: int = 10) -> str:
    """
    Query incident logs from Aurora PostgreSQL database.
    
    Args:
        severity: Filter by severity level (critical, warning, info)
        date_from: Start date in YYYY-MM-DD format
        date_to: End date in YYYY-MM-DD format  
        limit: Maximum number of results to return
        
    Returns:
        Formatted string with incident details
    """
    try:
        conn_string = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
        
        # Build query
        query = "SELECT doc_id, content, persona, severity, timestamp FROM incident_logs WHERE 1=1"
        params = []
        
        if severity:
            query += " AND severity = %s"
            params.append(severity)
        if date_from:
            query += " AND timestamp >= %s"
            params.append(date_from)
        if date_to:
            query += " AND timestamp <= %s"
            params.append(date_to)
            
        query += f" ORDER BY timestamp DESC LIMIT {limit}"
        
        with psycopg.connect(conn_string) as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                results = cur.fetchall()
                
        if not results:
            return "No incidents found matching the criteria."
            
        output = f"Found {len(results)} incidents:\n\n"
        for row in results:
            doc_id, content, persona, severity, timestamp = row
            output += f"[{timestamp}] {severity.upper()} - {persona}\n"
            output += f"  {content[:150]}...\n\n"
            
        return output
        
    except Exception as e:
        return f"Database query failed: {str(e)}"

@tool
def analyze_black_friday_patterns(year: int = 2024) -> str:
    """
    Analyze incident patterns specifically for Black Friday period.
    
    Args:
        year: Year to analyze (default 2024)
        
    Returns:
        Analysis of Black Friday incident patterns
    """
    try:
        # Black Friday is the last Friday of November
        # For 2024, that's November 29
        bf_date = f"{year}-11-29" if year == 2024 else f"{year}-11-24"
        
        conn_string = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
        
        with psycopg.connect(conn_string) as conn:
            with conn.cursor() as cur:
                # Get Black Friday week incidents
                cur.execute("""
                    SELECT severity, COUNT(*) as count
                    FROM incident_logs
                    WHERE timestamp BETWEEN %s::date - INTERVAL '3 days' 
                          AND %s::date + INTERVAL '3 days'
                    GROUP BY severity
                    ORDER BY count DESC
                """, (bf_date, bf_date))
                
                severity_dist = cur.fetchall()
                
                # Get top incident types
                cur.execute("""
                    SELECT 
                        CASE 
                            WHEN content ILIKE '%connection%' THEN 'Connection Issues'
                            WHEN content ILIKE '%memory%' THEN 'Memory Issues'
                            WHEN content ILIKE '%timeout%' THEN 'Timeout Issues'
                            WHEN content ILIKE '%cpu%' THEN 'CPU Issues'
                            ELSE 'Other'
                        END as incident_type,
                        COUNT(*) as count
                    FROM incident_logs
                    WHERE timestamp BETWEEN %s::date - INTERVAL '3 days' 
                          AND %s::date + INTERVAL '3 days'
                    GROUP BY incident_type
                    ORDER BY count DESC
                """, (bf_date, bf_date))
                
                incident_types = cur.fetchall()
                
        output = f"Black Friday {year} Analysis:\n"
        output += "=" * 50 + "\n\n"
        
        if severity_dist:
            output += "Severity Distribution:\n"
            for severity, count in severity_dist:
                output += f"  {severity}: {count} incidents\n"
        else:
            output += "No incidents found for Black Friday period\n"
            
        if incident_types:
            output += "\nTop Incident Types:\n"
            for itype, count in incident_types:
                output += f"  {itype}: {count} incidents\n"
                
        return output
        
    except Exception as e:
        return f"Pattern analysis failed: {str(e)}"

@tool
def generate_preparedness_checklist(team: str = "all") -> str:
    """
    Generate a Black Friday preparedness checklist based on historical data.
    
    Args:
        team: Specific team (dba, developer, sre, data_engineer) or 'all'
        
    Returns:
        Customized preparedness checklist
    """
    checklists = {
        'dba': [
            "✓ Increase max_connections from 500 to 1200",
            "✓ Schedule VACUUM ANALYZE 24 hours before Black Friday",
            "✓ Enable statement timeout at 30 seconds",
            "✓ Increase work_mem to 256MB for large queries",
            "✓ Set up pgBouncer for connection pooling",
            "✓ Create read replica for analytics queries",
            "✓ Monitor table bloat and dead tuples"
        ],
        'developer': [
            "✓ Implement connection retry logic with exponential backoff",
            "✓ Add circuit breakers for database calls",
            "✓ Cache frequently accessed data in Redis",
            "✓ Implement query timeout handling",
            "✓ Add database connection health checks",
            "✓ Review and optimize slow queries",
            "✓ Implement graceful degradation for non-critical features"
        ],
        'sre': [
            "✓ Set up alerts for connection pool > 80% utilization",
            "✓ Configure CloudWatch alarms for CPU > 75%",
            "✓ Create runbooks for common incident types",
            "✓ Set up automated scaling policies",
            "✓ Configure PagerDuty escalation policies",
            "✓ Test disaster recovery procedures",
            "✓ Set up distributed tracing"
        ],
        'data_engineer': [
            "✓ Pause non-critical ETL jobs during peak hours",
            "✓ Pre-aggregate reports before Black Friday",
            "✓ Optimize batch job scheduling",
            "✓ Set up data pipeline monitoring",
            "✓ Configure Airflow retry policies",
            "✓ Create data quality checks",
            "✓ Set up incremental data loads"
        ]
    }
    
    if team == 'all':
        output = "Black Friday Preparedness Checklist (All Teams):\n"
        output += "=" * 50 + "\n\n"
        for team_name, items in checklists.items():
            output += f"{team_name.upper()} Team:\n"
            for item in items[:3]:  # Show top 3 for each team
                output += f"  {item}\n"
            output += "\n"
    else:
        team_items = checklists.get(team, [])
        if team_items:
            output = f"Black Friday Preparedness Checklist ({team.upper()} Team):\n"
            output += "=" * 50 + "\n"
            for item in team_items:
                output += f"{item}\n"
        else:
            output = f"Unknown team: {team}. Available teams: dba, developer, sre, data_engineer"
            
    return output

@tool
def predict_resource_needs(metric: str = "all") -> str:
    """
    Predict resource requirements for Black Friday based on historical patterns.
    
    Args:
        metric: Specific metric (connections, cpu, memory, iops) or 'all'
        
    Returns:
        Resource predictions and recommendations
    """
    predictions = {
        'connections': {
            'current': 500,
            'predicted_peak': 950,
            'recommended': 1200,
            'action': 'Increase max_connections to 1200 and implement connection pooling'
        },
        'cpu': {
            'current': 'db.r8g.2xlarge',
            'predicted_peak': '85% utilization',
            'recommended': 'db.r8g.4xlarge',
            'action': 'Upgrade instance class or add read replicas'
        },
        'memory': {
            'current': '64 GB',
            'predicted_peak': '92% utilization',
            'recommended': '128 GB',
            'action': 'Upgrade to instance with more RAM or optimize queries'
        },
        'iops': {
            'current': '10,000 IOPS',
            'predicted_peak': '45,000 IOPS',
            'recommended': '50,000 IOPS',
            'action': 'Enable io2 storage with 50,000 provisioned IOPS'
        }
    }
    
    if metric == 'all':
        output = "Black Friday Resource Predictions:\n"
        output += "=" * 50 + "\n\n"
        for metric_name, data in predictions.items():
            output += f"{metric_name.upper()}:\n"
            output += f"  Current: {data['current']}\n"
            output += f"  Predicted Peak: {data['predicted_peak']}\n"
            output += f"  Recommended: {data['recommended']}\n"
            output += f"  Action: {data['action']}\n\n"
    else:
        data = predictions.get(metric)
        if data:
            output = f"Resource Prediction - {metric.upper()}:\n"
            output += "=" * 50 + "\n"
            output += f"Current: {data['current']}\n"
            output += f"Predicted Peak: {data['predicted_peak']}\n"
            output += f"Recommended: {data['recommended']}\n"
            output += f"Action Required: {data['action']}\n"
        else:
            output = f"Unknown metric: {metric}. Available: connections, cpu, memory, iops"
            
    return output

@tool
def check_database_health() -> str:
    """
    Check current database health and readiness status.
    
    Returns:
        Database health check results
    """
    try:
        conn_string = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
        
        with psycopg.connect(conn_string) as conn:
            with conn.cursor() as cur:
                # Check basic connectivity
                cur.execute("SELECT version()")
                version = cur.fetchone()[0]
                
                # Check incident_logs table
                cur.execute("SELECT COUNT(*) FROM incident_logs")
                incident_count = cur.fetchone()[0]
                
                # Check extensions
                cur.execute("SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm')")
                extensions = [row[0] for row in cur.fetchall()]
                
                # Check current connections
                cur.execute("SELECT COUNT(*) FROM pg_stat_activity")
                connection_count = cur.fetchone()[0]
                
        output = "Database Health Check:\n"
        output += "=" * 50 + "\n"
        output += f"✓ Database: Connected\n"
        output += f"✓ Version: {version.split(',')[0]}\n"
        output += f"✓ Incident Records: {incident_count:,}\n"
        output += f"✓ Extensions: {', '.join(extensions) if extensions else 'None'}\n"
        output += f"✓ Active Connections: {connection_count}\n"
        output += "\nStatus: HEALTHY"
        
        return output
        
    except Exception as e:
        return f"Health check failed: {str(e)}\nStatus: UNHEALTHY"

# ============================================================================
# MAIN AGENT SETUP
# ============================================================================

def create_black_friday_agent():
    """Create a Strands agent with all Black Friday analysis tools"""
    
    # Create agent with all custom tools
    agent = Agent(
        tools=[
            query_incidents,
            analyze_black_friday_patterns,
            generate_preparedness_checklist,
            predict_resource_needs,
            check_database_health
        ],
        system_prompt="""You are a Black Friday Preparedness Expert helping teams prepare for peak traffic events.
        
        You have access to:
        - Historical incident data from Aurora PostgreSQL
        - Pattern analysis capabilities
        - Preparedness checklists for different teams
        - Resource prediction models
        - Database health monitoring
        
        When answering questions:
        1. Use the appropriate tools to gather data
        2. Provide specific, actionable recommendations
        3. Reference historical patterns and metrics
        4. Consider different team perspectives
        5. Focus on preventing incidents before they occur
        
        Black Friday 2024 is November 29th."""
    )
    
    return agent

def main():
    """Main entry point"""
    
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║   DAT409 Lab 2: Strands Agent with Custom Tools          ║
    ║   Black Friday Preparedness Analysis                     ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    # Create agent
    print("Initializing Black Friday Preparedness Agent...")
    agent = create_black_friday_agent()
    print("Agent ready with custom tools!\n")
    
    # Sample questions
    sample_questions = [
        "Check the database health status",
        "What were the critical incidents from last Black Friday?",
        "Generate a preparedness checklist for the DBA team",
        "Predict resource needs for connections and memory",
        "Analyze Black Friday patterns for 2024"
    ]
    
    print("Sample questions you can ask:")
    for i, q in enumerate(sample_questions, 1):
        print(f"  {i}. {q}")
    
    print("\nType 'exit' to quit, 'examples' for sample questions\n")
    
    # Interactive loop
    while True:
        try:
            user_input = input("\nYour question: ").strip()
            
            if user_input.lower() == 'exit':
                print("Goodbye!")
                break
            elif user_input.lower() == 'examples':
                print("\nSample questions:")
                for i, q in enumerate(sample_questions, 1):
                    print(f"  {i}. {q}")
                continue
            elif not user_input:
                continue
            
            # Process with agent
            print("\nAnalyzing...")
            response = agent(user_input)
            
            print("\nResponse:")
            print("-" * 50)
            print(response)
            print("-" * 50)
            
        except KeyboardInterrupt:
            print("\n\nSession interrupted. Goodbye!")
            break
        except Exception as e:
            print(f"Error: {str(e)}")

if __name__ == "__main__":
    main()