"""Fetch Liquipedia Dota 2 wikitext in one batched MediaWiki API query (gzip, one request, as the API terms ask)."""
import gzip, json, sys, urllib.parse, urllib.request
titles = sys.argv[2].split("|")
out = sys.argv[1]
params = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "redirects": "1",
          "format": "json", "titles": "|".join(titles)}
url = "" + (sys.argv[3] if len(sys.argv) > 3 else "https://liquipedia.net/dota2/api.php") + "?" + urllib.parse.urlencode(params)
req = urllib.request.Request(url, headers={"User-Agent": "WarriorsOfAether-research/1.0 (lemonquake@gmail.com)",
                                           "Accept-Encoding": "gzip"})
with urllib.request.urlopen(req, timeout=60) as r:
    data = r.read()
    if r.headers.get("Content-Encoding") == "gzip":
        data = gzip.decompress(data)
j = json.loads(data)
pages = j.get("query", {}).get("pages", {})
res = {}
for p in pages.values():
    revs = p.get("revisions")
    res[p.get("title")] = revs[0]["slots"]["main"]["*"] if revs else None
json.dump({"redirects": j.get("query", {}).get("redirects"), "pages": res}, open(out, "w", encoding="utf-8"), indent=1)
for k, v in res.items():
    print(k, len(v) if v else "MISSING")
