import os
import pickle
import random
from datetime import datetime, date, timedelta
import numpy as np
import pandas as pd
from sqlalchemy import func
from sqlalchemy.orm import Session
from backend.database import (
    SessionLocal, Region, BloodBank, Hospital, DonationRecord, TransfusionRecord,
    BloodInventory, BSSIScore, ForecastCache, CalendarFlags, Donor
)

# Suppress Prophet logs to keep output clean
import logging
logger = logging.getLogger('prophet')
logger.setLevel(logging.ERROR)

from prophet import Prophet
from statsmodels.tsa.statespace.sarimax import SARIMAX

# Cache BSSI scores in a local memory dict to simulate Redis if Redis is unavailable
REDIS_MOCK_CACHE = {}

def get_redis_client():
    """Attempts to connect to Redis. Returns None if connection fails."""
    try:
        import redis
        r = redis.Redis(host=os.getenv("REDIS_HOST", "localhost"), port=int(os.getenv("REDIS_PORT", 6379)), db=0, socket_timeout=2)
        r.ping()
        return r
    except Exception:
        return None

redis_client = get_redis_client()

def cache_bssi(bank_id: int, blood_group: str, score: float):
    """Caches BSSI score in Redis (6-hour TTL) or local mock cache."""
    key = f"bssi:{bank_id}:{blood_group}"
    if redis_client:
        try:
            redis_client.setex(key, 21600, str(score))  # 6 hours = 21600 seconds
            return
        except Exception:
            pass
    REDIS_MOCK_CACHE[key] = (score, datetime.utcnow() + timedelta(hours=6))

def get_cached_bssi(bank_id: int, blood_group: str):
    """Retrieves cached BSSI score."""
    key = f"bssi:{bank_id}:{blood_group}"
    if redis_client:
        try:
            val = redis_client.get(key)
            if val:
                return float(val)
        except Exception:
            pass
    
    if key in REDIS_MOCK_CACHE:
        val, expiry = REDIS_MOCK_CACHE[key]
        if datetime.utcnow() < expiry:
            return val
        else:
            del REDIS_MOCK_CACHE[key]
    return None

