"""Build tos_2024.json from the parsed PRC annex rows, apply Res. No. 6 s. 2025,
and check every count. Usage: python tos_build.py <rows dir> <out json>"""
import sys, re, json

sys.stdout.reconfigure(encoding="utf-8")
ROWS, OUT = sys.argv[1], sys.argv[2]
BLOOM = ["Remembering", "Understanding", "Applying", "Analyzing", "Evaluating", "Creating"]
SUBJECTS = [
    # app subject id, file, short code, official name, weight
    ("criminal_jurisprudence", "clj", "CLJ", "Criminal Law and Jurisprudence", 20, "ANNEX%20A_CLJ.pdf"),
    ("law_enforcement", "lea", "LEA", "Law Enforcement Administration", 15, "ANNEX%20A_LEA.pdf"),
    ("criminalistics", "forensic", "FS", "Forensic Science", 15, "ANNEX%20A_Forensic%20Science.pdf"),
    ("crime_detection", "cdi", "CDI", "Crime Detection and Investigation", 20, "ANNEX%20A_CDI.pdf"),
    ("criminology", "criminology", "CRIM", "Criminology", 20, "ANNEX%20A_Criminology.pdf"),
    ("corrections", "corad", "CA", "Correctional Administration", 10, "ANNEX%20A_Corad_0.pdf"),
]
CODE = re.compile(r"(?<![\d.])(\d{1,2})\.(\d{1,2})?\.?\s")


def clean(t):
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"\s+([,.;:)])", r"\1", t)
    # PDF word-splits seen in the annexes
    for a, b in [("s tages", "stages"), ("c ircumstances", "circumstances"), ("R eprieve", "Reprieve"),
                 ("pet ition", "petition"), ("ro le", "role"), ("extin ction", "extinction"), ("RA 8 749", "RA 8749"),
                 ("adisorders", "disorders"), ("Schiziphrenia", "Schizophrenia"), ("the1987", "the 1987"),
                 ("Provintial", "Provincial"), ("estafa  and", "estafa and"),
                 ("Formation 1-Nationalism", "Formation 1 - Nationalism"),
                 ("Formation 2- Leadership", "Formation 2 - Leadership")]:
        t = t.replace(a, b)
    t = re.sub(r"([Dd]ecision)- making", r"\1-making", t)
    # LEA 6.4 is the last row before the subject total, which ran into its text
    t = re.sub(r"\s+Total$", "", t)
    return t


def load(file):
    rows = json.load(open(f"{ROWS}/rows_{file}.json", encoding="utf-8"))
    rows = [r for r in rows if not r["text"].startswith("Board of Criminology") and r["text"] != "Total"
            and not r["text"].lower().startswith("total")]
    # move text that ran over a page break back to the row it belongs to
    for i, r in enumerate(rows):
        m = CODE.search(r["text"] + " ")
        if m and m.start() > 0 and i > 0:
            rows[i - 1]["text"] += " " + r["text"][: m.start()]
            r["text"] = r["text"][m.start():]
    # LEA's last row (6.4) ends with words after the subject total; they were cut by the filter
    return rows


def build(app_id, file, code, name, weight, annex):
    rows = load(file)
    # a trailing fragment with no code belongs to the last competency
    topics = []
    for r in rows:
        text = clean(r["text"])
        m = re.match(r"^(\d{1,2})\.(\d{1,2})?\.?\s+(.*)$", text)
        if not m:
            if topics and topics[-1]["competencies"]:
                topics[-1]["competencies"][-1]["text"] += " " + text
                continue
            raise SystemExit(f"{code}: row without code: {text[:80]}")
        major, minor, body = m.group(1), m.group(2), m.group(3)
        bloom = {k: v for k, v in r["bloom"].items() if v}
        if minor is None:
            body = re.sub(r"\s*\((CLJ|CLJ )\s*\d\)\s*$", "", body).strip()
            topics.append({"code": f"{code}-{major}", "no": int(major), "title": body,
                           "items": r["items"], "bloom": bloom, "competencies": []})
        else:
            topics[-1]["competencies"].append({"code": f"{code}-{major}.{minor}", "no": f"{major}.{minor}",
                                               "text": body, "items": r["items"], "bloom": bloom})
    for t in topics:
        t["title"] = re.sub(r"\s*\(CLJ \d\)", "", t["title"]).strip()
        for c in t["competencies"]:
            c["text"] = clean(c["text"])
    return {"subject_id": app_id, "code": code, "name": name, "weight": weight, "items": 100,
            "annex_url": f"https://www.prc.gov.ph/sites/default/files/{annex}", "topics": topics}


