"""Pinned upstream URL corpus, downloaded into ignored build storage."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
REVISION='c48d58747e1f211527fb695fd60548a997fae617'
SHA256='81e85fd3c199c08ef9c34cf651b3580eeedd080316493bfaf277a6b5ff8cf652'
URL=f'https://raw.githubusercontent.com/web-platform-tests/wpt/{REVISION}/url/resources/urltestdata.json'

def rows():
    path=ROOT/'build/wpt-urltestdata.json'
    if not path.exists():
        path.parent.mkdir(parents=True,exist_ok=True)
        with urllib.request.urlopen(URL,timeout=60) as response:
            path.write_bytes(response.read())
    data=path.read_bytes()
    assert hashlib.sha256(data).hexdigest()==SHA256, 'WPT URL corpus hash mismatch'
    return [(index,row) for index,row in enumerate(json.loads(data)) if isinstance(row,dict)]

def scalar_value(text):
    # The URL Web IDL boundary replaces lone UTF-16 surrogates. Bend strings are
    # scalar sequences, so materialize that boundary conversion in the adapter.
    return text.encode('utf-16-le','surrogatepass').decode('utf-16-le','replace')
