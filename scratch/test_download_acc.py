import urllib.request

url = "https://raw.githubusercontent.com/prash29/Traffic-Accident-Analysis/master/datafile_4.csv"
try:
    print("Attempting to download India Road Accident dataset...")
    response = urllib.request.urlopen(url, timeout=5)
    data = response.read(300)
    print("Download successful! First 300 bytes:")
    print(data.decode('utf-8'))
except Exception as e:
    print(f"Error occurred: {e}")
