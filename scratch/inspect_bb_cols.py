import urllib.request
import csv
import io

url = "https://raw.githubusercontent.com/atmajitg/bloodbanks/master/blood-banks.csv"
try:
    response = urllib.request.urlopen(url, timeout=5)
    csv_text = response.read().decode('latin-1')
    reader = csv.reader(io.StringIO(csv_text))
    header = next(reader)
    print("Headers:", header)
    row = next(reader, None)
    if row:
        print("First row:")
        for h, val in zip(header, row):
            print(f"  {h}: {val}")
except Exception as e:
    print(f"Error occurred: {e}")
