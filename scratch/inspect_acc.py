import urllib.request
import csv
import io

url = "https://raw.githubusercontent.com/prash29/Traffic-Accident-Analysis/master/datafile_4.csv"
try:
    response = urllib.request.urlopen(url, timeout=5)
    csv_text = response.read().decode('utf-8-sig')
    reader = csv.reader(io.StringIO(csv_text))
    header = next(reader)
    print("Headers:", header)
    for i in range(5):
        row = next(reader, None)
        if row:
            print(f"Row {i+1}:", row)
except Exception as e:
    print(f"Error occurred: {e}")
