import urllib.request

url = "https://archive.ics.uci.edu/ml/machine-learning-databases/blood-transfusion/transfusion.data"
try:
    print("Attempting to download UCI Blood Transfusion dataset...")
    response = urllib.request.urlopen(url, timeout=5)
    data = response.read(100)
    print("Download successful! First 100 bytes:")
    print(data)
except Exception as e:
    print(f"Error occurred: {e}")
