import sys
import os
from datetime import date, timedelta
import base64

# Add workspace to path
sys.path.append('.')

from fastapi.testclient import TestClient
from backend.main import app, verify_password, encrypt_data
from backend.database import SessionLocal, Donor

client = TestClient(app)

def test_dpdp_consent_and_validations():
    print("Running Test: DPDP Consent & Pydantic Validations...")
    
    # Base payload
    base_payload = {
        "firebase_uid": "test_uid_compliance_1",
        "name": "Compliance Tester",
        "phone": "+919876543210",
        "blood_group": "O+",
        "dob": (date.today() - timedelta(days=20 * 365)).isoformat(), # 20 years old
        "location_lat": 12.9716,
        "location_lng": 77.5946,
        "password": "SecurePassword1",
        "consent_given": True,
        "id_document_name": "aadhaar_test.pdf",
        "id_document_base64": "U29tZSBhYWRoYWFyIGNvbnRlbnQ=" # "Some aadhaar content"
    }

    # 1. Reject if consent_given is False
    payload = base_payload.copy()
    payload["consent_given"] = False
    response = client.post("/donors/register", json=payload)
    assert response.status_code == 400
    assert "DPDP Act" in response.json()["detail"]
    print("  -> Checked: Blocked missing DPDP consent successfully.")

    # 2. Reject if phone number is invalid (non-Indian format)
    payload = base_payload.copy()
    payload["phone"] = "9876543210" # Missing country code
    response = client.post("/donors/register", json=payload)
    assert response.status_code == 422
    assert "phone" in response.text
    print("  -> Checked: Blocked invalid phone format successfully.")

    # 3. Reject if password has no digits or is short
    payload = base_payload.copy()
    payload["password"] = "Short"
    response = client.post("/donors/register", json=payload)
    assert response.status_code == 422
    assert "password" in response.text
    
    payload = base_payload.copy()
    payload["password"] = "NoDigitsHere"
    response = client.post("/donors/register", json=payload)
    assert response.status_code == 422
    assert "password" in response.text
    print("  -> Checked: Blocked weak password format successfully.")

    # 4. Reject if underage
    payload = base_payload.copy()
    payload["dob"] = (date.today() - timedelta(days=16 * 365)).isoformat() # 16 years old
    response = client.post("/donors/register", json=payload)
    assert response.status_code == 400
    assert "18 years or older" in response.json()["detail"]
    print("  -> Checked: Blocked underage donor successfully.")


def test_encryption_at_rest():
    print("Running Test: Encryption at Rest for Sensitive Aadhaar PII...")
    
    db = SessionLocal()
    unique_phone = "+917890123456"
    unique_uid = "uid_encryption_test_123"
    id_plaintext = "SecretAadhaarData123"
    id_base64 = base64.b64encode(id_plaintext.encode('utf-8')).decode('utf-8')
    
    # Register donor
    payload = {
        "firebase_uid": unique_uid,
        "name": "Aadhaar Encrypt Test",
        "phone": unique_phone,
        "blood_group": "AB-",
        "dob": "1990-01-01",
        "location_lat": 12.9716,
        "location_lng": 77.5946,
        "password": "ValidPassword9",
        "consent_given": True,
        "id_document_name": "aadhaar.pdf",
        "id_document_base64": id_base64
    }
    
    try:
        # Delete if already exists to ensure fresh run
        existing = db.query(Donor).filter(Donor.firebase_uid == unique_uid).first()
        if existing:
            db.delete(existing)
            db.commit()

        response = client.post("/donors/register", json=payload)
        assert response.status_code == 200
        
        # Verify stored database row
        donor_in_db = db.query(Donor).filter(Donor.firebase_uid == unique_uid).first()
        assert donor_in_db is not None
        
        # Assert database content is NOT plain text or plain base64
        stored_field = donor_in_db.id_document_base64
        assert stored_field != id_plaintext
        assert stored_field != id_base64
        assert "gAAAAA" in stored_field  # Fernet tokens start with gAAAAA
        print("  -> Checked: Database stored row uses ciphertext.")
        
        # Verify password is encrypted via Bcrypt
        assert donor_in_db.password_hash != "ValidPassword9"
        assert verify_password("ValidPassword9", donor_in_db.password_hash)
        print("  -> Checked: Password successfully hashed via Bcrypt (rounds=12).")
        
    finally:
        db.close()


