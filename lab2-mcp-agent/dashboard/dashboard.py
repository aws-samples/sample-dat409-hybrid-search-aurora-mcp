#!/usr/bin/env python3
"""
DAT409 Workshop - Optional: Streamlit Dashboard for Black Friday Insights
Interactive visualization of preparedness metrics and patterns
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import psycopg
import os
from pathlib import Path
import numpy as np
import sys
import warnings

# Suppress pandas SQLAlchemy warnings
warnings.filterwarnings('ignore', message='pandas only supports SQLAlchemy')

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

# Page configuration MUST BE FIRST
st.set_page_config(
    page_title="Black Friday Preparedness Dashboard",
    page_icon="🎯",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Function to find and load .env file (without Streamlit calls)
def find_and_load_env():
    """Find .env file in various locations"""
    if load_dotenv is None:
        return False, None
    
    possible_locations = [
        Path('.env'),  # Current directory
        Path('../.env'),  # Parent directory
        Path('../../.env'),  # Two levels up
        Path('../../../.env'),  # Three levels up
        Path('../setup/.env'),  # In sibling setup folder
        Path('../../setup/.env'),  # In setup folder from nested location
        Path('../lab2-mcp-agent/setup/.env'),  # Full path from scripts
        Path('setup/.env'),  # In child setup folder
        Path('/workshop/.env'),  # Workshop environment
        Path('/workshop/setup/.env'),  # Workshop setup folder
        Path('/workshop/lab2-mcp-agent/setup/.env'),  # Full workshop path
        Path.home() / '.env',  # Home directory
        Path.home() / 'workshop' / '.env',  # Home workshop
        Path.home() / 'workshop' / 'setup' / '.env',  # Home workshop setup
    ]
    
    # Also check environment variable for custom path
    env_file_path = os.getenv('ENV_FILE_PATH')
    if env_file_path:
        possible_locations.insert(0, Path(env_file_path))
    
    for location in possible_locations:
        if location.exists():
            try:
                load_dotenv(location)
                return True, location.resolve()  # Return absolute path
            except Exception as e:
                return False, None
    
    return False, None

# Try to load environment variables
env_loaded, env_location = find_and_load_env()

# Custom CSS for better styling with dark mode support
st.markdown("""
<style>
    /* Metric cards styling */
    [data-testid="metric-container"] {
        background-color: rgba(28, 131, 225, 0.1);
        border: 1px solid rgba(28, 131, 225, 0.2);
        padding: 15px;
        border-radius: 10px;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        margin: 5px 0;
    }
    
    /* Metric value styling */
    [data-testid="metric-container"] > div:nth-child(1) {
        color: #1c83e1;
        font-weight: 600;
    }
    
    [data-testid="metric-container"] > div:nth-child(2) {
        font-size: 2rem;
        font-weight: 700;
        color: #ffffff;
    }
    
    /* Delta styling */
    [data-testid="metric-container"] > div:nth-child(3) {
        color: #4ade80;
    }
    
    /* Alert boxes */
    .critical-alert {
        background-color: rgba(239, 68, 68, 0.1);
        border: 1px solid rgba(239, 68, 68, 0.3);
        border-left: 5px solid #ef4444;
        padding: 15px;
        margin: 10px 0;
        border-radius: 5px;
        color: #fca5a5;
    }
    
    .success-alert {
        background-color: rgba(34, 197, 94, 0.1);
        border: 1px solid rgba(34, 197, 94, 0.3);
        border-left: 5px solid #22c55e;
        padding: 15px;
        margin: 10px 0;
        border-radius: 5px;
        color: #86efac;
    }
    
    .warning-alert {
        background-color: rgba(251, 191, 36, 0.1);
        border: 1px solid rgba(251, 191, 36, 0.3);
        border-left: 5px solid #fbbf24;
        padding: 15px;
        margin: 10px 0;
        border-radius: 5px;
        color: #fde68a;
    }
    
    /* Headers */
    h1, h2, h3, h4 {
        color: #ffffff !important;
    }
    
    /* Expander styling */
    .streamlit-expanderHeader {
        background-color: rgba(28, 131, 225, 0.05);
        border-radius: 5px;
    }
    
    /* Sidebar styling */
    section[data-testid="stSidebar"] {
        background-color: #0e1117;
        border-right: 1px solid rgba(28, 131, 225, 0.2);
    }
    
    /* Success/warning/error messages */
    .stSuccess {
        background-color: rgba(34, 197, 94, 0.1);
        border: 1px solid rgba(34, 197, 94, 0.3);
        color: #86efac;
    }
    
    .stWarning {
        background-color: rgba(251, 191, 36, 0.1);
        border: 1px solid rgba(251, 191, 36, 0.3);
        color: #fde68a;
    }
    
    .stError {
        background-color: rgba(239, 68, 68, 0.1);
        border: 1px solid rgba(239, 68, 68, 0.3);
        color: #fca5a5;
    }
