#!/usr/bin/env python3
"""Render dashboard preview charts (SVG only, vector shapes + text, no raster) from the KPI tables."""
import io, pathlib, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from svgmin import minify_svg

plt.rcParams.update({"svg.fonttype": "none", "font.family": "sans-serif", "font.size": 9,
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": False})
C1, C2, C3, C4 = "#1f6f8b", "#e07a5f", "#81b29a", "#f2cc8f"


def save(fig, path):
    buf = io.StringIO(); fig.savefig(buf, format="svg", bbox_inches="tight"); plt.close(fig)
    path.write_text(minify_svg(buf.getvalue()))


def lab(ax, xs, ys, fmt, dy=0.0, fs=7):
    for x, y in zip(xs, ys):
        ax.text(x, y + dy, fmt(y), ha="center", va="bottom", fontsize=fs)


def p_smoker(ax, t):
    d = pd.read_csv(t / "a_med_smoker.csv").sort_values("smoker_status")
    ax.bar(d.smoker_status, d.avg_charges, color=[C3, C2])
    for i, (v, n) in enumerate(zip(d.avg_charges, d.members)):
        ax.text(i, v * 1.02, f"${v:,.0f}\nn={n}", ha="center", va="bottom", fontsize=8)
    ax.set_ylim(0, d.avg_charges.max() * 1.3); ax.set_ylabel("Avg annual charges (USD)")
    ax.set_title("Medical: smokers cost ~3.8x more")


def p_age(ax, t):
    d = pd.read_csv(t / "a_med_age_smoker.csv").sort_values("age_band")
    x = np.arange(len(d)); w = 0.38
    ax.bar(x - w / 2, d.avg_charges_non_smoker, w, color=C3, label="non-smoker")
    ax.bar(x + w / 2, d.avg_charges_smoker, w, color=C2, label="smoker")
    ax.set_xticks(x); ax.set_xticklabels(d.age_band.str[4:]); ax.set_xlabel("Age band")
    ax.set_ylabel("Avg charges (USD)"); ax.legend(frameon=False, fontsize=7)
    ax.set_title("Medical: charges rise with age in both groups")


def p_bmi(ax, t):
    d = pd.read_csv(t / "a_med_bmi_smoker.csv").sort_values("bmi_category")
    x = np.arange(len(d)); w = 0.38
    ax.bar(x - w / 2, d.avg_charges_non_smoker, w, color=C3, label="non-smoker")
    ax.bar(x + w / 2, d.avg_charges_smoker, w, color=C2, label="smoker")
    lab(ax, x + w / 2, d.avg_charges_smoker, lambda v: f"${v/1000:.1f}k")
    ax.set_xticks(x); ax.set_xticklabels(d.bmi_category.str[3:]); ax.set_ylabel("Avg charges (USD)")
    ax.set_ylim(0, d.avg_charges_smoker.max() * 1.2); ax.legend(frameon=False, fontsize=7)
    ax.set_title("Medical: obesity x smoking interaction")


def p_region(ax, t):
    d = pd.read_csv(t / "a_med_region.csv").sort_values("avg_charges")
    ax.barh(d.region_name, d.avg_charges, color=C1)
    for i, (v, s) in enumerate(zip(d.avg_charges, d.smoker_pct)):
        ax.text(v * 1.01, i, f"${v:,.0f} | {s:.1f}% smokers", va="center", fontsize=7)
    ax.set_xlim(0, d.avg_charges.max() * 1.55); ax.set_xlabel("Avg charges (USD)")
    ax.set_title("Medical: region (southeast = most smokers)")


def p_drv(ax, t):
    d = pd.read_csv(t / "a_motor_driver_age.csv").sort_values("driver_age_band")
    ax.bar(d.driver_age_band.str[4:], d.claim_frequency * 100, color=C1)
    lab(ax, range(len(d)), d.claim_frequency * 100, lambda v: f"{v:.1f}")
    ax.set_ylabel("Claims per 100 policy-years"); ax.set_xlabel("Driver age")
    ax.set_ylim(0, d.claim_frequency.max() * 125); ax.set_title("Motor: claim frequency by driver age")


def p_bm(ax, t):
    d = pd.read_csv(t / "a_motor_bonus_malus.csv").sort_values("bonus_malus_band")
    ax.bar(d.bonus_malus_band.str[4:].str.replace(" (max bonus)", "\n(max bonus)").str.replace(" (malus)", "\n(malus)"),
           d.claim_frequency * 100, color=C2)
    lab(ax, range(len(d)), d.claim_frequency * 100, lambda v: f"{v:.1f}")
    ax.set_ylabel("Claims per 100 policy-years"); ax.set_xlabel("Bonus-malus score")
    ax.set_ylim(0, d.claim_frequency.max() * 125); ax.set_title("Motor: frequency by bonus-malus")


def p_area(ax, t):
    d = pd.read_csv(t / "a_motor_area.csv").sort_values("area_code")
    ax.bar(d.area_code + "\n(" + d.median_density.astype(str) + "/km2)", d.claim_frequency * 100, color=C3)
    lab(ax, range(len(d)), d.claim_frequency * 100, lambda v: f"{v:.1f}")
    ax.set_ylabel("Claims per 100 policy-years"); ax.set_xlabel("Area (median density)")
    ax.set_ylim(0, d.claim_frequency.max() * 125); ax.set_title("Motor: frequency rises with urban density")


def p_sev(ax, t):
    d = pd.read_csv(t / "a_motor_severity_bands.csv").sort_values("claim_size_band")
    x = np.arange(len(d)); w = 0.38
    ax.bar(x - w / 2, d.claims_pct, w, color=C1, label="% of claims")
    ax.bar(x + w / 2, d.amount_pct, w, color=C2, label="% of claim EUR")
    ax.set_xticks(x); ax.set_xticklabels(d.claim_size_band.str[4:], rotation=30, ha="right")
    ax.set_ylabel("%"); ax.legend(frameon=False, fontsize=7)
    ax.set_title("Motor: 0.16% of claims (100k+) = 24.6% of EUR")


PANELS = [("med_smoker_charges", p_smoker), ("med_age_smoker", p_age), ("med_bmi_smoker", p_bmi),
          ("med_region", p_region), ("motor_freq_driver_age", p_drv), ("motor_freq_bonus_malus", p_bm),
          ("motor_freq_area", p_area), ("motor_severity_concentration", p_sev)]


def make_all(tables, out):
    tables, out = pathlib.Path(tables), pathlib.Path(out); out.mkdir(parents=True, exist_ok=True)
    for name, fn in PANELS:
        fig, ax = plt.subplots(figsize=(6.4, 3.6)); fn(ax, tables); save(fig, out / f"{name}.svg")
    k = pd.read_csv(tables / "a_kpi_headline.csv").iloc[0]
    fig, axes = plt.subplots(4, 2, figsize=(14, 17)); fig.subplots_adjust(hspace=0.6, wspace=0.3, top=0.9)
    for ax, (_, fn) in zip(axes.flat, PANELS):
        fn(ax, tables)
    cards = [("Insured people", f"{int(k.members):,}"), ("Avg charges", f"${k.avg_charges:,.0f}"),
             ("Smoker loading", f"{k.smoker_loading_x:.2f}x"), ("Motor policies", f"{int(k.policies):,}"),
             ("Policy-years", f"{k.exposure_years:,.0f}"), ("Claim freq.", f"{k.claim_frequency*100:.2f}/100"),
             ("Avg severity", f"EUR {k.avg_severity:,.0f}")]
    fig.suptitle("Insurance cost drivers & motor claim frequency (preview rendered from SQL outputs, full data)", fontsize=14, y=0.975)
    for i, (l, v) in enumerate(cards):
        x = 0.08 + i * 0.137
        fig.text(x, 0.94, v, fontsize=13, weight="bold", ha="center", color=C1)
        fig.text(x, 0.928, l, fontsize=9, ha="center", color="#555")
    save(fig, out / "dashboard.svg")
    print("charts ->", out, sorted(p.name for p in out.glob("*.svg")))


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    make_all(root / "results/tables", root / "results/charts")
