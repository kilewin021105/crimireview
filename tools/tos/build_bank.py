"""Checks the TOS-aligned question bank and writes supabase_tos_bank.sql.

Source: content/tos/bank/<subject code>.jsonl, one question per line:
  {"c": "CLJ-3.4", "b": "Ap", "q": "question?", "a": [correct, wrong1, wrong2, wrong3],
   "r": [why correct, why wrong1, why wrong2, why wrong3], "e": "explanation", "l": "legal basis or ''"}
The first option is the correct one; the build places it at a position taken
from the question id, so correct answers spread evenly over A-D.

Checks (the build fails on any of them):
  * every competency has exactly the TOS number of items at each Bloom level;
  * 4 non-empty, different options; a reason for every option; an explanation;
  * the correct option does not stand out by length (same rule as the app);
  * no two questions in a subject share a stem.

Run:  python tools/tos/build_bank.py            (check only)
      python tools/tos/build_bank.py --sql      (check and write the SQL)
"""
import hashlib, json, os, sys
from collections import Counter, defaultdict

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOS = json.load(open(os.path.join(ROOT, "assets", "tos", "tos_2024.json"), encoding="utf-8"))
BANK = os.path.join(ROOT, "content", "tos", "bank")
BLOOM = {"R": "Remembering", "U": "Understanding", "Ap": "Applying", "An": "Analyzing", "E": "Evaluating", "C": "Creating"}
DIFFICULTY = {"Remembering": "easy", "Understanding": "easy", "Applying": "medium",
              "Analyzing": "hard", "Evaluating": "hard", "Creating": "hard"}
STAND_OUT = 1.4


def stands_out(correct, wrong):
    c = len(correct.strip())
    longest = max(len(w.strip()) for w in wrong)
    return c > longest and c >= STAND_OUT * longest


def position(qid):
    return int(hashlib.sha256(qid.encode()).hexdigest(), 16) % 4


def sql_str(s):
    return "NULL" if s is None else "'" + s.replace("'", "''") + "'"