# ML MODEL 1: Prophet Forecasting with SARIMA Fallback
def train_and_cache_forecasts(db: Session, force_retrain=False):
    """
    Trains Prophet models for all 24 combinations (3 regions x 8 blood groups).
    Evaluates forecasting using MAPE on an 80/20 train/test split.
    If MAPE > 15%, auto-switches to SARIMA(1,1,1)(1,1,1,7).
    Saves 7-day predictions in forecast_cache.
    """
    regions = db.query(Region).all()
    blood_groups = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
    
    # Check if we have recent forecasts (e.g. generated within last 24h)
    if not force_retrain:
        recent_forecast = db.query(ForecastCache).first()
        if recent_forecast and (datetime.utcnow().date() - recent_forecast.generated_at.date()).days < 1:
            print("Forecasts are up to date. Skipping retraining.")
            return {}

    # Get Calendar Flags
    calendar_df = pd.read_sql(db.query(CalendarFlags).statement, db.bind)
    calendar_df['date'] = pd.to_datetime(calendar_df['date'])

    accuracy_metrics = {}

    for region in regions:
        r_id = region.region_id
        
        # Load Transfusion Records for this region
        # Group by transfused_at and blood_group
        transfusions_query = db.query(
            TransfusionRecord.transfused_at.label("date"),
            TransfusionRecord.blood_group,
            func.sum(TransfusionRecord.units).label("units")
        ).join(Hospital).filter(Hospital.region_id == r_id).group_by(
            TransfusionRecord.transfused_at, TransfusionRecord.blood_group
        )
        transfusions_df = pd.read_sql(transfusions_query.statement, db.bind)
        
        # Load Donation Records for this region
        donations_query = db.query(
            DonationRecord.donated_at.label("date"),
            DonationRecord.blood_group,
            func.sum(DonationRecord.units).label("units_donated"),
            func.max(DonationRecord.accident_count_that_day).label("accident_count")
        ).filter(DonationRecord.bank_id.in_(
            [b.bank_id for b in region.banks]
        )).group_by(DonationRecord.donated_at, DonationRecord.blood_group)
        donations_df = pd.read_sql(donations_query.statement, db.bind)

        if transfusions_df.empty:
            print(f"No historical transfusion data for region {region.name}. Skipping forecasting.")
            continue

        transfusions_df['date'] = pd.to_datetime(transfusions_df['date'])
        if not donations_df.empty:
            donations_df['date'] = pd.to_datetime(donations_df['date'])
        
        for bg in blood_groups:
            # Filter for specific blood group
            bg_transfusions = transfusions_df[transfusions_df['blood_group'] == bg].copy()
            bg_donations = donations_df[donations_df['blood_group'] == bg].copy() if not donations_df.empty else pd.DataFrame()
            
            # Construct standard time-series index
            all_dates_range = pd.date_range(
                start=calendar_df['date'].min(),
                end=calendar_df['date'].max(),
                freq='D'
            )
            df = pd.DataFrame({'date': all_dates_range})
            
            # Merge inputs
            df = df.merge(bg_transfusions[['date', 'units']], on='date', how='left').rename(columns={'units': 'y'})
            df['y'] = df['y'].fillna(0.0)
            
            if not bg_donations.empty:
                df = df.merge(bg_donations[['date', 'units_donated', 'accident_count']], on='date', how='left')
            else:
                df['units_donated'] = 0.0
                df['accident_count'] = 1
                
            df['units_donated'] = df['units_donated'].fillna(0.0)
            df['accident_count'] = df['accident_count'].fillna(1.0)
            
            df = df.merge(calendar_df[['date', 'is_festival', 'is_holiday']], on='date', how='left')
            df['is_festival'] = df['is_festival'].astype(int).fillna(0)
            df['is_holiday'] = df['is_holiday'].astype(int).fillna(0)
            
            # Train / Test split (80% / 20%)
            split_idx = int(len(df) * 0.8)
            train_df = df.iloc[:split_idx].copy()
            test_df = df.iloc[split_idx:].copy()

            # 1. Train Prophet Model
            prophet_train = pd.DataFrame({
                'ds': train_df['date'],
                'y': train_df['y'],
                'units_donated': train_df['units_donated'],
                'accident_count': train_df['accident_count'],
                'is_festival': train_df['is_festival'],
                'is_holiday': train_df['is_holiday']
            })
            
            m = Prophet(yearly_seasonality=True, weekly_seasonality=True, daily_seasonality=False)
            m.add_regressor('units_donated')
            m.add_regressor('accident_count')
            m.add_regressor('is_festival')
            m.add_regressor('is_holiday')
            m.fit(prophet_train)
            
            # Predict on test set to calculate MAPE
            prophet_test = pd.DataFrame({
                'ds': test_df['date'],
                'units_donated': test_df['units_donated'],
                'accident_count': test_df['accident_count'],
                'is_festival': test_df['is_festival'],
                'is_holiday': test_df['is_holiday']
            })
            forecast = m.predict(prophet_test)
            yhat = forecast['yhat'].values
            y_true = test_df['y'].values
            
            # Compute MAPE (avoid dividing by zero by adding 1.0)
            mape = np.mean(np.abs((y_true - yhat) / (y_true + 1.0))) * 100
            rmse = np.sqrt(np.mean((y_true - yhat) ** 2))
            
            use_fallback = mape > 15.0
            
            if use_fallback:
                print(f"Prophet MAPE ({mape:.2f}%) exceeds 15% for Region {region.name} - Group {bg}. Switching to SARIMA.")
                try:
                    # Fit SARIMAX(1,1,1)(1,1,1,7)
                    sarima_model = SARIMAX(
                        train_df['y'].values,
                        exog=train_df[['units_donated', 'accident_count', 'is_festival', 'is_holiday']].values,
                        order=(1,1,1),
                        seasonal_order=(1,1,1,7)
                    ).fit(disp=False)
                    
                    # Predict on test set
                    sarima_forecast = sarima_model.forecast(
                        steps=len(test_df),
                        exog=test_df[['units_donated', 'accident_count', 'is_festival', 'is_holiday']].values
                    )
                    mape = np.mean(np.abs((y_true - sarima_forecast) / (y_true + 1.0))) * 100
                    rmse = np.sqrt(np.mean((y_true - sarima_forecast) ** 2))
                    print(f"SARIMA metrics achieved: MAPE = {mape:.2f}%, RMSE = {rmse:.2f}")
                except Exception as sarima_err:
                    print(f"SARIMA fitting failed, reverting to Prophet standard. Error: {sarima_err}")
                    use_fallback = False
            
            accuracy_metrics[f"{r_id}:{bg}"] = {"mape": mape, "rmse": rmse, "model": "SARIMA" if use_fallback else "Prophet"}
            
            # Predict Next 7 Days
            future_dates = pd.date_range(start=df['date'].max() + timedelta(days=1), periods=7, freq='D')
            
            # Regressors for future (mocked from average history of latest days)
            future_donations = [df['units_donated'].tail(7).mean()] * 7
            future_accidents = [df['accident_count'].tail(7).mean()] * 7
            
            future_festivals = []
            future_holidays = []
            for fd in future_dates:
                # check holiday/festival flags
                _, _, f_impact = check_festival_mock(fd)
                is_hol = fd.weekday() in [5, 6]
                future_festivals.append(1 if f_impact < 0 else 0)
                future_holidays.append(1 if is_hol else 0)
            
            if use_fallback:
                # Predict via SARIMA
                # Fit on full dataset
                sarima_full = SARIMAX(
                    df['y'].values,
                    exog=df[['units_donated', 'accident_count', 'is_festival', 'is_holiday']].values,
                    order=(1,1,1),
                    seasonal_order=(1,1,1,7)
                ).fit(disp=False)
                
                exog_future = np.column_stack((future_donations, future_accidents, future_festivals, future_holidays))
                future_forecast = sarima_full.forecast(steps=7, exog=exog_future)
                
                # SARIMA standard errors as bounds
                yhat_vals = np.maximum(0.0, future_forecast)
                # Mock lower/upper using standard deviation
                yhat_lower_vals = np.maximum(0.0, yhat_vals - 1.96 * rmse)
                yhat_upper_vals = yhat_vals + 1.96 * rmse
            else:
                # Predict via Prophet
                future_prophet_df = pd.DataFrame({
                    'ds': future_dates,
                    'units_donated': future_donations,
                    'accident_count': future_accidents,
                    'is_festival': future_festivals,
                    'is_holiday': future_holidays
                })
                future_forecast = m.predict(future_prophet_df)
                yhat_vals = np.maximum(0.0, future_forecast['yhat'].values)
                yhat_lower_vals = np.maximum(0.0, future_forecast['yhat_lower'].values)
                yhat_upper_vals = future_forecast['yhat_upper'].values

            # Cache in Database (Clear old forecasts for this combination first)
            for bank in region.banks:
                db.query(ForecastCache).filter(
                    ForecastCache.bank_id == bank.bank_id,
                    ForecastCache.blood_group == bg
                ).delete()
                
                for step in range(7):
                    fc = ForecastCache(
                        bank_id=bank.bank_id,
                        blood_group=bg,
                        forecast_date=future_dates[step].date(),
                        yhat=float(round(yhat_vals[step], 1)),
                        yhat_lower=float(round(yhat_lower_vals[step], 1)),
                        yhat_upper=float(round(yhat_upper_vals[step], 1)),
                        generated_at=datetime.utcnow()
                    )
                    db.add(fc)
                    
        db.commit()
    print("Forecasting updates and caching complete.")
    return accuracy_metrics

