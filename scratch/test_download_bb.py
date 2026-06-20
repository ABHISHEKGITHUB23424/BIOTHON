import urllib.request

url = "https://raw.githubusercontent.com/atmajitg/bloodbanks/master/blood-banks.csv"
try:
    print("Attempting to download India Blood Bank Directory...")
    response = urllib.request.urlopen(url, timeout=5)
    data = response.read(200)
    print("Download successful! First 200 bytes:")
    print(data.decode('utf-8'))
except Exception as e:
    print(f"Error occurred: {e}")
