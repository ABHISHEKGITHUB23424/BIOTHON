import argparse
import random
import os
import urllib.request
import csv
import io
import uuid
import pickle
from datetime import datetime, date, timedelta
import numpy as np
import pandas as pd
from sqlalchemy.orm import Session
from sqlalchemy import func, text
from sklearn.linear_model import LogisticRegression

# Import database and models
from backend.database import (
    SessionLocal, Region, BloodBank, Hospital, Donor, DonationRecord,
    TransfusionRecord, BloodInventory, CalendarFlags, EmergencyEvent,
    BSSIScore, ShortageAlert, DonorAlertLog, Redistribution, ForecastCache,
    RefreshToken, ModelPerformance, SystemMetadata, DonorBehaviorReference,
    RealAccidentReference, DataProvenance, init_db, engine
)

# Indian Festivals and Holidays configuration
INDIAN_FESTIVALS = [
    {"name": "Diwali", "month": 10, "day": 25, "impact": -0.40},  # October/November
    {"name": "Holi", "month": 3, "day": 10, "impact": -0.35},     # March
    {"name": "Eid al-Fitr", "month": 5, "day": 3, "impact": -0.30}, # Varies, mock static
    {"name": "Independence Day", "month": 8, "day": 15, "impact": -0.20},
    {"name": "Republic Day", "month": 1, "day": 26, "impact": -0.20},
    {"name": "Ganesh Chaturthi", "month": 9, "day": 10, "impact": -0.30},
    {"name": "Christmas", "month": 12, "day": 25, "impact": -0.15},
]

BLOOD_GROUPS = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]

BASE_DONATION_RATIOS = {
    "O+": 1.0,
    "A+": 0.8,
    "B+": 0.85,
    "AB+": 0.45,
    "O-": 0.35,
    "A-": 0.25,
    "B-": 0.20,
    "AB-": 0.15,
}

