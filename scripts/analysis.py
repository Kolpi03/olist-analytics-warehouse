"""
analysis.py
-----------
Pulls from the MySQL warehouse and produces the four figures the README
needs. Deliberately reads from SQL, never from the CSVs — if the
notebook and the warehouse can disagree, they eventually will.

    pip install sqlalchemy pymysql pandas matplotlib scipy
    python scripts/analysis.py --password YOURPASS
"""

import argparse
import os

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import pandas as pd
from scipy import stats
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


FIG_DIR = "docs/figures"


def q(engine, sql: str) -> pd.DataFrame:
    """Execute a SQL query and return the result as a DataFrame."""
    with engine.connect() as c:
        return pd.read_sql(text(sql), c)


def fig_lateness_vs_review(engine):
    """Create lateness vs review score figure."""

    df = q(engine, """
        SELECT delay_days, review_score
        FROM fact_orders
        WHERE delay_days BETWEEN -30 AND 40
          AND review_score IS NOT NULL
    """)

    grouped = df.groupby("delay_days")["review_score"].agg(["mean", "count"])
    grouped = grouped[grouped["count"] >= 20]

    r, p = stats.pearsonr(
        df["delay_days"],
        df["review_score"]
    )

    rho, p_s = stats.spearmanr(
        df["delay_days"],
        df["review_score"]
    )

    fig, ax = plt.subplots(figsize=(9, 5))

    ax.plot(
        grouped.index,
        grouped["mean"],
        marker="o",
        lw=2
    )

    ax.axvline(
        0,
        ls="--",
        c="grey",
        lw=1
    )

    ax.annotate(
        "promised date",
        xy=(0.5, 4.6),
        fontsize=9,
        color="grey"
    )

    ax.set_xlabel(
        "Days late  (negative = arrived early)"
    )

    ax.set_ylabel(
        "Mean review score"
    )

    ax.set_title(
        f"Review score collapses once delivery slips\n"
        f"Pearson r = {r:.3f} (p = {p:.2e}),  "
        f"Spearman rho = {rho:.3f}"
    )

    ax.grid(alpha=0.3)

    fig.tight_layout()

    fig.savefig(
        f"{FIG_DIR}/lateness_vs_review.png",
        dpi=140
    )

    plt.close(fig)

    print(
        f"lateness vs review: "
        f"r={r:.3f} p={p:.3g} | "
        f"spearman={rho:.3f} p={p_s:.3g}"
    )

    return r, p


def fig_cohort_heatmap(engine):
    """Create customer cohort retention heatmap."""

    df = q(engine, """
        WITH first_order AS (
            SELECT
                customer_sk,
                MIN(purchase_ts) AS first_ts
            FROM fact_orders
            WHERE order_status <> 'canceled'
            GROUP BY customer_sk
        ),
        cohort AS (
            SELECT
                customer_sk,
                EXTRACT(YEAR_MONTH FROM first_ts) AS cohort_ym
            FROM first_order
        )
        SELECT
            c.cohort_ym,
            PERIOD_DIFF(
                EXTRACT(YEAR_MONTH FROM o.purchase_ts),
                c.cohort_ym
            ) AS month_index,
            COUNT(DISTINCT o.customer_sk) AS customers
        FROM fact_orders o
        JOIN cohort c
            ON c.customer_sk = o.customer_sk
        WHERE o.order_status <> 'canceled'
        GROUP BY
            c.cohort_ym,
            month_index
    """)

    pivot = df.pivot(
        index="cohort_ym",
        columns="month_index",
        values="customers"
    )

    pivot = pivot[pivot[0] >= 30]

    pct = pivot.div(
        pivot[0],
        axis=0
    ) * 100

    pct = pct.iloc[:, 1:13]

    fig, ax = plt.subplots(
        figsize=(11, 6)
    )

    im = ax.imshow(
        pct.values,
        aspect="auto",
        cmap="YlGnBu",
        vmin=0,
        vmax=max(
            1,
            pct.max().max()
        )
    )

    ax.set_xticks(
        range(len(pct.columns))
    )

    ax.set_xticklabels(
        pct.columns
    )

    ax.set_yticks(
        range(len(pct.index))
    )

    ax.set_yticklabels(
        pct.index
    )

    ax.set_xlabel(
        "Months since first order"
    )

    ax.set_ylabel(
        "Acquisition cohort"
    )

    ax.set_title(
        "Cohort retention (% of cohort ordering again)"
    )

    fig.colorbar(
        im,
        ax=ax,
        label="% retained"
    )

    fig.tight_layout()

    fig.savefig(
        f"{FIG_DIR}/cohort_retention.png",
        dpi=140
    )

    plt.close(fig)


