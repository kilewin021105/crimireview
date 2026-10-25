"""Parse a PRC TOS annex (Board Res. No. 2 s. 2024) by word positions.

Every row of the table that carries an item count is found by the number in
the "No. of Item" column; the numbers to its right are assigned to the Bloom
column whose header is closest horizontally. The text of a row is the words
in the left column since the previous row. Prints the rows and the checks.
"""
import sys, re, json
sys.path.insert(0, sys.argv[1])
sys.stdout.reconfigure(encoding="utf-8")
import pymupdf

BLOOM = ["Remembering", "Understanding", "Applying", "Analyzing", "Evaluating", "Creating"]
doc = pymupdf.open(sys.argv[2])

# header x-centres from page 1
p0 = doc[0].get_text("words")
centers = {}
for w in p0:
    for b in BLOOM:
        if w[4].startswith(b[:6]) and b not in centers:
            centers[b] = (w[0] + w[2]) / 2
item_hdr = [w for w in p0 if w[4] in ("Item", "Item.")]
wgt_hdr = [w for w in p0 if w[4] == "Wgt"]
if len(centers) != 6 or not item_hdr or not wgt_hdr:
    raise SystemExit(f"headers not found: {centers} {item_hdr} {wgt_hdr}")
items_x = (item_hdr[0][0] + item_hdr[0][2]) / 2 - 12   # "No. of Item" centre (header text spans two words)
wgt_x = (wgt_hdr[0][0] + wgt_hdr[0][2]) / 2
left_limit = wgt_x - 25

rows, pending = [], []
num = re.compile(r"^\d+(\.\d+)?%?$")
for pno, page in enumerate(doc):
    words = sorted(page.get_text("words"), key=lambda w: (round(w[1] / 3), w[0]))
    # group into lines by y
    lines = []
    for w in words:
        yc = (w[1] + w[3]) / 2
        if lines and abs(lines[-1][0] - yc) < 3.5:
            lines[-1][1].append(w)
        else:
            lines.append([yc, [w]])
    for yc, ws in lines:
        text_ws = [w for w in ws if w[2] <= left_limit]
        nums = [w for w in ws if w[0] > left_limit and num.match(w[4])]
        pending.extend(w[4] for w in text_ws)
        # a data row has a number under "No. of Item"
        item_w = [w for w in nums if abs((w[0] + w[2]) / 2 - items_x) < 22]
        if not item_w:
            continue
        wgt_w = [w for w in nums if abs((w[0] + w[2]) / 2 - wgt_x) < 25]
        bloom = {b: 0 for b in BLOOM}
        for w in nums:
            xc = (w[0] + w[2]) / 2
            if xc < items_x + 22:
                continue
            b = min(BLOOM, key=lambda k: abs(centers[k] - xc))
            bloom[b] += int(float(w[4]))
        rows.append({
            "page": pno + 1,
            "text": " ".join(pending).strip(),
            "wgt": wgt_w[0][4] if wgt_w else "",
            "items": int(float(item_w[0][4])),
            "bloom": bloom,
        })
        pending = []

json.dump(rows, open(sys.argv[3], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
for r in rows:
    b = " ".join(f"{k[:3]}{v}" for k, v in r["bloom"].items() if v)
    flag = "" if sum(r["bloom"].values()) == r["items"] else "  <-- BLOOM != ITEMS"
    print(f"p{r['page']} [{r['wgt']:>6}] {r['items']:>3} | {b:<28} | {r['text'][:95]}{flag}")
