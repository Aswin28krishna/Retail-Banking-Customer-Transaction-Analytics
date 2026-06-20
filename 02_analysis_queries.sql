/* =====================================================================
   RETAIL BANKING CUSTOMER & TRANSACTION ANALYTICS
   Analysis Queries
   Note: the dataset has no explicit "branch" dimension — the closest
   proxy is transactions.channel (ATM / Branch / MobileApp / OnlineBanking
   / InterbankPortal / System). Queries below use "channel" as the
   branch-performance equivalent; swap in a real branch_id if your
   production data has one.
   ===================================================================== */

/* ---------------------------------------------------------------------
 1. CUSTOMER 360 VIEW
 One row per customer with account count, total balance, lifetime
 transaction volume, last activity date, and tenure.
 Balance and transaction metrics are pre-aggregated in separate CTEs
 BEFORE joining customer-to-account-to-transaction (1:many:many), to
 avoid fan-out duplication of balance across transaction rows.
--------------------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_customer_360 AS
WITH acct_agg AS (
    SELECT customer_id,
           COUNT(*)        AS num_accounts,
           SUM(balance)     AS total_balance,
           MIN(creation_date) AS first_account_date
    FROM accounts
    GROUP BY customer_id
),
txn_agg AS (
    SELECT a.customer_id,
           COUNT(t.transaction_id) AS lifetime_txn_count,
           SUM(CASE WHEN t.transaction_type = 'Credit' THEN t.amount ELSE 0 END) AS lifetime_credits,
           SUM(CASE WHEN t.transaction_type = 'Debit'  THEN t.amount ELSE 0 END) AS lifetime_debits,
           MAX(t.created_time) AS last_transaction_date
    FROM accounts a
    JOIN transactions t ON t.account_id = a.account_id
    GROUP BY a.customer_id
)
SELECT
    c.customer_id,
    c.city,
    c.state,
    CAST((julianday('now') - julianday(c.birth_date)) / 365.25 AS INT) AS age,
    COALESCE(aa.num_accounts, 0)            AS num_accounts,
    COALESCE(aa.total_balance, 0)           AS total_balance,
    aa.first_account_date,
    COALESCE(ta.lifetime_txn_count, 0)      AS lifetime_txn_count,
    COALESCE(ta.lifetime_credits, 0)        AS lifetime_credits,
    COALESCE(ta.lifetime_debits, 0)         AS lifetime_debits,
    ta.last_transaction_date
FROM customers c
LEFT JOIN acct_agg aa ON aa.customer_id = c.customer_id
LEFT JOIN txn_agg ta ON ta.customer_id = c.customer_id;


/* ---------------------------------------------------------------------
 2. CUSTOMER ACTIVITY STATUS (Active / Moderate / Low Engagement)
 NOTE: this dataset is dense — every customer transacted within the
 last 10 days of the data window, so simple "days since last txn"
 thresholds don't discriminate at all. The meaningful engagement
 signal here is (a) account_status flags on the account table and
 (b) lifetime transaction FREQUENCY, which ranges 49 - 13,137 txns
 per customer. We segment on frequency quartiles + account status.
 In a production feed with realistic churn, swap this back to a
 recency-based "days since last txn" rule.
--------------------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_customer_activity AS
WITH max_date AS (SELECT MAX(created_time) AS d FROM transactions),
freq AS (
    SELECT customer_id,
           NTILE(4) OVER (ORDER BY lifetime_txn_count) AS freq_quartile
    FROM v_customer_360
),
acct_flag AS (
    SELECT customer_id,
           SUM(CASE WHEN account_status='Active' THEN 1 ELSE 0 END)   AS active_accounts,
           SUM(CASE WHEN account_status='Inactive' THEN 1 ELSE 0 END) AS inactive_accounts
    FROM accounts
    GROUP BY customer_id
)
SELECT
    v.customer_id,
    v.last_transaction_date,
    CAST((julianday((SELECT d FROM max_date)) - julianday(v.last_transaction_date)) AS INT) AS days_since_last_txn,
    f.freq_quartile,
    af.active_accounts,
    af.inactive_accounts,
    CASE
        WHEN v.last_transaction_date IS NULL THEN 'Never Active'
        WHEN af.active_accounts = 0 THEN 'Inactive'
        WHEN f.freq_quartile = 1 AND af.inactive_accounts > 0 THEN 'Dormant'
        WHEN f.freq_quartile = 1 THEN 'Low Engagement'
        WHEN f.freq_quartile IN (2,3) THEN 'Moderate Engagement'
        ELSE 'Active'
    END AS activity_segment
FROM v_customer_360 v
JOIN freq f ON f.customer_id = v.customer_id
JOIN acct_flag af ON af.customer_id = v.customer_id;


/* ---------------------------------------------------------------------
 3. CUSTOMER VALUE SEGMENTATION (High / Medium / Low)
 Based on total balance quartiles.
--------------------------------------------------------------------- */
CREATE VIEW IF NOT EXISTS v_customer_value_segment AS
WITH ranked AS (
    SELECT customer_id, total_balance,
           NTILE(4) OVER (ORDER BY total_balance) AS quartile
    FROM v_customer_360
)
SELECT
    customer_id,
    total_balance,
    CASE
        WHEN quartile = 4 THEN 'High Value'
        WHEN quartile = 3 THEN 'Medium-High Value'
        WHEN quartile = 2 THEN 'Medium-Low Value'
        ELSE 'Low Value'
    END AS value_segment
