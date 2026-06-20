"""
Rebuilds retail_banking.db locally from your raw CSV files + the schema/
queries in this package. Run this once on your machine (not needed if
you just want the SQL files for reference, or are loading directly into
MySQL/PostgreSQL/SQL Server instead).

Usage:
    pip install pandas
    python build_database.py /path/to/csv/folder

Expects these files in the given folder (the originals you already have):
    customer_profiles.csv
    bank_accounts.csv
    transaction_codes.csv
    account_transactions.csv
"""
import sys, sqlite3, pandas as pd
from pathlib import Path

src = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
conn = sqlite3.connect("retail_banking.db")

pd.read_csv(src / "customer_profiles.csv").to_sql("customers", conn, index=False, if_exists="replace")
pd.read_csv(src / "bank_accounts.csv").to_sql("accounts", conn, index=False, if_exists="replace")
pd.read_csv(src / "transaction_codes.csv").to_sql("transaction_codes", conn, index=False, if_exists="replace")

for chunk in pd.read_csv(src / "account_transactions.csv", chunksize=200_000, low_memory=False):
    chunk.to_sql("transactions", conn, index=False, if_exists="append")

cur = conn.cursor()
cur.execute("CREATE INDEX idx_acc_cust ON accounts(customer_id)")
cur.execute("CREATE INDEX idx_txn_acc ON transactions(account_id)")
cur.execute("CREATE INDEX idx_txn_code ON transactions(transaction_code)")
cur.execute("CREATE INDEX idx_txn_date ON transactions(created_time)")
conn.commit()

# Apply the views/queries from 02_analysis_queries.sql
import re
sql = (Path(__file__).parent / "02_analysis_queries.sql").read_text()
sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
for stmt in [s.strip() for s in sql.split(";") if s.strip()]:
    if stmt.upper().startswith("CREATE VIEW"):
        cur.execute(stmt)
conn.commit()
conn.close()
print("retail_banking.db built successfully.")