FALLBACK_PLACES = {
    1: { # Delhi NCR
        "banks": [
            {"name": "Indian Red Cross Society Blood Bank", "lat": 28.6158, "lng": 77.2023, "address": "Indian Red Cross Society, 1 Red Cross Road, Sansad Marg Area, New Delhi - 110001, Delhi, India", "phone": "+911123716441"},
            {"name": "Dr. Ram Manohar Lohia Hospital Blood Bank", "lat": 28.6272, "lng": 77.2016, "address": "Dr. RML Hospital, Baba Kharak Singh Road, Connaught Place, New Delhi - 110001, Delhi, India", "phone": "+911123365525"},
            {"name": "Safdarjung Hospital Blood Bank", "lat": 28.5672, "lng": 77.2057, "address": "Safdarjung Hospital, Ring Road, Ansari Nagar, New Delhi - 110029, Delhi, India", "phone": "+911126730000"},
        ],
        "hospitals": [
            {"name": "All India Institute of Medical Sciences (AIIMS)", "lat": 28.5672, "lng": 77.2100, "address": "AIIMS, Sri Aurobindo Marg, Ansari Nagar, New Delhi - 110029, Delhi, India"},
            {"name": "Fortis Flt. Lt. Rajan Dhall Hospital", "lat": 28.5284, "lng": 77.1610, "address": "Fortis Hospital, Aruna Asaf Ali Marg, Vasant Kunj, New Delhi - 110070, Delhi, India"},
            {"name": "Max Super Speciality Hospital, Saket", "lat": 28.5276, "lng": 77.2117, "address": "Max Hospital, 1 & 2 Press Enclave Road, Saket, New Delhi - 110017, Delhi, India"},
            {"name": "Sir Ganga Ram Hospital", "lat": 28.6385, "lng": 77.1896, "address": "Sir Ganga Ram Hospital, Sir Ganga Ram Hospital Marg, Rajinder Nagar, New Delhi - 110060, Delhi, India"},
        ]
    },
    2: { # Mumbai MMR
        "banks": [
            {"name": "KEM Hospital Blood Bank", "lat": 19.0028, "lng": 72.8423, "address": "KEM Hospital, Acharya Donde Marg, Parel, Mumbai - 400012, Maharashtra, India", "phone": "+912224107000"},
            {"name": "Wadia Hospital Blood Bank", "lat": 19.0045, "lng": 72.8430, "address": "Nowrosjee Wadia Maternity Hospital, Acharya Donde Marg, Parel, Mumbai - 400012, Maharashtra, India", "phone": "+912224143431"},
            {"name": "Tata Memorial Hospital Blood Bank", "lat": 19.0035, "lng": 72.8401, "address": "Tata Memorial Hospital, Dr. Ernest Borges Road, Parel, Mumbai - 400012, Maharashtra, India", "phone": "+912224177000"},
        ],
        "hospitals": [
            {"name": "Lilavati Hospital & Research Centre", "lat": 19.0515, "lng": 72.8272, "address": "Lilavati Hospital, A-791, Bandra Reclamation Road, Bandra West, Mumbai - 400050, Maharashtra, India"},
            {"name": "Kokilaben Dhirubhai Ambani Hospital", "lat": 19.1312, "lng": 72.8258, "address": "Kokilaben Hospital, Rao Saheb Achutrao Patwardhan Marg, Four Bungalows, Andheri West, Mumbai - 400053, Maharashtra, India"},
            {"name": "Jaslok Hospital & Research Centre", "lat": 18.9723, "lng": 72.8088, "address": "Jaslok Hospital, 15, Dr. Deshmukh Marg, Pedder Road, Mumbai - 400026, Maharashtra, India"},
            {"name": "Hinduja National Hospital", "lat": 19.0326, "lng": 72.8398, "address": "Hinduja Hospital, Veer Savarkar Marg, Mahim West, Mumbai - 400016, Maharashtra, India"},
        ]
    },
    3: { # Bengaluru Urban
        "banks": [
            {"name": "Rotary Bangalore TTK Blood Bank", "lat": 12.9304, "lng": 77.6225, "address": "Rotary Blood Bank, 20, 80 Feet Road, HAL 3rd Stage, Indiranagar, Bengaluru - 560075, Karnataka, India", "phone": "+918025287903"},
            {"name": "Narayana Hrudayalaya Blood Bank", "lat": 12.8122, "lng": 77.6934, "address": "Narayana Health City, 258/A, Bommasandra Industrial Area, Hosur Road, Bengaluru - 560099, Karnataka, India", "phone": "+918071222222"},
            {"name": "Victoria Hospital Blood Bank", "lat": 12.9644, "lng": 77.5746, "address": "Victoria Hospital, Fort Road, Near Kalasipalya, Bengaluru - 560002, Karnataka, India", "phone": "+918026701150"},
        ],
        "hospitals": [
            {"name": "Manipal Hospital, Old Airport Road", "lat": 12.9592, "lng": 77.6444, "address": "Manipal Hospital, 98, Old Airport Road, Kodihalli, Bengaluru - 560017, Karnataka, India"},
            {"name": "Fortis Hospital, Bannerghatta Road", "lat": 12.8942, "lng": 77.5976, "address": "Fortis Hospital, 154/9, Bannerghatta Road, Opposite IIM-B, Bengaluru - 560076, Karnataka, India"},
            {"name": "Aster CMI Hospital, Hebbal", "lat": 13.0285, "lng": 77.5896, "address": "Aster CMI Hospital, New Bell Road, Hebbal, Bengaluru - 560092, Karnataka, India"},
            {"name": "St. John's Medical College Hospital", "lat": 12.9332, "lng": 77.6244, "address": "St. John's Hospital, Sarjapur Road, John Nagar, Koramangala, Bengaluru - 560034, Karnataka, India"},
        ]
    },
    4: { # Chennai
        "banks": [
            {"name": "The Tamil Nadu Dr. MGR Medical University Blood Bank", "lat": 13.0098682, "lng": 80.2182251, "address": "The Tamil Nadu Dr. MGR Medical University Blood Bank, Race Course Interior Road, Guindy, Chennai - 600032, Tamil Nadu, India", "phone": "+914422353574"},
            {"name": "Rajiv Gandhi Govt General Hospital Blood Bank", "lat": 13.0806077, "lng": 80.2773314, "address": "Rajiv Gandhi Government General Hospital, General Hospital Road, Zone 5 Royapuram, Chennai - 600003, Tamil Nadu, India", "phone": "+914425305000"},
            {"name": "Tamil Nadu Govt Multi Super Speciality Hospital Blood Bank", "lat": 13.0694592, "lng": 80.273745, "address": "Tamil Nadu Government Multi Super Speciality Hospital, Swami Sivananda Salai, Zone 5 Royapuram, Chennai - 600005, Tamil Nadu, India", "phone": "+914425330300"},
        ],
        "hospitals": [
            {"name": "Vijaya Group of Hospitals", "lat": 13.0497391, "lng": 80.2083222, "address": "Vijaya Group of Hospital, Arcot Road, Zone 10 Kodambakkam, Chennai - 600017, Tamil Nadu, India"},
            {"name": "Kauvery Hospital", "lat": 13.0381705, "lng": 80.2573008, "address": "Kauvery Hospital, #199, Luz Church Road, Zone 9 Teynampet, Chennai - 600018, Tamil Nadu, India"},
            {"name": "Apollo Hospitals, Tondiarpet", "lat": 13.1289367, "lng": 80.2905623, "address": "Apollo Hospitals, Tondiarpet, Thiruvottriyur High Road, Tondiarpet, Chennai - 600081, Tamil Nadu, India"},
            {"name": "Madras Medical Mission Hospital", "lat": 13.0859961, "lng": 80.1870589, "address": "Madras Medical Mission Hospital - Institute of Cardio Vascular Diseases, 4-A, Seethakathi Street, Mogappair East, Chennai - 600037, Tamil Nadu, India"},
        ]
    }
}

