import sys
sys.path.append('.')
from fastapi.testclient import TestClient
from backend.main import app, create_jwt_token
import pytest

client = TestClient(app)

# Generate mock JWT tokens for testing role-based security
bank_headers = {"Authorization": f"Bearer {create_jwt_token(1, 'bank_admin')}"}
coord_headers = {"Authorization": f"Bearer {create_jwt_token(999, 'coordinator')}"}
donor_headers = {"Authorization": f"Bearer {create_jwt_token(1, 'donor')}"}

def test_auth_verify_token():
    # Test mock token verify
    response = client.post("/auth/verify-token", json={"id_token": "mock_token_donor"})
    assert response.status_code == 200
    data = response.json()
    assert data["role"] == "donor"
    assert "is_new_user" in data

def test_auth_profile_setup():
    response = client.post(
        "/auth/profile-setup", 
        json={
            "firebase_uid": "mock_uid_new_user",
            "role": "donor",
            "name": "Alex Mercer",
            "blood_group": "AB-",
            "dob": "1995-04-12",
            "city": "Delhi NCR",
            "location_lat": 28.6139,
            "location_lng": 77.2090,
            "phone": "+919888877777"
        }
    )
    assert response.status_code == 200
    assert response.json()["status"] == "success"

def test_get_inventory():
    response = client.get("/inventory/1", headers=bank_headers)
    assert response.status_code == 200
    data = response.json()
    assert "O+" in data
    assert "units_available" in data["O+"]

def test_get_bssi():
    response = client.get("/bssi/1")
    assert response.status_code == 200
    data = response.json()
    assert "O+" in data
    assert type(data["O+"]) in [int, float]

def test_get_forecast():
    response = client.get("/forecast/1/O+")
    assert response.status_code == 200
    data = response.json()
    assert type(data) is list
    if len(data) > 0:
        assert "yhat" in data[0]
        assert "date" in data[0]

def test_get_redistribution_suggestions():
    # Ensure suggesting is working (at least returns list)
    response = client.get("/redistribution/suggest/1/O+")
    assert response.status_code == 200
    assert type(response.json()) is list

def test_get_eligible_donors():
    response = client.get("/donors/eligible/O+/1", headers=bank_headers)
    assert response.status_code == 200
    data = response.json()
    assert type(data) is list
    if len(data) > 0:
        assert "donor_id" in data[0]
        assert "priority_score" in data[0]

def test_trigger_alert():
    # Trigger alert for bank 1, group O+
    response = client.post("/alerts/trigger/1/O+", headers=bank_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ["success", "no_eligible_donors"]

if __name__ == "__main__":
    print("Running automated endpoint tests...")
    test_auth_verify_token()
    print("Pass: /auth/verify-token")
    test_auth_profile_setup()
    print("Pass: /auth/profile-setup")
    test_get_inventory()
    print("Pass: /inventory/{bank_id}")
    test_get_bssi()
    print("Pass: /bssi/{bank_id}")
    test_get_forecast()
    print("Pass: /forecast/{bank_id}/{blood_group}")
    test_get_redistribution_suggestions()
    print("Pass: /redistribution/suggest/{bank_id}/{blood_group}")
    test_get_eligible_donors()
    print("Pass: /donors/eligible/{blood_group}/{bank_id}")
    test_trigger_alert()
    print("Pass: /alerts/trigger/{bank_id}/{blood_group}")
    print("\nALL BACKEND ROUTE VERIFICATIONS COMPLETED SUCCESSFULLY!")
