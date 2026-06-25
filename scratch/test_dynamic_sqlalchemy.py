import os
import sys

# Add current directory to path
sys.path.append(os.getcwd())

from sqlalchemy import Column, Boolean, String
from backend.database import Donor, engine
from sqlalchemy.sql import text

# Dynamically add columns
Donor.id_document_verified = Column(Boolean, default=False, nullable=False)
Donor.id_document_confidence = Column(String(50), default="unverified", nullable=True)

print("Columns added to Donor class.")
print("id_document_verified:", hasattr(Donor, "id_document_verified"))
print("id_document_confidence:", hasattr(Donor, "id_document_confidence"))

# Test query execution
try:
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE donors ADD COLUMN IF NOT EXISTS id_document_verified BOOLEAN DEFAULT FALSE;"))
        conn.execute(text("ALTER TABLE donors ADD COLUMN IF NOT EXISTS id_document_confidence VARCHAR(50) DEFAULT 'unverified';"))
    print("Database migration executed successfully.")
except Exception as e:
    print("Migration failed:", e)