def main():
    write_sql = "--sql" in sys.argv
    problems, rows, report = [], [], []
    for subj in TOS["subjects"]:
        code = subj["code"]
        path = os.path.join(BANK, f"{code.lower()}.jsonl")
        comps = {c["code"]: (t, c) for t in subj["topics"] for c in t["competencies"]}
        if not os.path.exists(path):
            report.append(f"{code}: no file yet")
            continue
        items = []
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            line = line.strip()
            if not line:
                continue
            try:
                items.append((n, json.loads(line)))
            except json.JSONDecodeError as e:
                problems.append(f"{code} line {n}: bad JSON ({e})")
        have = defaultdict(Counter)
        stems, per_comp = set(), Counter()
        for n, q in items:
            where = f"{code} line {n}"
            c = q.get("c")
            if c not in comps:
                problems.append(f"{where}: unknown competency {c}")
                continue
            level = BLOOM.get(q.get("b"))
            if not level:
                problems.append(f"{where}: unknown Bloom level {q.get('b')}")
                continue
            have[c][level] += 1
            a, r = q.get("a", []), q.get("r", [])
            if len(a) != 4 or any(not str(x).strip() for x in a):
                problems.append(f"{where}: needs 4 non-empty options")
                continue
            if len({x.strip().lower() for x in a}) != 4:
                problems.append(f"{where}: options repeat")
            if len(r) != 4 or any(not str(x).strip() for x in r):
                problems.append(f"{where}: needs a reason for every option")
            if not q.get("e", "").strip():
                problems.append(f"{where}: no explanation")
            if not q.get("q", "").strip():
                problems.append(f"{where}: no question")
            if stands_out(a[0], a[1:]):
                problems.append(f"{where}: correct option stands out by length ({len(a[0])} vs {max(len(x) for x in a[1:])})")
            stem = " ".join(q["q"].lower().split())
            if stem in stems:
                problems.append(f"{where}: duplicate question")
            stems.add(stem)
            per_comp[c] += 1
            topic, comp = comps[c]
            qid = f"tos24_{c}_{per_comp[c]:02d}"
            pos = position(qid)
            order = [1, 2, 3]
            opts = [(a[i], r[i] if i < len(r) else "", i == 0) for i in order]
            opts.insert(pos, (a[0], r[0] if r else "", True))
            rows.append({
                "id": qid, "subject_id": subj["subject_id"], "topic": topic["title"], "tos_code": c,
                "bloom_level": level, "difficulty": DIFFICULTY[level], "question_text": q["q"].strip(),
                "options": [{"text": t.strip(), "is_correct": ok, "rationale": why.strip()} for t, why, ok in opts],
                "correct_answer_index": pos, "explanation": q["e"].strip(),
                "legal_basis": (q.get("l") or "").strip() or None,
                "remediation_hint": f"Study module {subj['name']}, Chapter {topic['no']}: {topic['title']} ({c}).",
            })
        # exact TOS counts per competency and Bloom level
        for ccode, (topic, comp) in comps.items():
            want = Counter(comp["bloom"])
            got = have.get(ccode, Counter())
            if got != want:
                problems.append(f"{ccode}: has {dict(got) or 'nothing'}, TOS wants {dict(want)}")
        positions = Counter(r["correct_answer_index"] for r in rows if r["subject_id"] == subj["subject_id"])
        report.append(f"{code}: {len(items)} questions; correct answer A-D = "
                      + "/".join(str(positions.get(i, 0)) for i in range(4)))

    print("\n".join(report))
    if problems:
        print(f"\n{len(problems)} PROBLEM(S):")
        print("\n".join("- " + p for p in problems[:200]))
        sys.exit(1)
    print(f"\nAll checks passed: {len(rows)} questions match the TOS exactly.")
    if not write_sql:
        return
    out = os.path.join(ROOT, "supabase_tos_bank.sql")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER.format(n=len(rows)))
        for r in rows:
            f.write(
                "INSERT INTO public.questions (id, subject_id, topic, question_text, options, correct_answer_index, "
                "difficulty, explanation, legal_basis, remediation_hint, source, template_id, version, is_active, "
                "tos_code, bloom_level) VALUES ("
                + ", ".join([sql_str(r["id"]), sql_str(r["subject_id"]), sql_str(r["topic"]), sql_str(r["question_text"]),
                             sql_str(json.dumps(r["options"], ensure_ascii=False)) + "::jsonb", str(r["correct_answer_index"]),
                             sql_str(r["difficulty"]), sql_str(r["explanation"]), sql_str(r["legal_basis"]),
                             sql_str(r["remediation_hint"]), "'generated'", "'tos_2024'", "1", "FALSE",
                             sql_str(r["tos_code"]), sql_str(r["bloom_level"])])
                + ") ON CONFLICT DO NOTHING;\n")
        f.write(FOOTER.format(n=len(rows)))
    print(f"Wrote {out}")


HEADER = """-- ================================================================
-- CrimiReview -- TOS-aligned question bank ({n} questions)
-- ================================================================
-- Generated by tools/tos/build_bank.py from content/tos/bank/*.jsonl.
-- Do not edit by hand; edit the .jsonl files and run the tool again.
--
-- 100 questions per subject, one for every item of the PRC Tables of
-- Specifications (Board Res. No. 02 s. 2024, as amended by Res. No. 06
-- s. 2025): each competency gets exactly its TOS number of items at each
-- Bloom's taxonomy level. See content/tos/SOURCES.md.
--
-- Every question is INACTIVE (is_active = FALSE, source = 'generated',
-- template_id = 'tos_2024'). Students see a question only after a faculty
-- member reviews and approves it: Admin Panel -> TOS coverage.
--
-- Run AFTER supabase_tos_alignment.sql (it adds tos_code and bloom_level).
-- Safe to run again: existing rows (and faculty edits) are never overwritten.
-- ================================================================

BEGIN;

"""

# ON CONFLICT DO NOTHING also skips a question whose stem already exists in the
# subject (uq_questions_subject_stem), so report how many actually landed.
FOOTER = """
DO $tos_bank_check$
DECLARE
  n INT;
BEGIN
  SELECT COUNT(*) INTO n FROM public.questions WHERE template_id = 'tos_2024';
  IF n < {n} THEN
    RAISE WARNING 'Only % of the {n} TOS questions are in the table; the others share a stem with an existing question.', n;
  ELSE
    RAISE NOTICE 'All {n} TOS questions are in the table (inactive until faculty approve them).';
  END IF;
END
$tos_bank_check$;

COMMIT;
"""

if __name__ == "__main__":
    main()
