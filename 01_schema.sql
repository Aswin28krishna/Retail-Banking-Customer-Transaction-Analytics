/* =====================================================================
   RETAIL BANKING CUSTOMER & TRANSACTION ANALYTICS
   Schema Definition
   Engine: SQLite (portable across MySQL/PostgreSQL/SQL Server with
   minor type adjustments — see notes at bottom)
   ===================================================================== */

DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS transaction_codes;

CREATE TABLE customers (
    customer_id     TEXT PRIMARY KEY,
    national_id     TEXT NOT NULL,
    birth_date      DATE NOT NULL,
    city            TEXT,
    state           TEXT
);

CREATE TABLE accounts (
    account_id      TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(customer_id),
    account_type    TEXT NOT NULL,      -- Savings, Loan, FixedDeposit
    creation_date   DATE NOT NULL,
    account_status  TEXT NOT NULL,      -- Active, Inactive
    balance         REAL NOT NULL,
    loan_amount     REAL,               -- Loan accounts only
    term_months     REAL,               -- Loan accounts only
    interest_rate   REAL                -- Loan accounts only
);

CREATE TABLE transaction_codes (
    transaction_code TEXT PRIMARY KEY,
    label             TEXT NOT NULL,
    account_type      TEXT,
    transaction_type  TEXT,             -- Debit / Credit
    channel           TEXT
);

CREATE TABLE transactions (
    transaction_id          TEXT PRIMARY KEY,
    account_id              TEXT NOT NULL REFERENCES accounts(account_id),
    linked_transaction_id   TEXT,        -- pairs transfers/interbank legs
    created_time            DATETIME NOT NULL,
    transaction_type        TEXT NOT NULL,  -- Debit / Credit
    transaction_code        TEXT NOT NULL REFERENCES transaction_codes(transaction_code),
    amount                  REAL NOT NULL,
    channel                 TEXT
);

CREATE INDEX idx_accounts_customer   ON accounts(customer_id);
CREATE INDEX idx_txn_account         ON transactions(account_id);
CREATE INDEX idx_txn_code            ON transactions(transaction_code);
CREATE INDEX idx_txn_date            ON transactions(created_time);

/* ---------------------------------------------------------------------
   PORTING NOTES
   - SQLite TEXT -> VARCHAR(36) for UUID columns in MySQL/Postgres/SQLServer
   - DATE/DATETIME -> use native DATE/DATETIME2 types
   - Add FOREIGN KEY ... ON DELETE/UPDATE clauses as needed per RDBMS
   --------------------------------------------------------------------- */
