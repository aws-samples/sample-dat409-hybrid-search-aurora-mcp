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
from dotenv import load_dotenv
import numpy as np

# Load environment variables
load_dotenv('/workshop/.env')

# Page configuration
st.set_page_config(
    page_title="Black Friday Preparedness Dashboard",
    page_icon="🎯",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for better styling
st.markdown("""
<style>
    .stMetric {
        background-color: #f0f2f6;
        padding: 15px;
        border-radius: 10px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .critical-alert {
        background-color: #ffebee;
        border-left: 5px solid #f44336;
        padding: 10px;
        margin: 10px 0;
    }
    .success-alert {
        background-color: #e8f5e9;
        border-left: 5px solid #4caf50;
        padding: 10px;
        margin: 10px 0;
    }
</style>
""", unsafe_allow_html=True)

class BlackFridayDashboard:
    """Interactive dashboard for Black Friday preparedness"""
    
    def __init__(self):
        self.db_host = os.getenv('DB_HOST')
        self.db_port = os.getenv('DB_PORT', '5432')
        self.db_name = os.getenv('DB_NAME')
        self.db_user = os.getenv('DB_USER')
        self.db_password = os.getenv('DB_PASSWORD')
        self.conn_string = f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"
    
    @st.cache_data(ttl=60)
    def fetch_incident_data(_self, days_back: int = 365):
        """Fetch incident data from database"""
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
        
        with psycopg.connect(_self.conn_string) as conn:
            df = pd.read_sql_query(query, conn, params=(days_back,))
        
        # Parse timestamp
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        df['date'] = df['timestamp'].dt.date
        df['hour'] = df['timestamp'].dt.hour
        df['month'] = df['timestamp'].dt.to_period('M')
        
        return df
    
    @st.cache_data(ttl=60)
    def fetch_preparedness_checklist(_self):
        """Fetch preparedness checklist items"""
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
        
        with psycopg.connect(_self.conn_string) as conn:
            df = pd.read_sql_query(query, conn)
        
        return df
    
    def create_severity_timeline(self, df):
        """Create timeline visualization of incident severity"""
        
        # Aggregate by date and severity
        timeline_data = df.groupby(['date', 'severity']).size().reset_index(name='count')
        
        # Create stacked area chart
        fig = px.area(
            timeline_data,
            x='date',
            y='count',
            color='severity',
            title='Incident Severity Timeline',
            color_discrete_map={
                'critical': '#f44336',
                'warning': '#ff9800',
                'info': '#2196f3'
            },
            height=400
        )
        
        fig.update_layout(
            xaxis_title="Date",
            yaxis_title="Number of Incidents",
            hovermode='x unified'
        )
        
        return fig
    
    def create_team_distribution(self, df):
        """Create team distribution chart"""
        
        team_severity = df.groupby(['persona', 'severity']).size().reset_index(name='count')
        
        fig = px.bar(
            team_severity,
            x='persona',
            y='count',
            color='severity',
            title='Incident Distribution by Team',
            color_discrete_map={
                'critical': '#f44336',
                'warning': '#ff9800',
                'info': '#2196f3'
            },
            height=400
        )
        
        fig.update_layout(
            xaxis_title="Team",
            yaxis_title="Number of Incidents",
            barmode='stack'
        )
        
        return fig
    
    def create_hourly_heatmap(self, df):
        """Create hourly pattern heatmap"""
        
        # Create hour/day matrix
        df['weekday'] = df['timestamp'].dt.day_name()
        hourly_data = df.groupby(['weekday', 'hour']).size().reset_index(name='count')
        
        # Pivot for heatmap
        heatmap_data = hourly_data.pivot(index='weekday', columns='hour', values='count').fillna(0)
        
        # Reorder days
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        heatmap_data = heatmap_data.reindex(day_order)
        
        fig = go.Figure(data=go.Heatmap(
            z=heatmap_data.values,
            x=heatmap_data.columns,
            y=heatmap_data.index,
            colorscale='RdYlBu_r',
            hoverongaps=False,
            text=heatmap_data.values,
            texttemplate='%{text}',
            textfont={"size": 8}
        ))
        
        fig.update_layout(
            title='Incident Pattern Heatmap (Hour of Day vs Day of Week)',
            xaxis_title='Hour of Day',
            yaxis_title='Day of Week',
            height=400
        )
        
        return fig
    
    def calculate_risk_score(self, df):
        """Calculate Black Friday risk score"""
        
        # Get November data from previous year
        november_data = df[df['timestamp'].dt.month == 11]
        
        # Calculate metrics
        critical_rate = len(november_data[november_data['severity'] == 'critical']) / max(len(november_data), 1)
        avg_daily_incidents = len(november_data) / 30
        peak_hour_concentration = november_data.groupby('hour').size().max() / max(len(november_data), 1)
        
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
        
        # Date range selector
        days_back = st.sidebar.slider(
            "Historical Data (days)",
            min_value=7,
            max_value=365,
            value=90,
            step=7
        )
        
        # Team filter
        df = self.fetch_incident_data(days_back)
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
        
        # Calculate metrics
        total_incidents = len(df)
        critical_incidents = len(df[df['severity'] == 'critical'])
        risk_score = self.calculate_risk_score(df)
        days_to_bf = max(0, (datetime(2024, 11, 29) - datetime.now()).days)
        
        with col1:
            st.metric(
                "Total Incidents",
                f"{total_incidents:,}",
                delta=f"{len(df[df['timestamp'] > datetime.now() - timedelta(days=7)])} this week"
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
            # Group by category
            for category in checklist['category'].unique():
                with st.expander(f"{category} ({len(checklist[checklist['category'] == category])} items)"):
                    cat_items = checklist[checklist['category'] == category]
                    
                    for _, item in cat_items.iterrows():
                        status_icon = "✅" if item['status'] == 'completed' else "⏳" if item['status'] == 'in_progress' else "📌"
                        priority_badge = "🔴" if item['priority'] == 1 else "🟡" if item['priority'] == 2 else "🔵"
                        
                        st.markdown(f"""
                        {status_icon} **{item['item']}** {priority_badge}
                        - Owner: {item['owner']}
                        - Status: {item['status']}
                        """)
        else:
            st.info("No checklist items found. Run the setup script to populate.")
    
    def render_insights(self, df):
        """Render AI-generated insights"""
        
        st.header("🤖 Key Insights")
        
        # Calculate insights
        peak_hour = df.groupby('hour').size().idxmax()
        peak_day = df.groupby(df['timestamp'].dt.day_name()).size().idxmax()
        most_active_team = df.groupby('persona').size().idxmax()
        
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown(f"""
            <div class="success-alert">
            <h4>📊 Pattern Analysis</h4>
            <ul>
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
                <h4>⚠️ Common Issues</h4>
                <ul>
                {"".join([f"<li>{k}: <b>{v} incidents</b></li>" for k, v in sorted(pattern_counts.items(), key=lambda x: x[1], reverse=True)[:3]])}
                </ul>
                </div>
                """, unsafe_allow_html=True)
    
    def run(self):
        """Main dashboard execution"""
        
        # Header
        st.title("🎯 Black Friday Preparedness Dashboard")
        st.markdown("*Real-time insights from Aurora PostgreSQL hybrid search*")
        
        # Sidebar and filters
        filtered_df, days_back = self.render_sidebar()
        
        # Metrics row
        self.render_metrics(filtered_df)
        
        # Visualizations
        st.header("📈 Incident Analysis")
        
        col1, col2 = st.columns(2)
        with col1:
            st.plotly_chart(self.create_severity_timeline(filtered_df), use_container_width=True)
        with col2:
            st.plotly_chart(self.create_team_distribution(filtered_df), use_container_width=True)
        
        # Heatmap
        st.plotly_chart(self.create_hourly_heatmap(filtered_df), use_container_width=True)
        
        # Insights
        self.render_insights(filtered_df)
        
        # Preparedness checklist
        self.render_preparedness_section()
        
        # Recent incidents table
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