def check_festival_mock(date_val):
    # Quick duplicate from generator to avoid cyclic import
    from backend.generate_data import INDIAN_FESTIVALS
    for fest in INDIAN_FESTIVALS:
        if date_val.month == fest["month"] and date_val.day == fest["day"]:
            return True, fest["name"], fest["impact"]
    return False, None, 0.0

# ML MODEL 2: BSSI Composite Scoring Engine
def compute_bssi(db: Session, bank_id: int, blood_group: str) -> dict:
    """
    Computes BSSI for a blood group at a specific blood bank.
    Runs every 6 hours or instantly on manual inventory changes.
    Stores the result in PostgreSQL and Redis.
    """
    bank = db.query(BloodBank).filter(BloodBank.bank_id == bank_id).first()
    if not bank:
        return {}
    
    # 1. Inventory Gap Score (Weight: 0.35)
    # predicted_7day_demand vs units_available
    forecasts = db.query(ForecastCache).filter(
        ForecastCache.bank_id == bank_id,
        ForecastCache.blood_group == blood_group
    ).all()
    
    predicted_7day_demand = sum([f.yhat for f in forecasts])
    if predicted_7day_demand <= 0:
        # Fallback to rolling consumption average if forecast isn't ready
        predicted_7day_demand = 14.0  # Safe floor
        
    inventory = db.query(BloodInventory).filter(
        BloodInventory.bank_id == bank_id,
        BloodInventory.blood_group == blood_group
    ).first()
    
    units_available = inventory.units_available if inventory else 0.0
    units_expiring_3days = inventory.units_expiring_3days if inventory else 0.0
    
    inventory_gap_score = (predicted_7day_demand - units_available) / predicted_7day_demand
    
    # 2. Donation Trend Score (Weight: 0.25)
    # 1 - normalized 7-day donation slope
    # Fetch daily donations for the last 7 days
    today = datetime.now().date()
    seven_days_ago = today - timedelta(days=7)
    donations = db.query(
        DonationRecord.donated_at,
        func.count(DonationRecord.record_id).label("units")
    ).filter(
        DonationRecord.bank_id == bank_id,
        DonationRecord.blood_group == blood_group,
        DonationRecord.donated_at >= seven_days_ago,
        DonationRecord.donated_at < today
    ).group_by(DonationRecord.donated_at).all()
    
    donations_map = {d[0]: d[1] for d in donations}
    donations_series = [donations_map.get(today - timedelta(days=i), 0.0) for i in range(7, 0, -1)]
    
    # Linear Regression slope
    x = np.arange(7)
    y = np.array(donations_series)
    avg_donations = y.mean()
    
    if len(y) > 1 and avg_donations > 0:
        slope = np.polyfit(x, y, 1)[0]
        # Normalize slope against average
        normalized_slope = slope / (avg_donations + 1.0)
    else:
        normalized_slope = 0.0
        
    donation_trend_score = 1.0 - normalized_slope

    # 3. Accident Signal Score (Weight: 0.20)
    # accident_severity_today / max_historical_severity
    accident_records = db.query(DonationRecord.accident_count_that_day).filter(
        DonationRecord.bank_id == bank_id
    ).order_by(DonationRecord.donated_at.desc()).limit(1).first()
    
    accident_severity_today = float(accident_records[0]) if accident_records else 1.0
    
    # Get max historic accidents
    max_historic = db.query(func.max(DonationRecord.accident_count_that_day)).filter(
        DonationRecord.bank_id == bank_id
    ).scalar()
    
    max_historical_severity = float(max_historic) if max_historic and max_historic > 0 else 15.0
    accident_signal_score = accident_severity_today / max_historical_severity

    # 4. Rare Group Flag (Weight: 0.10)
    # 1 if AB-, B-, or O- else 0
    rare_group_flag = 1.0 if blood_group in ["AB-", "B-", "O-"] else 0.0

    # 5. Expiry Pressure Score (Weight: 0.10)
    # units_expiring_3days / units_available
    expiry_pressure_score = units_expiring_3days / units_available if units_available > 0 else 1.0

    # Clip all inputs 0 to 1
    inventory_gap_score = float(np.clip(inventory_gap_score, 0.0, 1.0))
    donation_trend_score = float(np.clip(donation_trend_score, 0.0, 1.0))
    accident_signal_score = float(np.clip(accident_signal_score, 0.0, 1.0))
    expiry_pressure_score = float(np.clip(expiry_pressure_score, 0.0, 1.0))

    # BSSI Calculation
    bssi_val = (
        inventory_gap_score * 0.35
        + donation_trend_score * 0.25
        + accident_signal_score * 0.20
        + rare_group_flag * 0.10
        + expiry_pressure_score * 0.10
    ) * 100.0

    bssi_val = float(round(bssi_val, 1))

    # Save to PostgreSQL
    score_entry = BSSIScore(
        bank_id=bank_id,
        blood_group=blood_group,
        score=bssi_val,
        inventory_gap_score=inventory_gap_score,
        donation_trend_score=donation_trend_score,
        accident_signal_score=accident_signal_score,
        rare_group_flag=rare_group_flag,
        expiry_pressure_score=expiry_pressure_score,
        computed_at=datetime.utcnow()
    )
    db.add(score_entry)
    db.commit()

    # Cache in Redis
    cache_bssi(bank_id, blood_group, bssi_val)

    return {
        "bank_id": bank_id,
        "blood_group": blood_group,
        "score": bssi_val,
        "factors": {
            "inventory_gap": round(inventory_gap_score, 3),
            "donation_trend": round(donation_trend_score, 3),
            "accident_signal": round(accident_signal_score, 3),
            "rare_group": round(rare_group_flag, 3),
            "expiry_pressure": round(expiry_pressure_score, 3)
        }
    }