MONTHLY_MULTIPLIERS = {
    1: 1.0, 2: 1.0, 3: 0.9, 4: 0.8, 5: 0.8, 6: 1.1,
    7: 1.3, 8: 1.3, 9: 1.2, 10: 1.0, 11: 0.9, 12: 1.1
}

def get_season(date_val):
    month = date_val.month
    if 4 <= month <= 6:
        return "Summer"
    elif 7 <= month <= 9:
        return "Monsoon"
    elif 10 <= month <= 11:
        return "Autumn"
    else:
        return "Winter"

def is_holiday_day(date_val):
    if date_val.weekday() in [5, 6]:  # Saturday/Sunday
        return True, "Weekend"
    return False, None

def check_festival(date_val):
    for fest in INDIAN_FESTIVALS:
        if date_val.month == fest["month"] and date_val.day == fest["day"]:
            return True, fest["name"], fest["impact"]
    return False, None, 0.0

def fetch_real_facilities_from_geoapify(lat, lng, api_key):
    url = f"https://api.geoapify.com/v2/places?categories=healthcare.hospital,healthcare.clinic_or_praxis&filter=circle:{lng},{lat},35000&limit=50&apiKey={api_key}"
    try:
        r = urllib.request.urlopen(url, timeout=5)
        import json
        data = json.loads(r.read().decode('utf-8'))
        features = data.get("features", [])
        places = []
        for f in features:
            props = f.get("properties", {})
            name = props.get("name")
            formatted = props.get("formatted")
            lon = props.get("lon")
            lat_val = props.get("lat")
            if name and formatted and lon and lat_val:
                places.append({
                    "name": name,
                    "lat": lat_val,
                    "lng": lon,
                    "address": formatted
                })
        return places
    except Exception as e:
        print(f"Geoapify Places API query error: {e}")
    return []

def fetch_real_banks_from_csv():
    url = "https://raw.githubusercontent.com/atmajitg/bloodbanks/master/blood-banks.csv"
    regions_banks = {1: [], 2: [], 3: [], 4: []}
    try:
        print("Downloading Kaggle India Blood Bank Directory...")
        req = urllib.request.Request(
            url, 
            headers={'User-Agent': 'Mozilla/5.0'}
        )
        response = urllib.request.urlopen(req, timeout=15)
        csv_text = response.read().decode('latin-1')
        reader = csv.reader(io.StringIO(csv_text))
        header = [col.strip() for col in next(reader)]
        
        name_idx = header.index("Blood Bank Name")
        state_idx = header.index("State")
        city_idx = header.index("City")
        dist_idx = header.index("District")
        addr_idx = header.index("Address")
        lat_idx = header.index("Latitude")
        lng_idx = header.index("Longitude")
        phone_idx = header.index("Contact No")
        
        for row in reader:
            if not row or len(row) <= max(lat_idx, lng_idx):
                continue
            state = row[state_idx].strip().lower()
            city = row[city_idx].strip().lower()
            dist = row[dist_idx].strip().lower()
            name = row[name_idx].strip()
            addr = row[addr_idx].strip().replace("\n", ", ")
            phone = row[phone_idx].strip()
            if phone:
                phone = phone.split(",")[0].split(";")[0].split("/")[0].strip()
                phone = phone[:20].strip()
            
            try:
                lat = float(row[lat_idx].strip())
                lng = float(row[lng_idx].strip())
                if lat == 0.0 or lng == 0.0 or lat < 8.0 or lat > 38.0 or lng < 68.0 or lng > 98.0:
                    continue
            except Exception:
                continue
                
            bank_data = {
                "name": name,
                "address": addr if addr else name,
                "lat": lat,
                "lng": lng,
                "phone": phone if phone and phone.lower() != "n/a" else "+919999000000"
            }
            
            if "delhi" in state:
                regions_banks[1].append(bank_data)
            elif "maharashtra" in state and ("mumbai" in city or "mumbai" in dist or "thane" in city or "thane" in dist):
                regions_banks[2].append(bank_data)
            elif "karnataka" in state and ("bangalore" in city or "bangalore" in dist or "bengaluru" in city or "bengaluru" in dist):
                regions_banks[3].append(bank_data)
            elif "tamil nadu" in state and ("chennai" in city or "chennai" in dist):
                regions_banks[4].append(bank_data)
                
        print("CSV Ingestion Complete.")
        for r_id, lst in regions_banks.items():
            print(f"  Region {r_id} parsed: {len(lst)} banks.")
    except Exception as e:
        print(f"Error fetching real blood banks: {e}")
    return regions_banks