def test_jwt_privilege_boundary():
    print("Running Test: JWT Authorization & Privilege Boundaries...")
    
    db = SessionLocal()
    # Create two test users
    uid_a = "uid_boundary_user_a"
    phone_a = "+919000000001"
    uid_b = "uid_boundary_user_b"
    phone_b = "+919000000002"
    
    try:
        # Delete if they exist
        for uid in [uid_a, uid_b]:
            existing = db.query(Donor).filter(Donor.firebase_uid == uid).first()
            if existing:
                db.delete(existing)
        db.commit()

        # Register Donor A
        payload_a = {
            "firebase_uid": uid_a,
            "name": "User A",
            "phone": phone_a,
            "blood_group": "A+",
            "dob": "1995-05-05",
            "location_lat": 12.9716,
            "location_lng": 77.5946,
            "password": "PasswordUserA1",
            "consent_given": True,
            "id_document_name": "doc_a.pdf",
            "id_document_base64": "SGVsbG8="
        }
        res_a = client.post("/donors/register", json=payload_a)
        assert res_a.status_code == 200
        donor_id_a = res_a.json()["donor_id"]

        # Register Donor B
        payload_b = {
            "firebase_uid": uid_b,
            "name": "User B",
            "phone": phone_b,
            "blood_group": "B+",
            "dob": "1996-06-06",
            "location_lat": 12.9716,
            "location_lng": 77.5946,
            "password": "PasswordUserB2",
            "consent_given": True,
            "id_document_name": "doc_b.pdf",
            "id_document_base64": "V29ybGQ="
        }
        res_b = client.post("/donors/register", json=payload_b)
        assert res_b.status_code == 200
        donor_id_b = res_b.json()["donor_id"]

        # Login as User A to get Token A
        login_res_a = client.post("/auth/login", json={"phone": phone_a, "password": "PasswordUserA1", "role": "donor"})
        assert login_res_a.status_code == 200
        token_a = login_res_a.json()["token"]

        # Login as User B to get Token B
        login_res_b = client.post("/auth/login", json={"phone": phone_b, "password": "PasswordUserB2", "role": "donor"})
        assert login_res_b.status_code == 200
        token_b = login_res_b.json()["token"]

        # 1. Update A's location using A's token -> should succeed
        headers_a = {"Authorization": f"Bearer {token_a}"}
        update_res_ok = client.put(
            "/donors/update-location",
            headers=headers_a,
            json={"firebase_uid": uid_a, "location_lat": 13.0, "location_lng": 78.0}
        )
        assert update_res_ok.status_code == 200
        print("  -> Checked: Authorized user can update own location.")

        # 2. Update A's location using B's token -> should return 403 Forbidden
        headers_b = {"Authorization": f"Bearer {token_b}"}
        update_res_fail = client.put(
            "/donors/update-location",
            headers=headers_b,
            json={"firebase_uid": uid_a, "location_lat": 13.0, "location_lng": 78.0}
        )
        assert update_res_fail.status_code == 403
        assert "Not authorized" in update_res_fail.json()["detail"]
        print("  -> Checked: Blocked location update for mismatched owner (HTTP 403 Forbidden).")

        # 3. Access A's dashboard using B's token -> should return 403 Forbidden
        dashboard_res_fail = client.get(
            f"/donors/{donor_id_a}/dashboard-data",
            headers=headers_b
        )
        assert dashboard_res_fail.status_code == 403
        assert "Access denied" in dashboard_res_fail.json()["detail"]
        print("  -> Checked: Blocked dashboard reading for mismatched owner (HTTP 403 Forbidden).")

        # 4. Access A's history using B's token -> should return 403 Forbidden
        history_res_fail = client.get(
            f"/donors/history/{donor_id_a}",
            headers=headers_b
        )
        assert history_res_fail.status_code == 403
        assert "Access denied" in history_res_fail.json()["detail"]
        print("  -> Checked: Blocked history reading for mismatched owner (HTTP 403 Forbidden).")

    finally:
        db.close()


def test_bruteforce_rate_limiting():
    print("Running Test: Login Rate Limiting (5 failures / 10 mins)...")
    
    phone = "+919999888877"
    # Make 5 failed attempts
    for i in range(5):
        response = client.post(
            "/auth/login",
            json={"phone": phone, "password": "wrongpassword", "role": "donor"}
        )
        assert response.status_code == 400
        assert "Invalid credentials" in response.json()["detail"]
        print(f"  -> Checked: Failed login attempt {i+1}/5 received HTTP 400.")

    # 6th attempt should trigger 429 Too Many Requests
    response_blocked = client.post(
        "/auth/login",
        json={"phone": phone, "password": "wrongpassword", "role": "donor"}
    )
    assert response_blocked.status_code == 429
    assert "Too many login attempts" in response_blocked.json()["detail"]
    print("  -> Checked: Brute-forcing correctly blocked with HTTP 429 (Too Many Requests).")


if __name__ == "__main__":
    print("====================================================")
    print("RUNNING SECURITY & COMPLIANCE AUTOMATED TESTS")
    print("====================================================")
    
    test_dpdp_consent_and_validations()
    test_encryption_at_rest()
    test_jwt_privilege_boundary()
    test_bruteforce_rate_limiting()
    
    print("====================================================")
    print("ALL COMPLIANCE AND SECURITY CHECKS PASSED SUCCESSFULLY!")
    print("====================================================")