FROM ranked;


/* ---------------------------------------------------------------------
 4. COMBINED RFM-STYLE SEGMENTATION
 Joins activity + value + frequency into one strategic segment label
 used for retention / cross-sell / marketing targeting.
--------------------------------------------------------------------- */
SELECT
    cs.customer_id,
    ca.activity_segment,
    vs.value_segment,
    c360.lifetime_txn_count,
    CASE
        WHEN ca.activity_segment = 'Inactive' AND vs.value_segment IN ('High Value','Medium-High Value')
            THEN 'Win-Back Priority'
        WHEN ca.activity_segment = 'Active' AND vs.value_segment = 'High Value'
            THEN 'VIP / Retain'
        WHEN ca.activity_segment = 'Active' AND vs.value_segment IN ('Low Value','Medium-Low Value')
            THEN 'Cross-Sell Opportunity'
        WHEN ca.activity_segment IN ('Dormant','Never Active')
            THEN 'Re-engagement Campaign'
        ELSE 'Standard'
    END AS strategic_segment
FROM customers cs
JOIN v_customer_activity ca ON ca.customer_id = cs.customer_id
JOIN v_customer_value_segment vs ON vs.customer_id = cs.customer_id
JOIN v_customer_360 c360 ON c360.customer_id = cs.customer_id;


/* ---------------------------------------------------------------------
 5. MONTHLY TRANSACTION VOLUME & VALUE TREND
--------------------------------------------------------------------- */
SELECT
    strftime('%Y-%m', created_time) AS month,
    COUNT(*)                        AS txn_count,
    SUM(amount)                     AS txn_value,
    SUM(CASE WHEN transaction_type='Credit' THEN amount ELSE 0 END) AS credit_value,
    SUM(CASE WHEN transaction_type='Debit'  THEN amount ELSE 0 END) AS debit_value
FROM transactions
GROUP BY month
ORDER BY month;


/* ---------------------------------------------------------------------
 6. CREDIT / DEBIT RATIO BY MONTH
--------------------------------------------------------------------- */
SELECT
    strftime('%Y-%m', created_time) AS month,
    ROUND(SUM(CASE WHEN transaction_type='Credit' THEN amount ELSE 0 END), 2) AS credit_value,
    ROUND(SUM(CASE WHEN transaction_type='Debit'  THEN amount ELSE 0 END), 2) AS debit_value,
    ROUND(
        SUM(CASE WHEN transaction_type='Credit' THEN amount ELSE 0 END) * 1.0 /
        NULLIF(SUM(CASE WHEN transaction_type='Debit' THEN amount ELSE 0 END), 0)
    , 2) AS credit_debit_ratio
FROM transactions
GROUP BY month
ORDER BY month;


/* ---------------------------------------------------------------------
 7. CHANNEL ("BRANCH") PERFORMANCE
 Volume, value, and unique customers served per channel.
--------------------------------------------------------------------- */
SELECT
    t.channel,
    COUNT(*)                          AS txn_count,
    SUM(t.amount)                     AS txn_value,
    COUNT(DISTINCT a.customer_id)     AS unique_customers,
    ROUND(AVG(t.amount), 2)           AS avg_txn_value
FROM transactions t
JOIN accounts a ON a.account_id = t.account_id
GROUP BY t.channel
ORDER BY txn_value DESC;


/* ---------------------------------------------------------------------
 8. TRANSACTION TYPE / CODE BREAKDOWN
--------------------------------------------------------------------- */
SELECT
    tc.label,
    t.transaction_type,
    COUNT(*)        AS txn_count,
    SUM(t.amount)   AS txn_value,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM transactions), 2) AS pct_of_total_txns
FROM transactions t
JOIN transaction_codes tc ON tc.transaction_code = t.transaction_code
GROUP BY tc.label, t.transaction_type
ORDER BY txn_value DESC;


/* ---------------------------------------------------------------------
 9. ACCOUNT BALANCE DISTRIBUTION BY ACCOUNT TYPE
--------------------------------------------------------------------- */
SELECT
    account_type,
    account_status,
    COUNT(*)             AS num_accounts,
    ROUND(SUM(balance),2) AS total_balance,
    ROUND(AVG(balance),2) AS avg_balance,
    ROUND(MIN(balance),2) AS min_balance,
    ROUND(MAX(balance),2) AS max_balance