</style>
""", unsafe_allow_html=True)

class BlackFridayDashboard:
    """Interactive dashboard for Black Friday preparedness"""
    
    def __init__(self):
        # Show env loading status (simplified)
        if env_loaded and env_location:
            st.sidebar.success("✅ Configuration loaded")
        else:
            st.sidebar.warning("⚠️ No .env file found. Using environment variables or manual input.")
            with st.sidebar.expander("💡 Help: Where to place .env file"):
                st.markdown("""
                The dashboard searched these locations:
                - Current directory
                - Parent directories (../, ../../)
                - Setup folder (../setup/.env)
                - Workshop paths (/workshop/.env)
                
                **Options:**
                1. Place your .env file in one of these locations
                2. Set ENV_FILE_PATH environment variable:
                   ```bash
                   export ENV_FILE_PATH=/path/to/your/.env
                   ```
                3. Enter connection details manually below
                """)
        
        # Try to get database connection details from environment
        self.db_host = os.getenv('DB_HOST')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')
        
        # If any required field is missing, show configuration UI
        if not all([self.db_host, self.db_name, self.db_user, self.db_password]):
            st.sidebar.header("🔧 Database Configuration")
            if not env_loaded:
                st.sidebar.info("Enter connection details manually or create a .env file")
            
            self.db_host = st.sidebar.text_input(
                "Database Host", 
                value=self.db_host or "",
                help="e.g., your-cluster.cluster-xxx.us-west-2.rds.amazonaws.com"
            )
            self.db_port = st.sidebar.text_input(
                "Database Port", 
                value=self.db_port or "5432"
            )
            self.db_name = st.sidebar.text_input(
                "Database Name", 
                value=self.db_name or "workshop_db"
            )
            self.db_user = st.sidebar.text_input(
                "Database User", 
                value=self.db_user or "workshop_admin"
            )
            self.db_password = st.sidebar.text_input(
                "Database Password", 
                type="password",
                value=self.db_password or ""
            )
            
            if st.sidebar.button("Test Connection"):
                self.test_connection()
        
        # Build connection string
        if all([self.db_host, self.db_name, self.db_user, self.db_password]):
            self.conn_string = f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
            self.connection_configured = True
        else:
            self.conn_string = None
            self.connection_configured = False
    
    def test_connection(self):
        """Test database connection"""
        if not self.conn_string:
            st.sidebar.error("Please fill in all connection details")
            return
        
        try:
            with psycopg.connect(self.conn_string) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT version()")
                    version = cur.fetchone()[0]
                    st.sidebar.success(f"✅ Connected! PostgreSQL {version.split(',')[0]}")
        except Exception as e:
            st.sidebar.error(f"❌ Connection failed: {str(e)}")
            st.sidebar.info("💡 Check that:\n- Host is accessible\n- Credentials are correct\n- Database exists\n- Security group allows connection")
    
    @st.cache_data(ttl=60)
    def fetch_incident_data(_self, days_back: int = 365):
        """Fetch incident data from database"""
        if not _self.connection_configured:
            st.error("Database connection not configured")
            return pd.DataFrame()
        
        # For "All time", fetch without date filter
        if days_back >= 36500:  # Our "All time" value
            query = """
                SELECT 
                    doc_id,
                    content,
                    persona,
                    timestamp,
                    severity,
                    metrics
                FROM incident_logs
                ORDER BY timestamp DESC
            """
            params = None
        else:
            query = """
                SELECT 
                    doc_id,
                    content,
                    persona,
                    timestamp,
                    severity,
                    metrics
                FROM incident_logs
                WHERE timestamp > CURRENT_DATE - INTERVAL '%s days'
                ORDER BY timestamp DESC
            """
            params = (days_back,)
        
        try:
            with psycopg.connect(_self.conn_string) as conn:
                # First check if table exists and has data
                with conn.cursor() as cur:
                    cur.execute("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'incident_logs')")
                    table_exists = cur.fetchone()[0]
                    
                    if not table_exists:
                        st.error("❌ Table 'incident_logs' does not exist")
                        st.info("💡 Please run Lab 1 (dat409_notebook.ipynb) to create and populate the incident_logs table")
                        return pd.DataFrame()
                    
                    # Check row count
                    cur.execute("SELECT COUNT(*) FROM incident_logs")
                    row_count = cur.fetchone()[0]
                    
                    if row_count == 0:
                        st.warning("⚠️ Table 'incident_logs' exists but is empty")
                        st.info("💡 Run all cells in Lab 1 notebook to populate the table with sample data")
                        return pd.DataFrame()
                    
                    st.sidebar.success(f"✅ Found {row_count:,} incident logs in database")
                
                # Now fetch the data
                if params:
                    df = pd.read_sql_query(query, conn, params=params)
                else:
                    df = pd.read_sql_query(query, conn)
            
            if df.empty:
                st.warning(f"⚠️ No incidents found in the selected time range")
                st.info("💡 Try selecting 'All time' or check the data timestamps")
                return pd.DataFrame()
            
            # Parse timestamp and remove timezone for easier comparison
            df['timestamp'] = pd.to_datetime(df['timestamp']).dt.tz_localize(None)
            df['date'] = df['timestamp'].dt.date
            df['hour'] = df['timestamp'].dt.hour
            df['month'] = df['timestamp'].dt.to_period('M')
            
            # Debug info
            st.sidebar.info(f"📊 Loaded {len(df)} incidents from {df['timestamp'].min().date()} to {df['timestamp'].max().date()}")
            
            return df
            
        except Exception as e:
            st.error(f"Failed to fetch data: {str(e)}")
            if "could not translate host name" in str(e):
                st.info("💡 Check that your DB_HOST is correct and accessible")
            elif "password authentication failed" in str(e):
                st.info("💡 Check your database credentials")
            elif "incident_logs" in str(e):
                st.info("💡 Make sure you've run Lab 1 to create and populate the incident_logs table")
            return pd.DataFrame()
    
    @st.cache_data(ttl=60)
    def fetch_preparedness_checklist(_self):
        """Fetch preparedness checklist items"""
        if not _self.connection_configured:
            return pd.DataFrame()
        
        query = """
            SELECT 
                category,
                item,
                priority,
                status,
                owner,
                due_date,
                notes
            FROM preparedness_checklist
            ORDER BY priority, category
        """
        
        try:
            with psycopg.connect(_self.conn_string) as conn:
                df = pd.read_sql_query(query, conn)
            return df
        except Exception as e:
            # Table might not exist yet
            return pd.DataFrame()
    
    def create_severity_timeline(self, df):
        """Create timeline visualization of incident severity"""
        if df.empty:
            fig = go.Figure()
            fig.add_annotation(
                text="No data available",
                xref="paper", yref="paper",
                x=0.5, y=0.5, showarrow=False,
                font=dict(size=20, color="#666")
            )
            fig.update_layout(
                plot_bgcolor='rgba(0,0,0,0)',
                paper_bgcolor='rgba(0,0,0,0)',
                height=400
            )
            return fig
        
        # Aggregate by date and severity
        timeline_data = df.groupby(['date', 'severity']).size().reset_index(name='count')
        
        # Create stacked area chart with better colors
        fig = px.area(
            timeline_data,
            x='date',
            y='count',
            color='severity',
            title='Incident Severity Timeline',
            color_discrete_map={
                'critical': '#ef4444',  # Bright red
                'warning': '#fbbf24',   # Bright amber
                'info': '#3b82f6'       # Bright blue
            },
            height=400
        )
        
        fig.update_layout(
            plot_bgcolor='rgba(0,0,0,0)',
            paper_bgcolor='rgba(0,0,0,0)',
            xaxis_title="Date",
            yaxis_title="Number of Incidents",
            hovermode='x unified',
            title_font_color='white',
            xaxis=dict(
                showgrid=True,
                gridcolor='rgba(128,128,128,0.2)',
                color='white'
            ),
            yaxis=dict(
                showgrid=True,
                gridcolor='rgba(128,128,128,0.2)',
                color='white'
            ),
            legend=dict(
                bgcolor='rgba(0,0,0,0)',
                font=dict(color='white')
            )
        )
        
        return fig
    
    def create_team_distribution(self, df):
        """Create team distribution chart"""
        if df.empty:
            fig = go.Figure()
            fig.add_annotation(
                text="No data available",
                xref="paper", yref="paper",
                x=0.5, y=0.5, showarrow=False,
                font=dict(size=20, color="#666")
            )
            fig.update_layout(
                plot_bgcolor='rgba(0,0,0,0)',
                paper_bgcolor='rgba(0,0,0,0)',
                height=400
            )
            return fig
        
        team_severity = df.groupby(['persona', 'severity']).size().reset_index(name='count')
        
        fig = px.bar(
            team_severity,
            x='persona',
            y='count',
            color='severity',
            title='Incident Distribution by Team',
            color_discrete_map={
                'critical': '#ef4444',  # Bright red
                'warning': '#fbbf24',   # Bright amber
                'info': '#3b82f6'       # Bright blue
            },
            height=400
        )
        
        fig.update_layout(
            plot_bgcolor='rgba(0,0,0,0)',
            paper_bgcolor='rgba(0,0,0,0)',
            xaxis_title="Team",
            yaxis_title="Number of Incidents",
            barmode='stack',
            title_font_color='white',
            xaxis=dict(
                showgrid=False,
                color='white'
            ),
            yaxis=dict(
                showgrid=True,
                gridcolor='rgba(128,128,128,0.2)',
                color='white'
            ),
            legend=dict(
                bgcolor='rgba(0,0,0,0)',
                font=dict(color='white')
            )
        )
        
        return fig
    
    def create_hourly_heatmap(self, df):
        """Create hourly pattern heatmap"""
        if df.empty:
            fig = go.Figure()
            fig.add_annotation(
                text="No data available",
                xref="paper", yref="paper",
                x=0.5, y=0.5, showarrow=False,
                font=dict(size=20, color="#666")
            )
            fig.update_layout(
                plot_bgcolor='rgba(0,0,0,0)',
                paper_bgcolor='rgba(0,0,0,0)',
                height=400
            )
            return fig
        
        # Create hour/day matrix
        df['weekday'] = df['timestamp'].dt.day_name()
        hourly_data = df.groupby(['weekday', 'hour']).size().reset_index(name='count')
        
        # Pivot for heatmap
        heatmap_data = hourly_data.pivot(index='weekday', columns='hour', values='count').fillna(0)
        
        # Reorder days
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        heatmap_data = heatmap_data.reindex([d for d in day_order if d in heatmap_data.index])
        
        fig = go.Figure(data=go.Heatmap(
            z=heatmap_data.values,
            x=heatmap_data.columns,
            y=heatmap_data.index,
            colorscale='Blues',  # Better for dark mode
            hoverongaps=False,
            text=heatmap_data.values,
            texttemplate='%{text}',
            textfont={"size": 10, "color": "white"},
            colorbar=dict(
                tickfont=dict(color='white'),
                title=dict(text='Count', font=dict(color='white'))
            )
        ))
        
        fig.update_layout(
            title='Incident Pattern Heatmap (Hour of Day vs Day of Week)',
            xaxis_title='Hour of Day',
            yaxis_title='Day of Week',
            height=400,
            plot_bgcolor='rgba(0,0,0,0)',
            paper_bgcolor='rgba(0,0,0,0)',
            title_font_color='white',
            xaxis=dict(
                showgrid=False,
                color='white',
                dtick=1
            ),
            yaxis=dict(
                showgrid=False,
                color='white'
            )
        )
        
        return fig
    
    def calculate_risk_score(self, df):
        """Calculate Black Friday risk score"""
        if df.empty:
            return 0
        
        # Get November data - handle timezone-aware timestamps
        november_data = df[df['timestamp'].dt.month == 11]
        
        # Calculate metrics
        critical_rate = len(november_data[november_data['severity'] == 'critical']) / max(len(november_data), 1)
        avg_daily_incidents = len(november_data) / 30
        peak_hour_concentration = november_data.groupby('hour').size().max() / max(len(november_data), 1) if not november_data.empty else 0
        
        # Risk score (0-100)
        risk_score = min(100, int(
            (critical_rate * 40) +  # 40% weight on critical incidents
            (min(avg_daily_incidents / 10, 1) * 30) +  # 30% weight on volume
            (peak_hour_concentration * 30)  # 30% weight on concentration
        ))
        
        return risk_score
    
    def render_sidebar(self):
        """Render sidebar controls"""
        
        st.sidebar.header("🎯 Black Friday Preparedness")
        
        if not self.connection_configured:
            return pd.DataFrame(), 90
        
        # Add time range selector
        time_range = st.sidebar.radio(
            "Time Range",
            ["Last 7 days", "Last 30 days", "Last 90 days", "Last 365 days", "All time"],
            index=4  # Default to "All time"
        )
        
        # Convert to days
        days_mapping = {
            "Last 7 days": 7,
            "Last 30 days": 30,
            "Last 90 days": 90,
            "Last 365 days": 365,
            "All time": 36500  # 100 years
        }
        days_back = days_mapping[time_range]
        
        # Fetch data
        df = self.fetch_incident_data(days_back)
        
        if df.empty:
            return df, days_back
        
        # Team filter
        teams = st.sidebar.multiselect(
            "Filter by Team",
            options=df['persona'].unique(),
            default=df['persona'].unique()
        )
        
        # Severity filter
        severities = st.sidebar.multiselect(
            "Filter by Severity",
            options=df['severity'].unique(),
            default=df['severity'].unique()
        )
        
        # Apply filters
        filtered_df = df[
            (df['persona'].isin(teams)) & 
            (df['severity'].isin(severities))
        ]
        
        return filtered_df, days_back
    
    def render_metrics(self, df):
        """Render key metrics"""
        
        col1, col2, col3, col4 = st.columns(4)
        
        if df.empty:
            with col1:
                st.metric("Total Incidents", "0")
            with col2:
                st.metric("Critical Incidents", "0")
            with col3:
                st.metric("Risk Score", "N/A")
            with col4:
                st.metric("Days to Black Friday", "N/A")
            return
        
        # Calculate metrics
        total_incidents = len(df)
        critical_incidents = len(df[df['severity'] == 'critical'])
        risk_score = self.calculate_risk_score(df)
        days_to_bf = max(0, (datetime(2025, 11, 28) - datetime.now()).days)  # 2025 Black Friday
        
        # Fix timezone comparison - use timezone-naive datetime
        recent_cutoff = datetime.now() - timedelta(days=7)
        recent_incidents = len(df[df['timestamp'] > recent_cutoff])
        
        with col1:
            st.metric(
                "Total Incidents",
                f"{total_incidents:,}",
                delta=f"{recent_incidents} this week"
            )
        
        with col2:
            st.metric(
                "Critical Incidents",
                f"{critical_incidents:,}",
                delta=f"{(critical_incidents/max(total_incidents,1)*100):.1f}% of total",
                delta_color="inverse"
            )
        
        with col3:
            risk_color = "🔴" if risk_score > 70 else "🟡" if risk_score > 40 else "🟢"
            st.metric(
                "Risk Score",
                f"{risk_color} {risk_score}/100",
                delta="Based on patterns"
            )
        
        with col4:
            st.metric(
                "Days to Black Friday",
                days_to_bf,
                delta="Preparation time"
            )
    
    def render_preparedness_section(self):
        """Render preparedness checklist section"""
        
        st.header("📋 Preparedness Checklist")
        
        checklist = self.fetch_preparedness_checklist()
        
        if not checklist.empty:
            # Create columns for categories
            categories = checklist['category'].unique()
            cols = st.columns(len(categories))
            
            for idx, category in enumerate(categories):
                with cols[idx]:
                    st.markdown(f"### {category}")
                    cat_items = checklist[checklist['category'] == category]
                    
                    # Create a container for each category
                    with st.container():
                        for _, item in cat_items.iterrows():
                            status_icon = "✅" if item['status'] == 'completed' else "⏳" if item['status'] == 'in_progress' else "📌"
                            priority_color = "#ef4444" if item['priority'] == 1 else "#fbbf24" if item['priority'] == 2 else "#3b82f6"
                            
                            # Create item card
                            st.markdown(f"""
                            <div style="margin-bottom: 10px; padding: 10px; 
                                        background-color: rgba(28, 131, 225, 0.05); 
                                        border-left: 3px solid {priority_color};
                                        border-radius: 5px;">
                                <div style="font-weight: bold; margin-bottom: 5px;">
                                    {status_icon} {item['item']}
                                </div>
                                <div style="font-size: 0.85em; color: #999;">
                                    👤 {item['owner']} | {item['status']}
                                </div>
                            </div>
                            """, unsafe_allow_html=True)
        else:
            st.info("No checklist items found. Run the Lab 2 setup script to populate.")
    
    def render_insights(self, df):
        """Render AI-generated insights"""
        
        st.header("🤖 Key Insights")
        
        if df.empty:
            st.info("No data available for insights. Please check that Lab 1 has been completed.")
            return
        
        # Calculate insights
        peak_hour = df.groupby('hour').size().idxmax() if not df.empty else 0
        peak_day = df.groupby(df['timestamp'].dt.day_name()).size().idxmax() if not df.empty else "N/A"
        most_active_team = df.groupby('persona').size().idxmax() if not df.empty else "N/A"
        
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown(f"""
            <div class="success-alert">
            <h4 style="color: #22c55e; margin-top: 0;">📊 Pattern Analysis</h4>
            <ul style="color: #86efac;">
            <li>Peak incident hour: <b>{peak_hour}:00</b></li>
            <li>Highest activity day: <b>{peak_day}</b></li>
            <li>Most reports from: <b>{most_active_team}</b></li>
            </ul>
            </div>
            """, unsafe_allow_html=True)
        
        with col2:
            # Find critical patterns
            critical_keywords = ['connection', 'timeout', 'memory', 'CPU']
            pattern_counts = {}
            
            for keyword in critical_keywords:
                count = len(df[df['content'].str.contains(keyword, case=False, na=False)])
                if count > 0:
                    pattern_counts[keyword] = count
            
            if pattern_counts:
                st.markdown(f"""
                <div class="critical-alert">
                <h4 style="color: #ef4444; margin-top: 0;">⚠️ Common Issues</h4>
                <ul style="color: #fca5a5;">
                {"".join([f"<li>{k}: <b>{v} incidents</b></li>" for k, v in sorted(pattern_counts.items(), key=lambda x: x[1], reverse=True)[:3]])}
                </ul>
                </div>
                """, unsafe_allow_html=True)
            else:
                st.markdown("""
                <div class="warning-alert">
                <h4 style="color: #fbbf24; margin-top: 0;">📌 No Pattern Detected</h4>
                <p style="color: #fde68a;">No clear incident patterns found in the selected timeframe.</p>
                </div>
                """, unsafe_allow_html=True)
    
    def run(self):
        """Main dashboard execution"""
        
        # Header
        st.title("🎯 Black Friday Preparedness Dashboard")
        st.markdown("*Real-time insights from Aurora PostgreSQL hybrid search*")
        
        # Check connection
        if not self.connection_configured:
            st.error("❌ Database connection not configured. Please check the sidebar.")
            st.info("💡 Make sure your .env file contains: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD")
            return
        
        # Sidebar and filters
        filtered_df, days_back = self.render_sidebar()
        
        # Metrics row
        self.render_metrics(filtered_df)
        
        # Visualizations
        st.header("📈 Incident Analysis")
        
        col1, col2 = st.columns(2)
        with col1:
            st.plotly_chart(self.create_severity_timeline(filtered_df), use_container_width=True, key="severity_timeline")
        with col2:
            st.plotly_chart(self.create_team_distribution(filtered_df), use_container_width=True, key="team_distribution")
        
        # Heatmap
        st.plotly_chart(self.create_hourly_heatmap(filtered_df), use_container_width=True, key="hourly_heatmap")
        
        # Insights
        self.render_insights(filtered_df)
        
        # Preparedness checklist
        self.render_preparedness_section()
        
        # Recent incidents table
        if not filtered_df.empty:
            with st.expander("📋 Recent Critical Incidents"):
                recent_critical = filtered_df[filtered_df['severity'] == 'critical'].head(10)
                if not recent_critical.empty:
                    st.dataframe(
                        recent_critical[['timestamp', 'persona', 'content']],
                        use_container_width=True
                    )
                else:
                    st.info("No critical incidents in the selected timeframe")
        
        # Footer
        st.markdown("---")
        st.caption("DAT409 Workshop | Hybrid Search with Aurora PostgreSQL | Last updated: " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

def main():
    """Main entry point"""
    dashboard = BlackFridayDashboard()
    dashboard.run()

if __name__ == "__main__":
    main()