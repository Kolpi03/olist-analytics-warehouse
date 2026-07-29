"""
Olist delivery-quality dashboard.

    pip install streamlit sqlalchemy pymysql pandas
    streamlit run dashboard/app.py

Reads ONLY from the rpt_* summary tables built by sql/10_summary_tables.sql.
That is the point: the dashboard never re-aggregates 112k line items, so
every filter change is instant.
"""

import os

import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text

st.set_page_config(page_title="Olist Delivery Quality", layout="wide")


@st.cache_resource
def get_engine():
    user = os.environ.get("MYSQL_USER", "root")
    pwd = os.environ.get("MYSQL_PASSWORD", "")
    host = os.environ.get("MYSQL_HOST", "127.0.0.1")
    return create_engine(f"mysql+pymysql://{user}:{pwd}@{host}:3306/olist")


@st.cache_data(ttl=600)
def load(sql: str) -> pd.DataFrame:
    with get_engine().connect() as c:
        return pd.read_sql(text(sql), c)


kpis = load("SELECT * FROM rpt_monthly_kpis ORDER BY year_month_key")
sellers = load("SELECT * FROM rpt_seller_scorecard")
cats = load("SELECT * FROM rpt_category_performance ORDER BY revenue DESC")

st.title("Why Olist Is Losing Customers")
st.caption("Late deliveries drive bad reviews, and bad first reviews drive churn.")

# ---- sidebar filter -------------------------------------------------
months = kpis["year_month_key"].tolist()
lo, hi = st.sidebar.select_slider(
    "Period", options=months, value=(months[0], months[-1])
)
k = kpis[(kpis.year_month_key >= lo) & (kpis.year_month_key <= hi)]

# ---- KPI row --------------------------------------------------------
c1, c2, c3, c4 = st.columns(4)
c1.metric("Revenue", f"R$ {k.revenue.sum():,.0f}")
c2.metric("Orders", f"{int(k.orders.sum()):,}")
c3.metric("Late deliveries", f"{k.late_pct.mean():.1f}%")
c4.metric("Avg review", f"{k.avg_review.mean():.2f} / 5")

# ---- trend ----------------------------------------------------------
st.subheader("Monthly revenue and delivery reliability")
left, right = st.columns(2)
with left:
    st.line_chart(k.set_index("year_month_key")[["revenue"]])
with right:
    st.line_chart(k.set_index("year_month_key")[["late_pct", "avg_review"]])

# ---- sellers --------------------------------------------------------
st.subheader("Sellers to act on")
flag = st.radio("Filter", ["ESCALATE", "WATCH", "OK", "All"], horizontal=True, index=0)
view = sellers if flag == "All" else sellers[sellers.action_flag == flag]
st.dataframe(
    view.sort_values("late_pct", ascending=False)[
        ["seller_id", "state", "orders", "revenue", "late_pct",
         "avg_review", "avg_delivery_days", "action_flag"]
    ],
    use_container_width=True, hide_index=True,
)
st.caption(
    f"{(sellers.action_flag == 'ESCALATE').sum()} sellers flagged ESCALATE "
    f"out of {len(sellers)}. Only sellers with 30+ orders are scored — below "
    "that, a single bad delivery swings the rate to 100%."
)

# ---- categories -----------------------------------------------------
st.subheader("Category revenue vs delivery quality")
st.dataframe(
    cats[["category_en", "revenue", "pct_of_revenue", "orders",
          "avg_review", "late_pct"]].head(25),
    use_container_width=True, hide_index=True,
)