FROM accounts
GROUP BY account_type, account_status
ORDER BY account_type, account_status;


/* ---------------------------------------------------------------------
 10. NEW ACCOUNT GROWTH (ACQUISITION TREND)
--------------------------------------------------------------------- */
SELECT
    strftime('%Y-%m', creation_date) AS month,
    account_type,
    COUNT(*) AS new_accounts
FROM accounts
GROUP BY month, account_type
ORDER BY month;


/* ---------------------------------------------------------------------
 11. GEOGRAPHIC PERFORMANCE (STATE / CITY LEVEL)
 Aggregates are pre-rolled up per CTE to avoid fan-out duplication
 from the accounts <-> transactions one-to-many join.
--------------------------------------------------------------------- */
WITH acct_bal AS (
    SELECT customer_id, COUNT(*) AS num_accounts, SUM(balance) AS total_balance
    FROM accounts GROUP BY customer_id
),
txn_agg AS (
    SELECT a.customer_id, COUNT(*) AS txn_count, SUM(t.amount) AS txn_value
    FROM transactions t JOIN accounts a ON a.account_id = t.account_id
    GROUP BY a.customer_id
)
SELECT
    c.state,
    COUNT(DISTINCT c.customer_id)        AS num_customers,
    SUM(ab.num_accounts)                 AS num_accounts,
    ROUND(SUM(ab.total_balance), 2)      AS total_balance,
    SUM(ta.txn_count)                    AS txn_count,
    ROUND(SUM(ta.txn_value), 2)          AS txn_value
FROM customers c
JOIN acct_bal ab ON ab.customer_id = c.customer_id
LEFT JOIN txn_agg ta ON ta.customer_id = c.customer_id
GROUP BY c.state
ORDER BY total_balance DESC;


/* ---------------------------------------------------------------------
 12. AGE-BAND CUSTOMER BEHAVIOR
--------------------------------------------------------------------- */
SELECT
    CASE
        WHEN age < 25 THEN 'Under 25'
        WHEN age BETWEEN 25 AND 34 THEN '25-34'
        WHEN age BETWEEN 35 AND 44 THEN '35-44'
        WHEN age BETWEEN 45 AND 54 THEN '45-54'
        WHEN age BETWEEN 55 AND 64 THEN '55-64'
        ELSE '65+'
    END AS age_band,
    COUNT(*)                       AS num_customers,
    ROUND(AVG(total_balance), 2)   AS avg_balance,
    ROUND(AVG(lifetime_txn_count), 1) AS avg_txn_count
FROM v_customer_360
GROUP BY age_band
ORDER BY age_band;


/* ---------------------------------------------------------------------
 13. TOP 20 HIGH-VALUE CUSTOMERS (for relationship manager outreach)
--------------------------------------------------------------------- */
SELECT
    c360.customer_id,
    c.city, c.state,
    c360.num_accounts,
    ROUND(c360.total_balance, 2)        AS total_balance,
    c360.lifetime_txn_count,
    ca.activity_segment
FROM v_customer_360 c360
JOIN customers c ON c.customer_id = c360.customer_id
JOIN v_customer_activity ca ON ca.customer_id = c360.customer_id
ORDER BY c360.total_balance DESC
LIMIT 20;


/* ---------------------------------------------------------------------
 14. AT-RISK / CHURN CANDIDATES
 High historical value but now inactive — top retention priority.
--------------------------------------------------------------------- */
SELECT
    c360.customer_id,
    c.city, c.state,
    ROUND(c360.total_balance, 2) AS total_balance,
    ca.days_since_last_txn,
    ca.activity_segment
FROM v_customer_360 c360
JOIN customers c ON c.customer_id = c360.customer_id
JOIN v_customer_activity ca ON ca.customer_id = c360.customer_id
WHERE ca.activity_segment IN ('Inactive', 'Dormant')
ORDER BY c360.total_balance DESC
LIMIT 50;


/* ---------------------------------------------------------------------
 15. LOAN PORTFOLIO SNAPSHOT
--------------------------------------------------------------------- */
SELECT
    COUNT(*)                       AS num_loans,
    ROUND(SUM(loan_amount), 2)     AS total_loan_book,
    ROUND(AVG(interest_rate), 2)   AS avg_interest_rate,
    ROUND(AVG(term_months), 1)     AS avg_term_months,
    SUM(CASE WHEN account_status='Active' THEN 1 ELSE 0 END)   AS active_loans,
    SUM(CASE WHEN account_status='Inactive' THEN 1 ELSE 0 END) AS closed_loans
FROM accounts
WHERE account_type = 'Loan';
