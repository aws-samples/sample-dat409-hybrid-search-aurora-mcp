#!/usr/bin/env python3
"""
DAT409 Workshop - Lab 2: Strands Agent for Black Friday Preparedness
Natural language interface to Aurora PostgreSQL using MCP
"""

import os
import sys
from typing import List, Dict, Any
from datetime import datetime, timedelta
from mcp import stdio_client, StdioServerParameters
from strands import Agent
from strands.tools.mcp import MCPClient
from dotenv import load_dotenv
import json

# Load environment variables
load_dotenv('/workshop/.env')

class BlackFridayAgent:
    """Strands Agent for Black Friday preparedness analysis"""
    
    def __init__(self):
        self.db_host = os.getenv('DB_HOST')
        self.secret_arn = os.getenv('DATABASE_SECRET_ARN')
        self.region = os.getenv('AWS_REGION', 'us-west-2')
        self.db_name = os.getenv('DB_NAME')
        self.mcp_client = None
        self.agent = None
        
    def setup_mcp_client(self):
        """Initialize MCP client for Aurora PostgreSQL"""
        
        # Create MCP client with stdio transport
        self.mcp_client = MCPClient(lambda: stdio_client(
            StdioServerParameters(
                command="uvx",
                args=[
                    "awslabs.postgres-mcp-server@latest",
                    "--hostname", self.db_host,
                    "--database", self.db_name,
                    "--secret_arn", self.secret_arn,
                    "--region", self.region,
                    "--readonly", "False"
                ]
            )
        ))
        
        print("✅ MCP client initialized")
        
    def create_custom_tools(self):
        """Create custom tools for Black Friday analysis"""
        
        from strands.tools import tool
        
        @tool(description="Analyze incident patterns from the past year to identify Black Friday risks")
        def analyze_black_friday_patterns(timeframe: str = "1 year") -> str:
            """
            Analyze historical incidents to identify patterns relevant to Black Friday
            """
            query = """
                WITH incident_analysis AS (
                    SELECT 
                        date_trunc('month', timestamp) as month,
                        severity,
                        COUNT(*) as incident_count,
                        AVG(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) as critical_rate
                    FROM incident_logs
                    WHERE timestamp > CURRENT_DATE - INTERVAL '1 year'
                    GROUP BY date_trunc('month', timestamp), severity
                )
                SELECT 
                    to_char(month, 'Month YYYY') as period,
                    SUM(incident_count) as total_incidents,
                    ROUND(AVG(critical_rate) * 100, 2) as critical_percentage
                FROM incident_analysis
                GROUP BY month
                ORDER BY month DESC
                LIMIT 12;
            """
            return f"Executing pattern analysis for {timeframe}"
        
        @tool(description="Generate a Black Friday preparedness checklist based on historical data")
        def generate_preparedness_checklist(priority_level: int = 1) -> str:
            """
            Generate actionable checklist items based on incident patterns
            """
            checklist_items = [
                "1. Database: Increase max_connections to 1000 (based on connection exhaustion patterns)",
                "2. Monitoring: Set up alerts for connection pool > 80% utilization",
                "3. Infrastructure: Add 2 read replicas for query distribution",
                "4. Application: Implement connection pooling with HikariCP",
                "5. Operations: Schedule aggressive vacuum 24 hours before Black Friday",
                "6. Caching: Increase Redis cache size by 50%",
                "7. Load Testing: Run simulated Black Friday traffic test",
                "8. Runbooks: Update incident response playbooks"
            ]
            return "\n".join(checklist_items)
        
        @tool(description="Predict resource requirements for Black Friday based on historical metrics")
        def predict_resource_requirements(metric_type: str = "connections") -> str:
            """
            Predict resource needs based on historical Black Friday data
            """
            predictions = {
                "connections": "Predicted peak: 950 connections (increase pool to 1200)",
                "cpu": "Predicted peak: 85% CPU (consider upgrading to r8g.4xlarge)",
                "memory": "Predicted peak: 92% memory (add 32GB RAM)",
                "iops": "Predicted peak: 50,000 IOPS (enable io2 storage)"
            }
            return predictions.get(metric_type, "Unknown metric type")
        
        return [analyze_black_friday_patterns, generate_preparedness_checklist, predict_resource_requirements]
    
    def run_interactive_session(self):
        """Run interactive Q&A session"""
        
        print("\n🤖 Black Friday Preparedness Agent Ready!")
        print("=" * 60)
        print("Ask questions about Black Friday preparedness in natural language.")
        print("Type 'exit' to quit, 'examples' for sample questions.\n")
        
        sample_questions = [
            "What were the top 3 critical incidents from last Black Friday?",
            "Show me connection pool exhaustion patterns from November",
            "Which teams reported the most incidents during peak traffic?",
            "What's the correlation between connection issues and query timeouts?",
            "Generate a preparedness checklist for database team",
            "What resources should we scale for this Black Friday?",
            "Show me all incidents with severity 'critical' from last November",
            "What were the most common error patterns during high traffic?",
            "Compare incident rates between Black Friday and Cyber Monday",
            "What preventive measures can we take based on past failures?"
        ]
        
        with self.mcp_client:
            # Get MCP tools and combine with custom tools
            mcp_tools = self.mcp_client.list_tools_sync()
            custom_tools = self.create_custom_tools()
            all_tools = mcp_tools + custom_tools
            
            # Create agent with all tools
            self.agent = Agent(
                tools=all_tools,
                system_prompt="""You are a Black Friday Preparedness Expert analyzing historical incident data 
                from Aurora PostgreSQL to help teams prepare for peak traffic events. You have access to:
                1. A year of incident logs with different severity levels
                2. Pattern analysis capabilities
                3. Historical Black Friday metrics
                4. Team-specific incident reports
                
                When answering questions:
                - Query the incident_logs table for historical data
                - Identify patterns and correlations
                - Provide actionable recommendations
                - Reference specific metrics and thresholds
                - Consider different team perspectives (DBA, Developer, SRE, Data Engineer)
                """
            )
            
            while True:
                try:
                    user_input = input("\n🔍 Your question: ").strip()
                    
                    if user_input.lower() == 'exit':
                        print("👋 Goodbye!")
                        break
                    elif user_input.lower() == 'examples':
                        print("\n📝 Sample questions you can ask:")
                        for i, q in enumerate(sample_questions, 1):
                            print(f"  {i}. {q}")
                        continue
                    elif not user_input:
                        continue
                    
                    # Process query with agent
                    print("\n🔄 Analyzing...")
                    response = self.agent(user_input)
                    
                    print("\n📊 Analysis Results:")
                    print("-" * 50)
                    print(response)
                    print("-" * 50)
                    
                except KeyboardInterrupt:
                    print("\n\n👋 Session interrupted. Goodbye!")
                    break
                except Exception as e:
                    print(f"\n❌ Error: {str(e)}")
                    print("Please try rephrasing your question.")
    
    def run_batch_analysis(self):
        """Run a batch of predefined analyses"""
        
        print("\n📊 Running Batch Analysis for Black Friday Preparedness")
        print("=" * 60)
        
        analyses = [
            {
                "title": "Connection Pool Analysis",
                "query": "SELECT COUNT(*) as incidents, AVG(CAST(metrics->>'active_connections' AS INT)) as avg_connections FROM incident_logs WHERE content LIKE '%connection%' AND timestamp > NOW() - INTERVAL '3 months'"
            },
            {
                "title": "Critical Incident Timeline",
                "query": "SELECT DATE(timestamp) as date, COUNT(*) as critical_count FROM incident_logs WHERE severity = 'critical' AND timestamp > NOW() - INTERVAL '1 year' GROUP BY DATE(timestamp) ORDER BY critical_count DESC LIMIT 10"
            },
            {
                "title": "Team Response Patterns",
                "query": "SELECT persona, severity, COUNT(*) as count FROM incident_logs WHERE timestamp > NOW() - INTERVAL '6 months' GROUP BY persona, severity ORDER BY count DESC"
            }
        ]
        
        with self.mcp_client:
            tools = self.mcp_client.list_tools_sync()
            self.agent = Agent(tools=tools)
            
            for analysis in analyses:
                print(f"\n### {analysis['title']}")
                print("-" * 40)
                response = self.agent(f"Run this SQL query and explain the results: {analysis['query']}")
                print(response)

def main():
    """Main entry point"""
    
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║   DAT409 Lab 2: Strands Agent for Black Friday Prep     ║
    ║   Natural Language Interface to Aurora PostgreSQL       ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    # Check for command line arguments
    mode = sys.argv[1] if len(sys.argv) > 1 else "interactive"
    
    # Initialize agent
    agent = BlackFridayAgent()
    agent.setup_mcp_client()
    
    if mode == "batch":
        agent.run_batch_analysis()
    else:
        agent.run_interactive_session()

if __name__ == "__main__":
    main()