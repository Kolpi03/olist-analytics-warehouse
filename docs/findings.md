# Findings memo

**To:** Marketplace Operations
**Re:** What actually drives repeat purchase — and what doesn't
**Data:** 99,441 orders, Sep 2016 – Oct 2018, R$15,737,668 GMV

## Bottom line

Late delivery devastates customer satisfaction and has almost no effect on
whether customers come back — because at Olist, essentially nobody comes back.
The repeat purchase rate is 3.12%, and it is statistically indistinguishable
across every review score from 1 to 5.

## What we found

**1. Delivery timing is the dominant driver of review scores.**
Verified directly: orders arriving 10+ days early average a **4.32** review;
orders arriving more than 14 days late average **1.73**. Across the full
delay range, Pearson r = -0.291 (p < 1e-300, n = 93,607). Nothing else in
the dataset comes close to this effect size.

**2. Review scores do not predict repeat purchase.**
Repeat rate by first-order review score: 3.23% (5★), 2.86% (4★), 2.93% (3★),
2.94% (2★), 3.10% (1★). chi-square = 7.82, dof = 4, p = 0.098 — not
significant, and not monotonic. Furious customers return at the same rate as
delighted ones.

**3. The late-delivery churn effect is real but commercially trivial.**
Customers whose first order arrived late repeat at 2.56% vs 3.13% for those
whose first order was on time (chi-square = 7.57, p = 0.006). Applied to the
7,592 affected customers at the mean repeat-order value, total recoverable
revenue is approximately **R$6,235** — 0.04% of GMV.

**4. Lateness is concentrated, not systemic.**
103 of 2,970 sellers (3.5%) account for half of all late deliveries. Ten
sellers exceed 25% late at 30+ orders and are flagged ESCALATE in the live
dashboard.

**5. Delivery estimates are heavily padded.**
São Paulo promises 18.8 days and delivers in 8.3. Rondônia promises 38.4 and
delivers in 18.9. Nationally the pad averages over 11 days.

## What to do

| Action | Owner | Effort | Expected impact |
|---|---|---|---|
| A/B test tighter delivery estimates in SP/MG/PR | Product | Medium | Unmeasured here; largest untested lever |
| SLA for the 10 ESCALATE sellers | Seller Ops | Low | Half the late-delivery volume sits in ~100 accounts |
| Lengthen quoted windows in PI, CE, AL | Logistics | Low | Directly reduces the 1-2 star driver |
| **Do not** fund service-recovery retention campaigns | — | — | Headroom is R$6K; the premise is unsupported |

## What would change my mind

If an experiment that padded delivery estimates by three extra days moved
repeat rate measurably, the causal story is stronger than this dataset can
show. Equally, if Olist has repeat-purchase data beyond October 2018, the
late cohorts here are censored and the retention picture could look
different.

The stronger test is on the acquisition side, which this dataset cannot see:
review scores likely affect marketplace ranking and new-buyer trust. That is
where delivery quality probably pays for itself — not in retention.

---
*Verified end-to-end against the real Olist dataset: 14/14 data quality
checks pass, all 9 source row counts match exactly, all figures in this
memo were re-run directly against the loaded warehouse.*