def update_all_bssi_scores(db: Session):
    """Computes and updates BSSI scores for all blood banks and blood groups."""
    banks = db.query(BloodBank).all()
    blood_groups = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
    
    results = []
    for bank in banks:
        for bg in blood_groups:
            res = compute_bssi(db, bank.bank_id, bg)
            results.append(res)
    return results

# Donor Prioritization Score (at alert trigger)
# priority_score = (1/distance_km * 0.5) + (response_rate * 0.3) + (days_since_last_donation/90 * 0.2)
def rank_eligible_donors(db: Session, bank_id: int, blood_group: str) -> list:
    """
    Ranks eligible donors for a blood group based on priority score.
    Uses the Haversine formula in plain SQL to compute distance directly in the database.
    Returns list of top 20 prioritized donors.
    """
    from sqlalchemy import text
    bank = db.query(BloodBank).filter(BloodBank.bank_id == bank_id).first()
    if not bank:
        return []
    
    today = datetime.now().date()
    
    # Proximity query using SQL Haversine formula
    sql_query = text("""
        SELECT donor_id, name, phone, blood_group, dob, location_lat, location_lng, 
               last_donation_date, response_rate, alert_count,
               (
                   6371 * acos(
                       LEAST(1.0, GREATEST(-1.0, 
                           cos(radians(:bank_lat)) * cos(radians(location_lat)) * 
                           cos(radians(location_lng) - radians(:bank_lng)) + 
                           sin(radians(:bank_lat)) * sin(radians(location_lat))
                       ))
                   )
               ) AS distance_km
        FROM donors
        WHERE blood_group = :blood_group AND is_eligible = true
        ORDER BY distance_km
    """)
    
    result = db.execute(sql_query, {
        "bank_lat": bank.location_lat,
        "bank_lng": bank.location_lng,
        "blood_group": blood_group
    }).fetchall()
    
    ranked_donors = []
    for row in result:
        distance_km = float(row.distance_km)
        dist_term = 1.0 / max(0.1, distance_km)
        
        last_don_date = row.last_donation_date or (today - timedelta(days=90))
        days_since = (today - last_don_date).days
        days_term = days_since / 90.0
        
        response_rate = float(row.response_rate) if row.response_rate is not None else 0.0
        
        priority_score = (dist_term * 0.5) + (response_rate * 0.3) + (days_term * 0.2)
        eta_minutes = int(distance_km * 2) + 5
        
        # Load the donor object to match the returned type expectation
        donor_obj = db.query(Donor).filter(Donor.donor_id == row.donor_id).first()
        
        ranked_donors.append({
            "donor": donor_obj,
            "priority_score": float(round(priority_score, 4)),
            "distance_km": float(round(distance_km, 2)),
            "eta_minutes": eta_minutes
        })
        
    ranked_donors.sort(key=lambda x: x["priority_score"], reverse=True)
    return ranked_donors[:20]