data = {
    "source": {
        "title": "Enhanced Tables of Specifications for the Subjects in the Licensure Examination for Criminologists",
        "resolution": "PRB of Criminology Resolution No. 02, Series of 2024",
        "as_of": "2024-01-22", "done": "2024-04-16", "effective": "2024-05-05",
        "first_exam": "July 2024 Licensure Examination for Criminologists",
        "url": "https://www.prc.gov.ph/sites/default/files/2024-02%20Published%20%281%29%20%281%29.pdf",
        "amendment": {
            "resolution": "PRB of Criminology Resolution No. 06, Series of 2025",
            "done": "2025-06-26", "effective": "2025-07-16",
            "first_exam": "August 2025 Licensure Examination for Criminologists",
            "changes": "Criminology Topic 4 replaced: Professional Conduct and Ethical Standards for Criminologists, "
                       "based on the Code of Ethical and Professional Conduct of Philippine Registered Criminologists "
                       "(Board Resolution No. 07, Series of 2024, effective January 31, 2025).",
            "url": "https://www.prc.gov.ph/sites/default/files/2025-06%20published%20Amendments%20To%20Board%20Resolution%20No.%2002%20%28S.%202024%29%20in%20the%20Subject%20Area%20of%20Criminology.pdf",
        },
        "bloom_levels": BLOOM,
    },
    "subjects": [build(*s) for s in SUBJECTS],
}

# Res. No. 06 s. 2025: Criminology Topic 4 as amended (Annex A of that resolution)
crim = next(s for s in data["subjects"] if s["code"] == "CRIM")
t4 = next(t for t in crim["topics"] if t["no"] == 4)
t4.update({
    "title": "Professional Conduct and Ethical Standards for Criminologists",
    "items": 15,
    "bloom": {"Understanding": 2, "Applying": 11, "Analyzing": 2},
    "amended_by": "Resolution No. 06 s. 2025",
    "competencies": [
        {"code": "CRIM-4.1", "no": "4.1", "items": 2, "bloom": {"Applying": 2},
         "text": "Apply Chapter 1 and 2 of the Code of Ethics and Professional Conduct of Criminologists."},
        {"code": "CRIM-4.2", "no": "4.2", "items": 3, "bloom": {"Applying": 2, "Analyzing": 1},
         "text": "Exhibit adherence to Chapter 3 of the Code of Ethics and Professional Conduct of Criminologists."},
        {"code": "CRIM-4.3", "no": "4.3", "items": 7, "bloom": {"Understanding": 1, "Applying": 5, "Analyzing": 1},
         "text": "Apply the Oath of Professionals and Chapter 4 of the Code of Ethics and Professional Conduct for Criminologists."},
        {"code": "CRIM-4.4", "no": "4.4", "items": 3, "bloom": {"Understanding": 1, "Applying": 2},
         "text": "Comprehend the concept of ethics and its practical application concerning the foundational principles of human rights."},
    ],
})

# ---- checks
problems = []
for s in data["subjects"]:
    total = sum(t["items"] for t in s["topics"])
    if total != 100:
        problems.append(f"{s['code']}: topics total {total}")
    for t in s["topics"]:
        ci = sum(c["items"] for c in t["competencies"])
        if ci != t["items"]:
            problems.append(f"{t['code']}: competencies {ci} != topic {t['items']}")
        for b in BLOOM:
            cb = sum(c["bloom"].get(b, 0) for c in t["competencies"])
            if cb != t["bloom"].get(b, 0):
                problems.append(f"{t['code']} {b}: competencies {cb} != topic {t['bloom'].get(b, 0)}")
        for c in t["competencies"]:
            if sum(c["bloom"].values()) != c["items"]:
                problems.append(f"{c['code']}: bloom {sum(c['bloom'].values())} != items {c['items']}")
    totals = {b: sum(t["bloom"].get(b, 0) for t in s["topics"]) for b in BLOOM}
    s["bloom"] = {k: v for k, v in totals.items() if v}
    print(f"{s['code']:<5} {len(s['topics'])} topics, {sum(len(t['competencies']) for t in s['topics'])} competencies, "
          f"100 items | " + " ".join(f"{k[:3]}{v}" for k, v in s["bloom"].items()))

json.dump(data, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("PROBLEMS:" if problems else "All counts consistent.", *problems, sep="\n- ")
