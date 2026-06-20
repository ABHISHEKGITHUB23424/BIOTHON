from backend.database import SessionLocal, BloodBank, Region

db = SessionLocal()
try:
    regions = db.query(Region).all()
    for r in regions:
        print(f"Region: {r.name} (id={r.region_id})")
        banks = db.query(BloodBank).filter(BloodBank.region_id == r.region_id).all()
        for b in banks:
            print(f"  Bank: {b.name} | Lat: {b.location_lat} | Lng: {b.location_lng} | Addr: {b.address}")
finally:
    db.close()
