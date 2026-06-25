import asyncio
import random
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from datetime import datetime

app = FastAPI(title="RaktSetu Open Data & Simulation Server")

# Enable CORS for Flutter Web running on port 8080 or other ports
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Seed list of 12 banks mapped from local_db.dart
BANKS = [
    {"bank_id": 1, "name": "Delhi NCR Main Bank", "city": "Delhi NCR", "region_id": 1, "baseline": "healthy"},
    {"bank_id": 2, "name": "Noida Metro Bank", "city": "Delhi NCR", "region_id": 1, "baseline": "critical"},
    {"bank_id": 3, "name": "Gurgaon City Bank", "city": "Delhi NCR", "region_id": 1, "baseline": "warning"},
    {"bank_id": 4, "name": "Mumbai Main Bank", "city": "Mumbai", "region_id": 2, "baseline": "healthy"},
    {"bank_id": 5, "name": "Thane Regional Bank", "city": "Mumbai", "region_id": 2, "baseline": "warning"},
    {"bank_id": 6, "name": "Navi Mumbai Bank", "city": "Mumbai", "region_id": 2, "baseline": "healthy"},
    {"bank_id": 7, "name": "Bengaluru Urban Main", "city": "Bengaluru", "region_id": 3, "baseline": "healthy"},
    {"bank_id": 8, "name": "Koramangala Blood Depot", "city": "Bengaluru", "region_id": 3, "baseline": "critical"},
    {"bank_id": 9, "name": "Hebbal Emergency Bank", "city": "Bengaluru", "region_id": 3, "baseline": "warning"},
    {"bank_id": 10, "name": "Chennai Central Bank", "city": "Chennai", "region_id": 4, "baseline": "healthy"},
    {"bank_id": 11, "name": "Guindy Metro Depot", "city": "Chennai", "region_id": 4, "baseline": "warning"},
    {"bank_id": 12, "name": "T. Nagar Emergency Bank", "city": "Chennai", "region_id": 4, "baseline": "healthy"},
]

BLOOD_GROUPS = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"]
RARE_GROUPS = ["AB-", "O-", "B-", "A-"]

# Stores mapping: bank_id -> blood_group -> { units: float, expiring: float, last_updated: datetime }
inventory_store = {}

def get_base_units(bank_baseline, bg):
    is_rare = bg in RARE_GROUPS
    base = 15.0 if is_rare else 45.0
    
    if bank_baseline == "healthy":
        return random.uniform(base * 1.0, base * 1.8)
    elif bank_baseline == "warning":
        return random.uniform(base * 0.4, base * 0.7)
    else: # critical
        return random.uniform(base * 0.05, base * 0.3)

def init_inventory():
    for bank in BANKS:
        bid = bank["bank_id"]
        inventory_store[bid] = {}
        for bg in BLOOD_GROUPS:
            units = get_base_units(bank["baseline"], bg)
            expiring = units * random.uniform(0.02, 0.12)
            inventory_store[bid][bg] = {
                "units_available": round(units, 1),
                "units_expiring_3days": round(expiring, 1),
                "last_updated": datetime.now().isoformat()
            }

# Initialize stock
init_inventory()

# Background task to fluctuate inventory
async def inventory_simulator():
    while True:
        await asyncio.sleep(4)  # update stock every 4 seconds
        # Pick 2-4 random banks to fluctuate
        selected_banks = random.sample(BANKS, k=random.randint(2, 4))
        for bank in selected_banks:
            bid = bank["bank_id"]
            groups = random.sample(BLOOD_GROUPS, k=random.randint(1, 3))
            for bg in groups:
                # Decide delta: donation (+) or usage (-)
                delta = random.choice([
                    random.uniform(0.8, 3.8),   # donation (positive delta)
                    random.uniform(-0.8, -4.2)  # usage (negative delta)
                ])
                # Check bounds
                current = inventory_store[bid][bg]["units_available"]
                if current > 85.0:
                    delta = -abs(delta) # force reduction
                elif current < 3.0:
                    delta = abs(delta)  # force increase
                
                new_units = max(0.5, round(current + delta, 1))
                new_exp = max(0.0, round(new_units * random.uniform(0.02, 0.12), 1))
                
                inventory_store[bid][bg] = {
                    "units_available": new_units,
                    "units_expiring_3days": new_exp,
                    "last_updated": datetime.now().isoformat()
                }

@app.on_event("startup")
async def startup_event():
    # Start simulator in background
    asyncio.create_task(inventory_simulator())