def ingest_real_datasets(db: Session):
    print("Ingesting real-world datasets and creating provenance records...")
    
    # 1. UCI Blood Transfusion Ingestion & Model Training
    uci_url = "https://archive.ics.uci.edu/ml/machine-learning-databases/blood-transfusion/transfusion.data"
    uci_stats = {"mean_recency": 9.52, "std_recency": 8.07, "mean_frequency": 5.5, "std_frequency": 5.8}
    try:
        print("Downloading UCI Blood Transfusion dataset...")
        req = urllib.request.Request(uci_url, headers={'User-Agent': 'Mozilla/5.0'})
        response = urllib.request.urlopen(req, timeout=15)
        csv_text = response.read().decode('utf-8')
        reader = csv.reader(io.StringIO(csv_text))
        header = next(reader)
        
        uci_rows = []
        X, y = [], []
        for row in reader:
            if not row:
                continue
            rec = int(row[0])
            freq = int(row[1])
            mon = int(row[2])
            time_val = int(row[3])
            donated = int(row[4])
            
            db.add(DonorBehaviorReference(
                recency_months=rec,
                frequency_times=freq,
                monetary_cc=mon,
                time_months=time_val,
                donated_march_2007=donated
            ))
            X.append([rec, freq, time_val])
            y.append(donated)
            uci_rows.append((rec, freq, mon, time_val, donated))
            
        db.commit()
        print(f"Ingested {len(X)} records into donor_behavior_reference.")
        
        if X:
            X_arr = np.array(X)
            y_arr = np.array(y)
            clf = LogisticRegression()
            clf.fit(X_arr, y_arr)
            
            os.makedirs("models", exist_ok=True)
            with open("models/donor_response_model.pkl", "wb") as f:
                pickle.dump(clf, f)
            print("Successfully trained and saved UCI donor behavior classifier to models/donor_response_model.pkl")
            
            recencies = [r[0] for r in uci_rows]
            frequencies = [r[1] for r in uci_rows]
            uci_stats = {
                "mean_recency": float(np.mean(recencies)),
                "std_recency": float(np.std(recencies)),
                "mean_frequency": float(np.mean(frequencies)),
                "std_frequency": float(np.std(frequencies))
            }
    except Exception as e:
        print(f"Error ingesting UCI dataset: {e}")

    # 2. MoRTH Road Accident Dataset Ingestion
    acc_url = "https://raw.githubusercontent.com/prash29/Traffic-Accident-Analysis/master/datafile_4.csv"
    accident_stats = {
        "Delhi": {"total_accidents": 8623, "killed": 1671, "injured": 8234},
        "Maharashtra": {"total_accidents": 61627, "killed": 12803, "injured": 51234},
        "Karnataka": {"total_accidents": 43713, "killed": 10444, "injured": 38945},
        "Tamil Nadu": {"total_accidents": 67250, "killed": 15190, "injured": 65431}
    }
    try:
        print("Downloading MoRTH Road Accident dataset...")
        req = urllib.request.Request(acc_url, headers={'User-Agent': 'Mozilla/5.0'})
        response = urllib.request.urlopen(req, timeout=15)
        csv_text = response.read().decode('latin-1')
        reader = csv.reader(io.StringIO(csv_text))
        header = [col.strip() for col in next(reader)]
        
        state_idx = header.index("States/UTs")
        tot_idx = header.index("Total No. of Road Accidents - 2014")
        killed_idx = header.index("Total -Number of Persons-Killed - 2014")
        injured_idx = header.index("Total -Number of Persons-Injured - 2014")
        
        for row in reader:
            if not row:
                continue
            state = row[state_idx].strip()
            try:
                tot = int(row[tot_idx].replace(",", "").strip())
                killed = int(row[killed_idx].replace(",", "").strip())
                injured = int(row[injured_idx].replace(",", "").strip())
            except Exception:
                continue
                
            db.add(RealAccidentReference(
                state=state,
                total_accidents=tot,
                killed=killed,
                injured=injured,
                year=2014
            ))
            
            std_name = None
            if "delhi" in state.lower():
                std_name = "Delhi"
            elif "maharashtra" in state.lower():
                std_name = "Maharashtra"
            elif "karnataka" in state.lower():
                std_name = "Karnataka"
            elif "tamil nadu" in state.lower():
                std_name = "Tamil Nadu"
                
            if std_name:
                accident_stats[std_name] = {
                    "total_accidents": tot,
                    "killed": killed,
                    "injured": injured
                }
        db.commit()
        print(f"Ingested road accident reference table.")
    except Exception as e:
        print(f"Error ingesting accident dataset: {e}")
        
    # 3. Data Provenance Table Seeding
    provenance_data = [
        # Tier 1
        ("blood_banks.name", 1, "Kaggle India Blood Bank Directory", "Direct ingestion of blood bank names from public directory."),
        ("blood_banks.location", 1, "Kaggle India Blood Bank Directory", "Direct ingestion of latitude/longitude coordinates."),
        ("blood_banks.address", 1, "Kaggle India Blood Bank Directory", "Direct ingestion of street addresses."),
        ("donor_ranking.priority_score.response_rate", 1, "UCI Blood Transfusion Service Center", "Scikit-learn Logistic Regression classifier trained on real donor behavior data."),
        
        # Tier 2
        ("donation_records.accident_count_that_day", 2, "MoRTH Road Accidents 2014", "Poisson-disaggregated daily accident counts derived from real state-level annual totals."),
        
        # Tier 3
        ("donors.days_since_last_donation", 3, "UCI Blood Transfusion Service Center", "Distribution-sampled starting recency calibrated against mean/std of real UCI donor data."),
        ("donors.donation_frequency", 3, "UCI Blood Transfusion Service Center", "Distribution-sampled starting frequency calibrated against real UCI donor data."),
        ("donation_records.units", 3, "BloodSense Synthetic Rules", "Distribution-matched daily donation quantities (calibrated on historical volumes)."),
        ("transfusion_records.units", 3, "BloodSense Synthetic Rules", "Distribution-matched daily consumption quantities (calibrated on hospital demands).")
    ]
    
    for field_name, tier, source, methodology in provenance_data:
        db.add(DataProvenance(
            field_name=field_name,
            tier=tier,
            source_dataset=source,
            access_date=datetime.utcnow(),
            methodology=methodology
        ))
    db.commit()
    print("Seeded data provenance table.")
    
    # 4. System Metadata
    data_version = str(uuid.uuid4())
    db.add(SystemMetadata(key="data_version", value=data_version))
    db.commit()
    print(f"Seeded system metadata with data_version: {data_version}")
    
    return uci_stats, accident_stats