def fig_pareto(engine):
    """Create category revenue Pareto chart."""

    df = q(engine, """
        SELECT
            category_en,
            revenue
        FROM rpt_category_performance
        ORDER BY revenue DESC
    """)

    df["cum_pct"] = (
        100
        * df["revenue"].cumsum()
        / df["revenue"].sum()
    )

    top = df.head(20)

    fig, ax = plt.subplots(
        figsize=(11, 5)
    )

    ax.bar(
        top["category_en"],
        top["revenue"]
    )

    ax.set_xticklabels(
        top["category_en"],
        rotation=60,
        ha="right",
        fontsize=8
    )

    ax.set_ylabel(
        "Revenue (BRL)"
    )

    ax2 = ax.twinx()

    ax2.plot(
        top["category_en"],
        top["cum_pct"],
        color="crimson",
        marker="o",
        lw=1.5
    )

    ax2.axhline(
        80,
        ls="--",
        c="crimson",
        lw=1
    )

    ax2.set_ylabel(
        "Cumulative % of revenue"
    )

    n80 = int(
        (df["cum_pct"] <= 80).sum()
    ) + 1

    ax.set_title(
        f"{n80} of {len(df)} categories generate 80% of revenue"
    )

    fig.tight_layout()

    fig.savefig(
        f"{FIG_DIR}/category_pareto.png",
        dpi=140
    )

    plt.close(fig)

    print(
        f"pareto: {n80}/{len(df)} categories = 80% of revenue"
    )


def fig_freight_vs_distance(engine):
    """Create freight vs distance/weight figures."""

    df = q(engine, """
        SELECT
            foi.freight_value,
            dp.weight_g,

            6371 * 2 * ASIN(
                SQRT(
                    POWER(
                        SIN(
                            RADIANS(
                                gc.lat - gs.lat
                            ) / 2
                        ),
                        2
                    )
                    +
                    COS(
                        RADIANS(gs.lat)
                    )
                    *
                    COS(
                        RADIANS(gc.lat)
                    )
                    *
                    POWER(
                        SIN(
                            RADIANS(
                                gc.lng - gs.lng
                            ) / 2
                        ),
                        2
                    )
                )
            ) AS km

        FROM fact_order_items foi

        JOIN fact_orders fo
            ON fo.order_id = foi.order_id

        JOIN dim_customer dc
            ON dc.customer_sk = fo.customer_sk

        JOIN dim_seller ds
            ON ds.seller_sk = foi.seller_sk

        JOIN dim_product dp
            ON dp.product_sk = foi.product_sk

        JOIN dim_geography gc
            ON gc.zip_code_prefix = dc.zip_code_prefix

        JOIN dim_geography gs
            ON gs.zip_code_prefix = ds.zip_code_prefix

        WHERE foi.freight_value BETWEEN 0 AND 200
    """).dropna()

    # Which explains freight better:
    # distance or product weight?
    r_km, _ = stats.pearsonr(
        df["km"],
        df["freight_value"]
    )

    r_wt, _ = stats.pearsonr(
        df["weight_g"],
        df["freight_value"]
    )

    fig, axes = plt.subplots(
        1,
        2,
        figsize=(12, 4.5)
    )

    axes[0].scatter(
        df["km"],
        df["freight_value"],
        s=3,
        alpha=0.15
    )

    axes[0].set_xlabel(
        "Seller-to-customer distance (km)"
    )

    axes[0].set_ylabel(
        "Freight charged (BRL)"
    )

    axes[0].set_title(
        f"Freight vs distance  (r = {r_km:.3f})"
    )

    axes[1].scatter(
        df["weight_g"],
        df["freight_value"],
        s=3,
        alpha=0.15,
        color="darkgreen"
    )

    axes[1].set_xscale(
        "log"
    )

    axes[1].set_xlabel(
        "Product weight (g, log scale)"
    )

    axes[1].set_title(
        f"Freight vs weight  (r = {r_wt:.3f})"
    )

    for a in axes:
        a.grid(alpha=0.3)

    fig.tight_layout()

    fig.savefig(
        f"{FIG_DIR}/freight_drivers.png",
        dpi=140
    )

    plt.close(fig)

    print(
        f"freight drivers: "
        f"r_distance={r_km:.3f}  "
        f"r_weight={r_wt:.3f}"
    )


def main():
    """Main entry point."""

    ap = argparse.ArgumentParser()

    ap.add_argument(
        "--host",
        default="127.0.0.1"
    )

    ap.add_argument(
        "--port",
        default="3306"
    )

    ap.add_argument(
        "--user",
        default="root"
    )

    ap.add_argument(
        "--password",
        default=os.environ.get(
            "MYSQL_PASSWORD",
            ""
        )
    )

    ap.add_argument(
        "--db",
        default="olist"
    )

    args = ap.parse_args()

    os.makedirs(
        FIG_DIR,
        exist_ok=True
    )

    # IMPORTANT:
    # SQLAlchemy URL.create() safely handles special characters
    # in passwords such as @, :, /, #, %, etc.
    url = URL.create(
        drivername="mysql+pymysql",
        username=args.user,
        password=args.password,
        host=args.host,
        port=int(args.port),
        database=args.db,
    )

    engine = create_engine(
        url
    )

    print(
        f"Connecting to MySQL at "
        f"{args.host}:{args.port}/{args.db}..."
    )

    # Test the connection before running the analysis.
    with engine.connect() as connection:
        connection.execute(
            text("SELECT 1")
        )

    print(
        "MySQL connection successful.\n"
    )

    fig_lateness_vs_review(
        engine
    )

    fig_cohort_heatmap(
        engine
    )

    fig_pareto(
        engine
    )

    fig_freight_vs_distance(
        engine
    )

    print(
        f"\nFigures written to {FIG_DIR}/"
    )


if __name__ == "__main__":
    main()