@app.get("/api/inventory")
async def get_inventory(bank_id: int = None):
    # Returns inventory for a specific bank or all banks
    if bank_id is not None:
        if bank_id in inventory_store:
            data = []
            for bg, val in inventory_store[bank_id].items():
                data.append({
                    "blood_group": bg,
                    "units_available": val["units_available"],
                    "units_expiring_3days": val["units_expiring_3days"],
                    "last_updated": val["last_updated"]
                })
            bank = next((b for b in BANKS if b["bank_id"] == bank_id), None)
            return JSONResponse(content={
                "bank_id": bank_id,
                "name": bank["name"] if bank else "Unknown Bank",
                "city": bank["city"] if bank else "Unknown",
                "inventory": data
            })
        else:
            return JSONResponse(status_code=404, content={"detail": f"Bank ID {bank_id} not found."})
            
    # Return all inventory data flattened
    result = []
    for bank in BANKS:
        bid = bank["bank_id"]
        for bg, val in inventory_store[bid].items():
            ratio = val["units_available"] / (15.0 if bg in RARE_GROUPS else 45.0)
            if ratio < 0.35:
                status = "critical"
            elif ratio < 0.7:
                status = "warning"
            else:
                status = "healthy"
                
            result.append({
                "bank_id": bid,
                "bank_name": bank["name"],
                "city": bank["city"],
                "blood_group": bg,
                "units": val["units_available"],
                "expiring": val["units_expiring_3days"],
                "status": status,
                "updated_at": val["last_updated"]
            })
    return JSONResponse(content=result)

