"""Builds the six study modules (assets/modules/<subject>_module.json) from
content/tos/modules/<code>.md, one chapter per TOS topic and one section per
TOS competency, and checks that every topic and competency has its notes.

Source format (content/tos/modules/clj.md):

    # CLJ-1
    Intro: One paragraph that opens the chapter.
    Terms: Term one; Term two; Term three

    ## CLJ-1.1 Short section title
    Key: The one-sentence key point shown in the study notes before a quiz.
    - A bullet
    - Another bullet
    A plain paragraph.

Run:  python tools/tos/build_modules.py
"""
import json, os, re, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOS = json.load(open(os.path.join(ROOT, "assets", "tos", "tos_2024.json"), encoding="utf-8"))
SRC = os.path.join(ROOT, "content", "tos", "modules")
OUT = os.path.join(ROOT, "assets", "modules")
CITATION = "PRB of Criminology Res. No. 02 s. 2024, as amended by Res. No. 06 s. 2025"


def parse(path):
    chapters, chapter, section = {}, None, None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip()
        if not line.strip():
            continue
        m = re.match(r"^# (\S+)\s*$", line)
        if m:
            chapter = {"code": m.group(1), "intro": "", "terms": [], "sections": [], "line": n}
            chapters[chapter["code"]] = chapter
            section = None
            continue
        m = re.match(r"^## (\S+) (.+)$", line)
        if m:
            if chapter is None:
                raise SystemExit(f"{path}:{n}: section before any chapter")
            section = {"code": m.group(1), "title": m.group(2).strip(), "key": "", "body": [], "line": n}
            chapter["sections"].append(section)
            continue
        if section is None and chapter is not None:
            if line.startswith("Intro: "):
                chapter["intro"] = line[7:].strip()
            elif line.startswith("Terms: "):
                chapter["terms"] = [t.strip() for t in line[7:].split(";") if t.strip()]
            else:
                raise SystemExit(f"{path}:{n}: text outside a section: {line[:60]}")
            continue
        if line.startswith("Key: "):
            section["key"] = line[5:].strip()
        else:
            section["body"].append(line.strip())
    return chapters


def main():
    problems = []
    total_sections = 0
    for subj in TOS["subjects"]:
        path = os.path.join(SRC, f"{subj['code'].lower()}.md")
        if not os.path.exists(path):
            problems.append(f"{subj['code']}: {path} is missing")
            continue
        parsed = parse(path)
        chapters = []
        for topic in subj["topics"]:
            src = parsed.get(topic["code"])
            if src is None:
                problems.append(f"{topic['code']}: no chapter")
                continue
            if not src["intro"]:
                problems.append(f"{topic['code']}: no Intro")
            if len(src["terms"]) < 4:
                problems.append(f"{topic['code']}: fewer than 4 Terms")
            by_code = {s["code"]: s for s in src["sections"]}
            extra = set(by_code) - {c["code"] for c in topic["competencies"]}
            if extra:
                problems.append(f"{topic['code']}: sections for unknown competencies {sorted(extra)}")
            content, key_points = [f"## {topic['title']}", ""], []
            for comp in topic["competencies"]:
                s = by_code.get(comp["code"])
                if s is None:
                    problems.append(f"{comp['code']}: no section")
                    continue
                if not s["key"]:
                    problems.append(f"{comp['code']}: no Key line")
                bullets = [b for b in s["body"] if b.startswith("- ")]
                if len(bullets) < 2:
                    problems.append(f"{comp['code']}: fewer than 2 bullets")
                if ":" in s["title"]:
                    problems.append(f"{comp['code']}: no colons in section titles (the reader drops them)")
                total_sections += 1
                content += [f"### {comp['no']} {s['title']}", "",
                            f"TOS competency {comp['no']} ({comp['items']} item{'s' if comp['items'] != 1 else ''}): {comp['text']}",
                            ""] + s["body"] + [""]
                key_points.append({"code": comp["code"], "title": s["title"], "note": s["key"]})
            chapters.append({
                "number": topic["no"],
                "code": topic["code"],
                "title": topic["title"],
                "itemCount": topic["items"],
                "introduction": src["intro"],
                "content": "\n".join(content).strip() + "\n",
                "keyPoints": key_points,
                "keyTerms": src["terms"],
            })
        module = {
            "id": subj["subject_id"],
            "title": subj["name"],
            "description": f"Study module for {subj['name']} ({subj['weight']}% of the Criminologist Licensure "
                           f"Examination), organized by the topics and competencies of the PRC Table of Specifications.",
            "source": CITATION,
            "totalItems": 100,
            "status": "Written with AI assistance from the TOS competencies and the laws they name; "
                      "for faculty review (content/tos/SOURCES.md).",
            "chapters": chapters,
        }
        out = os.path.join(OUT, f"{subj['subject_id']}_module.json")
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            json.dump(module, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"{subj['code']}: {len(chapters)} chapters -> {os.path.relpath(out, ROOT)}")
    if problems:
        print(f"\n{len(problems)} PROBLEM(S):")
        print("\n".join("- " + p for p in problems))
        sys.exit(1)
    print(f"\nAll {total_sections} competencies have notes.")


if __name__ == "__main__":
    main()
