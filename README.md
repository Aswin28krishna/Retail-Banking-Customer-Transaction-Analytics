# Retail-Banking-Customer-Transaction-Analytics

<img width="905" height="511" alt="Capture 1" src="https://github.com/user-attachments/assets/83c12c81-8c0a-4d00-af57-a892a4e23e4d" />

<img width="1296" height="526" alt="Excel 1" src="https://github.com/user-attachments/assets/f078d26e-2648-490d-926b-68243ba1ecbb" />

#Insights Summary

**Data scope:** 100,000 transactions · Jan – Dec 2024 · 6 branches · 6 banks · 3 payment methods

---

## 1. Important data characteristic — read before presenting this project

Every transaction in this dataset has a **unique customer_id and account number** —
there are no repeat customers, no multi-transaction histories per person, and no
way to measure retention or individual customer engagement. This is a flat,
one-row-per-transaction synthetic ledger, not a relational customer database like
the Retail Banking project. All KPIs here are aggregated at the **branch, bank,
payment-method, and spend-category** level rather than the customer level — that's
the correct way to use this dataset, and worth stating plainly if asked about it
rather than implying customer-level segmentation was performed.

## 2. Overall Activity

- 100,000 transactions totaling **$254.9M** in value over 12 months (avg ~8,330 txns/month)
- Credit and debit volumes are almost perfectly balanced (50,028 Credit vs 49,972 Debit), and the **credit/debit ratio hovers around 1.0x** every month — this dataset reflects balanced synthetic generation rather than a real seasonal cash-flow pattern
- Average transaction value: **$2,549**

## 3. Branch Performance

- All 6 branches are nearly identical in volume and value — City Center Branch leads narrowly ($42.9M), North Branch trails slightly ($41.7M), but the spread is under 3%
- This even distribution suggests the data was generated without an intentional "flagship branch" bias — useful to note if a stakeholder asks "which branch is underperforming," since the honest answer is none significantly are

## 4. Bank-Level Comparison

- Kotak Mahindra Bank, Axis Bank, and the other 4 banks each process roughly 1/6 of total volume — again, near-uniform distribution
- If this feed represents a multi-bank aggregator product, the takeaway is that transaction share is evenly split across partner banks rather than concentrated

## 5. Payment Method Mix

- Debit Card ($85.2M), Credit Card ($84.9M), and Bank Transfer ($84.8M) are essentially tied in both volume and value — no single channel dominates
- This is useful for product strategy conversations: there's no obvious "declining channel" to deprioritize in this data

## 6. Spending & Income Categories

- Top categories by value: **Utility Bill Payment** ($13.2M, Credit), **Dinner at Restaurant** ($13.0M, Debit), **Client Payment** (~$12.9M combined), **Freelance Payment** ($12.9M, Debit)
- **Data quality note:** category labels don't reliably align with transaction type — e.g. "Salary Deposit" appears as both a Credit AND a Debit transaction in the data, which wouldn't happen in a real banking ledger (you don't debit a salary deposit). Flag this if presenting the project: it shows you validated the data and caught a synthetic-data artifact rather than treating every column at face value.

## 7. Transaction Timing & Size

- Wednesday and Sunday are the highest-volume days; Monday and Tuesday the lowest — differences are modest (~3%), so no strong weekday effect
- Transaction sizes cluster heavily in the **$2,500–$4,999** band (50,969 transactions, $191.3M — 75% of total value), with very few under $500
- Top 20 largest transactions (flagged in the SQL queries) sit right at the data's apparent generation ceiling (~$5,000), useful as a starting point for an anomaly-review or fraud-monitoring conversation even though this specific dataset shows no true outliers

## 8. Recommended Talking Points for This Project

1. Frame this project around **operational/transaction-level reporting** (branch ops, payment channel mix, category-level cash flow) rather than customer retention — that's what the data actually supports
2. Use the **data quality validation** (category/type mismatch, uniform distributions) as a concrete example of analytical rigor — it's a stronger story than presenting clean-looking numbers without scrutiny
3. The **near-uniform distributions** across branch/bank/method are themselves a finding: in real production data you'd expect to see meaningful variance, so calling out the synthetic nature here demonstrates you understand what real vs. generated data should look like

---

*See `sql/02_analysis_queries.sql` for the full query set behind every figure above, and the Power BI / Excel files in this project for interactive drill-down.*