@app.get("/", response_class=HTMLResponse)
async def serve_dashboard():
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>RaktSetu Open Data — National Blood Inventory (Live Stream)</title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=Outfit:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  :root {
    --bg-gradient: linear-gradient(135deg, #09090b 0%, #111115 100%);
    --card: rgba(20, 20, 25, 0.75);
    --border: rgba(255, 255, 255, 0.08);
    --border-hover: rgba(255, 255, 255, 0.16);
    --text-primary: #f4f4f5;
    --text-secondary: #a1a1aa;
    --text-muted: #71717a;
    
    --accent: #ef4444;
    --accent-glow: rgba(239, 68, 68, 0.25);
    
    --red-bg: rgba(239, 68, 68, 0.12);
    --red-text: #fca5a5;
    --red-solid: #ef4444;
    
    --amber-bg: rgba(245, 158, 11, 0.12);
    --amber-text: #fde047;
    --amber-solid: #f59e0b;
    
    --green-bg: rgba(16, 185, 129, 0.12);
    --green-text: #a7f3d0;
    --green-solid: #10b981;
    
    --blue-bg: rgba(59, 130, 246, 0.15);
    --blue-text: #93c5fd;
    --blue-solid: #3b82f6;
  }
  
  * { box-sizing: border-box; outline: none; }
  body { 
    margin: 0; 
    background: var(--bg-gradient); 
    color: var(--text-primary); 
    font-family: 'Plus Jakarta Sans', sans-serif;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
  }
  
  .wrap { max-width: 1200px; margin: 0 auto; padding: 40px 24px 80px; }
  
  header { 
    display: flex; 
    justify-content: space-between; 
    align-items: center; 
    margin-bottom: 24px; 
    flex-wrap: wrap; 
    gap: 16px; 
  }
  
  .title-group h1 { 
    font-family: 'Outfit', sans-serif;
    font-size: 32px; 
    font-weight: 700; 
    margin: 0 0 6px; 
    background: linear-gradient(120deg, #ffffff 30%, #a1a1aa 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  
  .subtitle { font-size: 15px; color: var(--text-secondary); margin: 0; }
  
  .badge-row { display: flex; gap: 10px; align-items: center; }
  
  .pill { 
    font-size: 13px; 
    padding: 6px 14px; 
    border-radius: 100px; 
    font-weight: 600; 
    display: inline-flex;
    align-items: center;
    border: 1px solid transparent;
  }
  
  .pill-demo { 
    background: var(--amber-bg); 
    color: var(--amber-text); 
    border-color: rgba(245, 158, 11, 0.2);
  }
  
  .pill-live { 
    background: var(--green-bg); 
    color: var(--green-text); 
    border-color: rgba(16, 185, 129, 0.2);
    gap: 8px; 
  }
  
  .dot { 
    width: 8px; 
    height: 8px; 
    border-radius: 50%; 
    background: var(--green-solid); 
    box-shadow: 0 0 8px var(--green-solid);
    animation: pulse 1.5s infinite; 
  }
  
  @keyframes pulse { 
    0%, 100% { transform: scale(1); opacity: 1; } 
    50% { transform: scale(1.2); opacity: 0.4; } 
  }
  
  .disclaimer { 
    background: rgba(20, 20, 25, 0.4); 
    border: 1px solid var(--border); 
    backdrop-filter: blur(10px);
    color: var(--text-secondary); 
    font-size: 14px; 
    line-height: 1.6; 
    padding: 16px 20px; 
    border-radius: 14px; 
    margin-bottom: 32px; 
    border-left: 4px solid var(--amber-solid);
  }
  
  .disclaimer b { color: var(--text-primary); font-weight: 600; }
  
  .topbar { 
    display: flex; 
    gap: 16px; 
    align-items: center; 
    margin-bottom: 24px; 
    flex-wrap: wrap; 
  }
  
  select, input[type=text] { 
    font-family: inherit;
    font-size: 14px; 
    padding: 12px 16px; 
    border: 1px solid var(--border); 
    border-radius: 12px; 
    background: var(--card); 
    color: var(--text-primary); 
    transition: all 0.25s ease;
    backdrop-filter: blur(12px);
  }
  
  select:hover, input[type=text]:hover {
    border-color: var(--border-hover);
  }
  
  select:focus, input[type=text]:focus {
    border-color: var(--blue-solid);
    box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
  }
  
  input[type=text] { flex: 1; min-width: 260px; }
  
  .meta-right { 
    margin-left: auto; 
    font-size: 14px; 
    color: var(--text-secondary); 
    display: flex;
    align-items: center;
    gap: 16px;
  }
  
  .meta-right span { color: var(--text-primary); font-weight: 600; }
  
  .stats { 
    display: grid; 
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); 
    gap: 16px; 
    margin-bottom: 32px; 
  }
  
  .stat-card { 
    background: var(--card); 
    border: 1px solid var(--border); 
    backdrop-filter: blur(12px);
    border-radius: 16px; 
    padding: 20px; 
    transition: transform 0.2s ease, border-color 0.2s ease;
  }
  
  .stat-card:hover {
    transform: translateY(-2px);
    border-color: var(--border-hover);
  }
  
  .stat-label { 
    font-size: 12px; 
    color: var(--text-muted); 
    margin: 0 0 8px; 
    text-transform: uppercase; 
    letter-spacing: .08em; 
    font-weight: 700;
  }
  
  .stat-value { 
    font-size: 32px; 
    font-weight: 700; 
    margin: 0; 
    font-family: 'Outfit', sans-serif;
  }
  
  .stat-sub { font-size: 13px; color: var(--text-muted); margin-top: 6px; }
  
  .table-container {
    background: var(--card);
    border: 1px solid var(--border);
    backdrop-filter: blur(12px);
    border-radius: 20px;
    overflow: hidden;
    margin-bottom: 40px;
  }
  
  table { width: 100%; border-collapse: collapse; text-align: left; }
  
  thead th { 
    font-size: 12px; 
    color: var(--text-secondary); 
    text-transform: uppercase; 
    letter-spacing: .08em; 
    padding: 18px 24px; 
    border-bottom: 1px solid var(--border); 
    background: rgba(255, 255, 255, 0.02);
    font-weight: 700;
  }
  
  tbody td { 
    padding: 16px 24px; 
    font-size: 15px; 
    border-bottom: 1px solid var(--border); 
    transition: background-color 0.3s ease;
  }
  
  tbody tr:last-child td { border-bottom: none; }
  tbody tr { transition: background-color 0.2s ease; }
  tbody tr:hover { background: rgba(255, 255, 255, 0.02); }
  
  .bank-name { font-weight: 600; color: var(--text-primary); font-size: 15px; }
  .bank-city { color: var(--text-muted); font-size: 12px; margin-top: 3px; }
  
  .blood-group-badge {
    display: inline-block;
    padding: 6px 12px;
    border-radius: 8px;
    font-weight: 700;
    font-size: 14px;
    font-family: 'Outfit', sans-serif;
    background: rgba(255, 255, 255, 0.06);
    color: var(--text-primary);
    text-align: center;
    min-width: 48px;
  }
  
  .status-pill { 
    font-size: 12px; 
    font-weight: 700; 
    padding: 4px 12px; 
    border-radius: 100px; 
    display: inline-flex; 
    align-items: center;
    text-transform: capitalize;
  }
  
  .status-healthy { background: var(--green-bg); color: var(--green-text); }
  .status-warning { background: var(--amber-bg); color: var(--amber-text); }
  .status-critical { background: var(--red-bg); color: var(--red-text); }
  
  .units-cell {
    font-family: 'Outfit', sans-serif;
    font-size: 16px;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 12px;
    transition: background 0.4s ease;
  }
  
  .units-flash-highlight {
    animation: flashAnimation 1.2s ease-out;
  }
  
  @keyframes flashAnimation {
    0% { background-color: rgba(59, 130, 246, 0.25); color: var(--blue-text); }
    100% { background-color: transparent; }
  }
  
  .bg-bar { 
    width: 80px; 
    height: 8px; 
    border-radius: 4px; 
    background: rgba(255, 255, 255, 0.08); 
    position: relative; 
    display: inline-block;
    overflow: hidden;
  }
  
  .bg-bar-fill { 
    position: absolute; 
    left: 0; 
    top: 0; 
    height: 100%; 
    border-radius: 4px; 
    transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1);
  }
  
  footer { 
    margin-top: 40px; 
    font-size: 13px; 
    color: var(--text-muted); 
    text-align: center; 
    line-height: 1.5;
  }
</style>
</head>
<body>
<div class="wrap">

  <header>
    <div class="title-group">
      <h1>RaktSetu Open Data</h1>
      <p class="subtitle">Simulating live, real-time national blood inventory feeds</p>
    </div>
    <div class="badge-row">
      <span class="pill pill-demo">Simulation Feed — Test Hub</span>
      <span class="pill pill-live"><span class="dot"></span>Live Updating</span>
    </div>
  </header>

  <div class="disclaimer">
    <b>Connected to BloodSense / RaktRekha.</b> This dashboard is running an active backend simulation. It provides a real-time HTTP JSON stream at <code>/api/inventory</code> with randomized blood unit fluctuations. It represents all 12 blood banks available in the Flutter app's local database. Your Flutter application can connect directly to this port to retrieve live-synced inventory metrics.
  </div>

  <div class="topbar">
    <select id="cityFilter">
      <option value="all">All cities</option>
    </select>
    <select id="bgFilter">
      <option value="all">All blood groups</option>
    </select>
    <input type="text" id="search" placeholder="Search blood bank by name...">
    <div class="meta-right">
      <div>Last update: <span id="lastUpdated">--</span></div>
    </div>
  </div>

  <div class="stats">
    <div class="stat-card">
      <p class="stat-label">Banks tracked</p>
      <p class="stat-value" id="statBanks">12</p>
      <p class="stat-sub">across 4 major regions</p>
    </div>
    <div class="stat-card">
      <p class="stat-label">Total blood units</p>
      <p class="stat-value" id="statUnits">--</p>
      <p class="stat-sub" id="statUnitsDelta">monitoring live fluctuations</p>
    </div>
    <div class="stat-card">
      <p class="stat-label">Critical Shortages</p>
      <p class="stat-value" id="statCritical" style="color: var(--red-text);">--</p>
      <p class="stat-sub">BSSI score above threshold</p>
    </div>
    <div class="stat-card">
      <p class="stat-label">Expiring in 3 Days</p>
      <p class="stat-value" id="statExpiring" style="color: var(--amber-text);">--</p>
      <p class="stat-sub">across all groups</p>
    </div>
  </div>

  <div class="table-container">
    <table>
      <thead>
        <tr>
          <th>Blood Bank</th>
          <th>Blood Group</th>
          <th>Units Available</th>
          <th>Expiring (3d)</th>
          <th>BSSI Severity</th>
          <th>Last Synced</th>
        </tr>
      </thead>
      <tbody id="tableBody">
        <tr>
          <td colspan="6" style="text-align: center; color: var(--text-muted); padding: 40px;">
            Connecting to RaktSetu streaming feed...
          </td>
        </tr>
      </tbody>
    </table>
  </div>

  <footer>
    RaktSetu Simulation Hub · Port 8081 · Designed for Real-Time Integration tests<br>
    Updates are pushed every 4 seconds to clients pulling the REST feed.
  </footer>

</div>

<script>
let inventory = [];
let prevTotalUnits = null;
let previousUnitsMap = {}; // Tracks bankId-bg -> units to trigger flash animations

function fmtTime(dateStr) {
  const d = new Date(dateStr);
  return d.toLocaleTimeString("en-IN", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function fmtAgo(dateStr) {
  const sec = Math.floor((Date.now() - new Date(dateStr).getTime()) / 1000);
  if (sec < 5) return "just now";
  if (sec < 60) return sec + "s ago";
  const min = Math.floor(sec / 60);
  return min + "m ago";
}

function maxUnitsFor(bg) {
  const vals = inventory.filter(r => r.blood_group === bg).map(r => r.units);
  return Math.max(...vals, 1);
}

function populateFiltersOnce(data) {
  const citySel = document.getElementById("cityFilter");
  const cities = [...new Set(data.map(b => b.city))];
  cities.forEach(c => {
    const opt = document.createElement("option");
    opt.value = c; opt.textContent = c;
    citySel.appendChild(opt);
  });
  
  const bgSel = document.getElementById("bgFilter");
  const groups = [...new Set(data.map(b => b.blood_group))];
  // Sort them
  const order = ["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"];
  order.forEach(bg => {
    if (groups.includes(bg)) {
      const opt = document.createElement("option");
      opt.value = bg; opt.textContent = bg;
      bgSel.appendChild(opt);
    }
  });
}

let filtersPopulated = false;

function render() {
  const cityFilter = document.getElementById("cityFilter").value;
  const bgFilter = document.getElementById("bgFilter").value;
  const search = document.getElementById("search").value.toLowerCase();

  const filtered = inventory.filter(r => {
    if (cityFilter !== "all" && r.city !== cityFilter) return false;
    if (bgFilter !== "all" && r.blood_group !== bgFilter) return false;
    if (search && !r.bank_name.toLowerCase().includes(search)) return false;
    return true;
  });

  const tbody = document.getElementById("tableBody");
  tbody.innerHTML = "";
  
  filtered.forEach(r => {
    const tr = document.createElement("tr");
    const maxU = maxUnitsFor(r.blood_group);
    const pct = Math.min(100, Math.round((r.units / maxU) * 100));
    
    let barColor = "var(--green-solid)";
    if (r.status === "critical") barColor = "var(--red-solid)";
    else if (r.status === "warning") barColor = "var(--amber-solid)";
    
    const key = `${r.bank_id}-${r.blood_group}`;
    const prevVal = previousUnitsMap[key];
    let highlightClass = "";
    
    if (prevVal !== undefined && prevVal !== r.units) {
      highlightClass = "units-flash-highlight";
    }
    previousUnitsMap[key] = r.units;

    tr.innerHTML = `
      <td>
        <div class="bank-name">${r.bank_name}</div>
        <div class="bank-city">${r.city}</div>
      </td>
      <td><span class="blood-group-badge">${r.blood_group}</span></td>
      <td class="units-cell ${highlightClass}">
        <span class="bg-bar"><span class="bg-bar-fill" style="width:${pct}%; background:${barColor};"></span></span>
        ${r.units}
      </td>
      <td>${r.expiring}</td>
      <td><span class="status-pill status-${r.status}">${r.status}</span></td>
      <td>${fmtAgo(r.updated_at)}</td>
    `;
    tbody.appendChild(tr);
  });

  // Calculate totals
  const totalUnits = Math.round(inventory.reduce((s, r) => s + r.units, 0));
  const totalExpiring = Math.round(inventory.reduce((s, r) => s + r.expiring, 0) * 10) / 10;
  const criticalCount = inventory.filter(r => r.status === "critical").length;

  document.getElementById("statUnits").textContent = totalUnits.toLocaleString("en-IN");
  document.getElementById("statCritical").textContent = criticalCount;
  document.getElementById("statExpiring").textContent = totalExpiring;

  const deltaEl = document.getElementById("statUnitsDelta");
  if (prevTotalUnits !== null) {
    const diff = totalUnits - prevTotalUnits;
    if (diff !== 0) {
      deltaEl.textContent = (diff >= 0 ? "+" : "") + diff + " units fluctuated";
      deltaEl.style.color = diff >= 0 ? "var(--green-text)" : "var(--red-text)";
    }
  } else {
    deltaEl.textContent = "Live inventory tracking active";
  }
  prevTotalUnits = totalUnits;
}

async function fetchUpdates() {
  try {
    const res = await fetch("/api/inventory");
    const data = await res.json();
    inventory = data;
    
    if (!filtersPopulated && data.length > 0) {
      populateFiltersOnce(data);
      filtersPopulated = true;
    }
    
    document.getElementById("lastUpdated").textContent = fmtTime(new Date());
    render();
  } catch (e) {
    console.error("Error fetching live feed: ", e);
  }
}

// Initial fetch
fetchUpdates();

// Poll API every 2 seconds
setInterval(fetchUpdates, 2000);

// Fast time updates in UI
setInterval(() => {
  if (inventory.length > 0) {
    render();
  }
}, 1000);

document.getElementById("cityFilter").addEventListener("change", render);
document.getElementById("bgFilter").addEventListener("change", render);
document.getElementById("search").addEventListener("input", render);
</script>
</body>
</html>
"""
    return HTMLResponse(content=html_content)

if __name__ == "__main__":
    uvicorn.run("live_feed:app", host="0.0.0.0", port=8081, reload=True)