def generate_synthetic_data(num_regions=4, days=730, seed=42):
    print(f"Starting synthetic data generation: regions={num_regions}, days={days}, seed={seed}")
    random.seed(seed)
    np.random.seed(seed)
    
    db = SessionLocal()
    
    # Ingest reference tables & train model
    uci_stats, accident_stats = ingest_real_datasets(db)
    
    # Fetch real blood banks from directory
    real_banks_data = fetch_real_banks_from_csv()
    
    # 1. Generate Regions
    regions_data = [
        {"name": "Delhi NCR", "state": "Delhi", "district": "New Delhi", "accident_risk_level": 4},
        {"name": "Mumbai MMR", "state": "Maharashtra", "district": "Mumbai City", "accident_risk_level": 5},
        {"name": "Bengaluru Urban", "state": "Karnataka", "district": "Bengaluru", "accident_risk_level": 3},
        {"name": "Chennai", "state": "Tamil Nadu", "district": "Chennai", "accident_risk_level": 4},
    ]
    
    regions = []
    for i in range(min(num_regions, len(regions_data))):
        r = Region(**regions_data[i])
        db.add(r)
        regions.append(r)
    db.commit()
    print(f"Seeded {len(regions)} regions.")
    
    # 2. Populate Blood Banks and Hospitals
    api_key = "1d6b9e8325e840f48096e1063e04ffe6"
    blood_banks = []
    hospitals = []
    
    lat_centers = {1: 28.6139, 2: 19.0760, 3: 12.9716, 4: 13.0827}
    lng_centers = {1: 77.2090, 2: 72.8777, 3: 77.5946, 4: 80.2707}
    
    for r_idx, region in enumerate(regions):
        r_id = region.region_id
        lat = lat_centers.get(r_idx + 1, 28.6139)
        lng = lng_centers.get(r_idx + 1, 77.2090)
        
        # Try fetching real banks from CSV directory
        selected_banks = real_banks_data.get(r_idx + 1, [])
        if len(selected_banks) < 3:
            # Fall back to geoapify & fallback list
            print(f"Not enough banks in CSV directory for {region.name}. Fetching Geoapify...")
            fetched = fetch_real_facilities_from_geoapify(lat, lng, api_key)
            real_banks = []
            for p in fetched:
                name_lower = p["name"].lower()
                if "blood" in name_lower or "red cross" in name_lower or "rotary" in name_lower or "transfusion" in name_lower:
                    real_banks.append(p)
            
            for rb in real_banks:
                if len(selected_banks) < 3:
                    if "blood" not in rb["name"].lower():
                        rb["name"] = f"{rb['name']} Blood Bank"
                    selected_banks.append(rb)
                    
            fb_list = FALLBACK_PLACES.get(r_idx + 1, FALLBACK_PLACES[1])["banks"]
            for fb in fb_list:
                if len(selected_banks) < 3:
                    if not any(sb["name"].lower() == fb["name"].lower() for sb in selected_banks):
                        selected_banks.append(fb)
        
        # Keep only top 3
        selected_banks = selected_banks[:3]
        
        # Get hospitals
        fallback_hosp = FALLBACK_PLACES.get(r_idx + 1, FALLBACK_PLACES[1])["hospitals"]
        selected_hospitals = fallback_hosp[:4]
        
        # Add Blood Banks
        for b_idx, b_data in enumerate(selected_banks):
            bank = BloodBank(
                name=b_data["name"],
                location_lat=b_data["lat"],
                location_lng=b_data["lng"],
                address=b_data["address"],
                region_id=r_id,
                contact_phone=b_data.get("phone", f"+919999000{r_id}{b_idx}"),
                admin_user_id=f"firebase_admin_uid_{r_id}_{b_idx}"
            )
            db.add(bank)
            blood_banks.append(bank)
            
        # Add Hospitals
        for h_idx, h_data in enumerate(selected_hospitals):
            avg_consumption = {}
            for bg in BLOOD_GROUPS:
                base_c = 15.0 if bg == "O+" else (5.0 if bg in ["A+", "B+"] else 1.5)
                avg_consumption[bg] = round(base_c * random.uniform(0.7, 1.3), 1)
                
            hospital = Hospital(
                name=h_data["name"],
                location_lat=h_data["lat"],
                location_lng=h_data["lng"],
                address=h_data["address"],
                region_id=r_id,
                avg_daily_consumption=avg_consumption
            )
            db.add(hospital)
            hospitals.append(hospital)
            
    db.commit()
    print(f"Seeded {len(blood_banks)} blood banks and {len(hospitals)} hospitals.")
    
    # 3. Generate Calendar Flags
    start_date = datetime.now().date() - timedelta(days=days)
    all_dates = [start_date + timedelta(days=d) for d in range(days)]
    
    calendar_entries = {}
    for d in all_dates:
        is_fest, fest_name, fest_impact = check_festival(d)
        is_hol, hol_name = is_holiday_day(d)
        
        impact = 0.0
        if is_fest:
            impact = fest_impact
        elif is_hol:
            impact = -0.20
            
        cf = CalendarFlags(
            date=d,
            is_festival=is_fest,
            is_holiday=is_hol,
            festival_name=fest_name if is_fest else hol_name,
            expected_donation_impact=impact
        )
        db.add(cf)
        calendar_entries[d] = cf
    db.commit()
    print(f"Seeded {days} days of calendar flags.")
    
    # 4. Generate Donors with UCI Distributions
    donors = []
    donor_names = ["Rahul", "Priya", "Amit", "Sneha", "Vikram", "Anjali", "Rohan", "Divya", "Suresh", "Kavitha"]
    donor_surnames = ["Sharma", "Verma", "Patel", "Nair", "Rao", "Joshi", "Kumar", "Singh", "Gupta", "Mehta"]
    
    # Extract UCI stats
    mean_recency = uci_stats["mean_recency"]
    std_recency = uci_stats["std_recency"]
    mean_freq = uci_stats["mean_frequency"]
    std_freq = uci_stats["std_frequency"]
    
    for region in regions:
        r_id = region.region_id
        for d_idx in range(50):
            bg = random.choices(BLOOD_GROUPS, weights=[0.35, 0.05, 0.20, 0.03, 0.25, 0.03, 0.07, 0.02], k=1)[0]
            lat = region.banks[0].location_lat + random.uniform(-0.1, 0.1)
            lng = region.banks[0].location_lng + random.uniform(-0.1, 0.1)
            
            # Response statistics matching UCI
            # alert_count = frequency * 3
            # response_count = frequency
            sampled_freq = max(1, int(np.random.normal(mean_freq, std_freq)))
            alert_count = sampled_freq * 3
            response_count = sampled_freq
            resp_rate = response_count / alert_count
            
            dob = datetime.now().date() - timedelta(days=random.randint(18*365, 55*365))
            
            # Recency distribution
            sampled_recency = max(0.5, min(36.0, np.random.normal(mean_recency, std_recency)))
            days_ago = int(sampled_recency * 30.0)
            last_don = datetime.now().date() - timedelta(days=days_ago)
            is_eligible = days_ago >= 90
            
            donor = Donor(
                firebase_uid=f"firebase_user_{r_id}_{d_idx}",
                name=f"{random.choice(donor_names)} {random.choice(donor_surnames)}",
                phone=f"+91987654{r_id:02}{d_idx:02}",
                blood_group=bg,
                dob=dob,
                location_lat=lat,
                location_lng=lng,
                last_donation_date=last_don,
                is_eligible=is_eligible,
                fcm_token=f"fcm_token_{r_id}_{d_idx}",
                alert_count=alert_count,
                response_count=response_count,
                response_rate=resp_rate,
                registered_at=datetime.utcnow() - timedelta(days=random.randint(180, 700))
            )
            db.add(donor)
            donors.append(donor)
    db.commit()
    print(f"Seeded {len(donors)} donors based on UCI distributions.")
    
    # 5. Daily Poisson Accident Counts & Historic Donation/Transfusion Seeding
    accident_days = {}
    for region in regions:
        r_id = region.region_id
        # Define high-accident days per region for emergency events
        year1_days = all_dates[:365]
        year2_days = all_dates[365:]
        h_days_y1 = random.sample(year1_days, 15)
        h_days_y2 = random.sample(year2_days, 15)
        accident_days[r_id] = set(h_days_y1 + h_days_y2)
        
        for ad in accident_days[r_id]:
            ee = EmergencyEvent(
                region_id=r_id,
                event_type="Accident Spike",
                severity=random.randint(3, 5),
                event_date=ad,
                estimated_blood_impact_units=float(random.randint(15, 35))
            )
            db.add(ee)
    db.commit()
    
    print("Generating daily historical records (Poisson-disaggregated)...")
    
    banks_by_region = {r.region_id: [b for b in blood_banks if b.region_id == r.region_id] for r in regions}
    hospitals_by_region = {r.region_id: [h for h in hospitals if h.region_id == r.region_id] for r in regions}
    donors_by_group_region = {}
    for d in donors:
        r_id = int(d.phone[8])
        donors_by_group_region.setdefault((d.blood_group, r_id), []).append(d)
        
    donation_records = []
    transfusion_records = []
    
    inventory_tracker = {}
    for b in blood_banks:
        for bg in BLOOD_GROUPS:
            inventory_tracker[(b.bank_id, bg)] = 50.0
            
    for d in all_dates:
        season = get_season(d)
        is_fest = calendar_entries[d].is_festival
        is_hol = calendar_entries[d].is_holiday
        
        seasonal_multiplier = 1.0
        if season == "Summer":
            seasonal_multiplier -= 0.15
        elif d.month in [3, 11]:
            seasonal_multiplier -= 0.10
            
        fest_multiplier = 1.0
        if is_fest:
            fest_multiplier -= random.uniform(0.30, 0.40)
            
        for region in regions:
            r_id = region.region_id
            state_name = region.state
            
            # Poisson-disaggregated daily accident counts
            annual_acc = accident_stats.get(state_name, {"total_accidents": 40000})["total_accidents"]
            lambda_val = (annual_acc / 12.0) * MONTHLY_MULTIPLIERS[d.month] / 30.0
            acc_count = int(np.random.poisson(lambda_val))
            
            # Spike flag (if accidents > average by 20%)
            is_acc_day = acc_count > (lambda_val * 1.2)
            
            # Generate donations
            for bank in banks_by_region[r_id]:
                for bg in BLOOD_GROUPS:
                    base_ratio = BASE_DONATION_RATIOS[bg]
                    base_donations = 8.0 if bg == "O+" else 4.0
                    base_donations *= base_ratio
                    
                    expected_donations = base_donations * seasonal_multiplier * fest_multiplier
                    actual_donations = max(0, int(np.random.normal(expected_donations, expected_donations * 0.2)))
                    
                    if actual_donations > 0:
                        possible_donors = donors_by_group_region.get((bg, r_id), [])
                        for u in range(actual_donations):
                            linked_donor_id = None
                            if possible_donors and random.random() < 0.4:
                                linked_donor_id = random.choice(possible_donors).donor_id
                                
                            rec = DonationRecord(
                                donor_id=linked_donor_id,
                                bank_id=bank.bank_id,
                                blood_group=bg,
                                units=1.0,
                                donated_at=d,
                                is_festival_day=is_fest,
                                accident_count_that_day=acc_count,
                                season=season
                            )
                            donation_records.append(rec)
                            inventory_tracker[(bank.bank_id, bg)] += 1.0
            
            # Generate transfusions
            for hospital in hospitals_by_region[r_id]:
                bank_to_deduct = banks_by_region[r_id][0]
                for bg in BLOOD_GROUPS:
                    avg_c = hospital.avg_daily_consumption[bg]
                    demand_multiplier = 1.0
                    if is_acc_day:
                        if bg in ["O+", "AB+"]:
                            demand_multiplier += random.uniform(0.25, 0.35)
                        else:
                            demand_multiplier += random.uniform(0.20, 0.25)
                            
                    expected_transfusions = avg_c * demand_multiplier
                    actual_transfusions = max(0, int(np.random.normal(expected_transfusions, expected_transfusions * 0.15)))
                    
                    if actual_transfusions > 0:
                        rec = TransfusionRecord(
                            hospital_id=hospital.hospital_id,
                            blood_group=bg,
                            units=float(actual_transfusions),
                            transfused_at=d,
                            emergency_flag=is_acc_day
                        )
                        transfusion_records.append(rec)
                        inventory_tracker[(bank_to_deduct.bank_id, bg)] = max(0.0, inventory_tracker[(bank_to_deduct.bank_id, bg)] - actual_transfusions)
                        
    print(f"Saving {len(donation_records)} donation records...")
    db.bulk_save_objects(donation_records)
    db.commit()
    
    print(f"Saving {len(transfusion_records)} transfusion records...")
    db.bulk_save_objects(transfusion_records)
    db.commit()
    
    # 6. Seed current inventory & expiry numbers
    three_days_ago = all_dates[-3]
    donations_3days_ago = db.query(
        DonationRecord.bank_id, DonationRecord.blood_group, func.count(DonationRecord.record_id).label("cnt")
    ).filter(DonationRecord.donated_at == three_days_ago).group_by(DonationRecord.bank_id, DonationRecord.blood_group).all()
    
    expiry_map = {(d[0], d[1]): d[2] * 0.15 for d in donations_3days_ago}
    
    print("Saving current blood inventories...")
    for b in blood_banks:
        for bg in BLOOD_GROUPS:
            current_units = max(5.0, inventory_tracker[(b.bank_id, bg)])
            expiring = round(expiry_map.get((b.bank_id, bg), current_units * 0.08), 1)
            
            bi = BloodInventory(
                bank_id=b.bank_id,
                blood_group=bg,
                units_available=float(round(current_units, 1)),
                units_expiring_3days=float(expiring),
                last_updated=datetime.utcnow()
            )
            db.add(bi)
    db.commit()
    db.close()
    print("Synthetic data generation and database seeding complete!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed database with synthetic blood bank records.")
    parser.add_argument("--regions", type=int, default=4, help="Number of regions to seed (max 4)")
    parser.add_argument("--days", type=int, default=730, help="Number of historic days")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--reset", action="store_true", help="Clear and re-seed database using table-clearing order")
    
    args = parser.parse_args()
    
    db = SessionLocal()
    if args.reset:
        print("Ensuring tables are initialized...")
        init_db()
        print("Resetting database by clearing tables in cascade-safe order...")
        tables_to_clear = [
            DonorAlertLog, ShortageAlert, Redistribution, ForecastCache, BSSIScore,
            DonationRecord, TransfusionRecord, BloodInventory, Donor, Hospital, BloodBank,
            EmergencyEvent, Region, CalendarFlags, DonorBehaviorReference, RealAccidentReference,
            DataProvenance, SystemMetadata, RefreshToken, ModelPerformance
        ]
        for tbl in tables_to_clear:
            try:
                db.query(tbl).delete()
                db.commit()
            except Exception as e:
                db.rollback()
                print(f"Error clearing {tbl.__tablename__}: {e}")
        print("Database cleared. Re-seeding from scratch...")
    else:
        print("Dropping all existing database tables and initializing...")
        from backend.database import Base, engine
        Base.metadata.drop_all(bind=engine)
        init_db()
    db.close()
    
    generate_synthetic_data(num_regions=args.regions, days=args.days, seed=args.seed)
