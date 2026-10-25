"""Writes supabase_tos_alignment.sql and its rollback from the TOS and the topic map.

Inputs:  assets/tos/tos_2024.json   (the Tables of Specifications)
         assets/tos/topic_map.json  (old topic names -> TOS topic codes)
Outputs: supabase_tos_alignment.sql, supabase_tos_alignment_rollback.sql

If content_review/snapshot_imported.jsonl is present, the tool also checks the
map against it (every old topic mapped, no stem collisions when a question
moves to another subject, no collisions with the new TOS bank) and prints how
many questions move, stay, or are deactivated.

Run:  python tools/tos/build_alignment.py
"""
import collections, hashlib, json, os, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOS = json.load(open(os.path.join(ROOT, "assets", "tos", "tos_2024.json"), encoding="utf-8"))
MAP = json.load(open(os.path.join(ROOT, "assets", "tos", "topic_map.json"), encoding="utf-8"))
SNAPSHOT = os.path.join(ROOT, "content_review", "snapshot_imported.jsonl")
BANK = os.path.join(ROOT, "content", "tos", "bank")
BLOOM = TOS["source"]["bloom_levels"]


def s(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def j(v):
    return s(json.dumps(v, ensure_ascii=False)) + "::jsonb"


topics = {t["code"]: (subj, t) for subj in TOS["subjects"] for t in subj["topics"]}
subject_of_code = {code: subj["subject_id"] for code, (subj, t) in topics.items()}


def check_map():
    problems = []
    for subject, entries in MAP["topics"].items():
        for old, code in entries.items():
            if code is not None and code not in topics:
                problems.append(f"{subject} / {old}: unknown TOS topic {code}")
    for qid, code in MAP["overrides"].items():
        if code not in topics:
            problems.append(f"override {qid}: unknown TOS topic {code}")
    return problems


def check_snapshot():
    """Dry run of the migration on the snapshot of the live imported questions."""
    if not os.path.exists(SNAPSHOT):
        print("(no snapshot; skipped the dry run)")
        return []
    problems = []
    qs = [json.loads(line) for line in open(SNAPSHOT, encoding="utf-8")]
    lookup = {subj: {k.strip().lower(): v for k, v in m.items()} for subj, m in MAP["topics"].items()}
    flagged = set(MAP["flagged"]["ids"])
    md5 = lambda text: hashlib.md5(text.strip().lower().encode()).hexdigest()
    before = collections.defaultdict(set)   # subject -> stems before the move (what the SQL checks)
    for q in qs:
        before[q["subject_id"]].add(md5(q["question"]))
    after = collections.defaultdict(set)    # subject -> stems after the move, active or not
    arriving = collections.defaultdict(set)
    moved = stay = off = unknown = blocked = 0
    per_topic = collections.Counter()
    for q in qs:
        key = q["topic"].strip().lower()
        code = MAP["overrides"].get(q["id"], lookup.get(q["subject_id"], {}).get(key, "?"))
        h = md5(q["question"])
        if code == "?":
            unknown += 1
            after[q["subject_id"]].add(h)
            problems.append(f"snapshot {q['id']}: topic '{q['topic']}' ({q['subject_id']}) is not in the map")
            continue
        if code is None:
            off += 1
            after[q["subject_id"]].add(h)
            continue
        target = subject_of_code[code]
        if target == q["subject_id"]:
            stay += 1
        elif h in before[target]:
            # the SQL keeps it in place and deactivates it: the target already has this stem
            blocked += 1
            after[q["subject_id"]].add(h)
            continue
        else:
            if h in arriving[target]:
                problems.append(f"snapshot {q['id']}: two questions with the same stem would move into {target}")
            arriving[target].add(h)
            moved += 1
        after[target].add(h)
        per_topic[code] += 1
    off_flagged = sum(1 for q in qs if q["id"] in flagged)
    stems = after
    # new bank stems must not collide with old stems in the same subject (ON CONFLICT would skip them)
    for subj in TOS["subjects"]:
        path = os.path.join(BANK, f"{subj['code'].lower()}.jsonl")
        if not os.path.exists(path):
            continue
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if not line.strip():
                continue
            q = json.loads(line)
            h = hashlib.md5(q["q"].strip().lower().encode()).hexdigest()
            if h in stems[subj["subject_id"]]:
                problems.append(f"bank {subj['code']} line {n}: same stem as an old question")
    print(f"Dry run on {len(qs)} imported questions: {stay} keep their subject, {moved} move to another subject, "
          f"{blocked} stay put and are deactivated (the target subject already has the same question), "
          f"{off} deactivated (topic not in the TOS), {off_flagged} deactivated as flagged, {unknown} unmapped.")
    for subj in TOS["subjects"]:
        row = [f"{t['code']}={per_topic.get(t['code'], 0)}" for t in subj["topics"]]
        print("  " + "  ".join(row))
    return problems


def alignment_sql():
    out = [HEADER]
    out.append("-- 1. The TOS itself ---------------------------------------------------------")
    out.append(TABLES)
    sort = 0
    for subj in TOS["subjects"]:
        for t in subj["topics"]:
            sort += 1
            out.append("INSERT INTO public.tos_topics (code, subject_id, topic_no, title, items, bloom, amended_by, sort) VALUES ("
                       + ", ".join([s(t["code"]), s(subj["subject_id"]), str(t["no"]), s(t["title"]), str(t["items"]),
                                    j(t["bloom"]), s(t.get("amended_by")), str(sort)])
                       + ")\n  ON CONFLICT (code) DO UPDATE SET subject_id = EXCLUDED.subject_id, topic_no = EXCLUDED.topic_no, "
                         "title = EXCLUDED.title, items = EXCLUDED.items, bloom = EXCLUDED.bloom, "
                         "amended_by = EXCLUDED.amended_by, sort = EXCLUDED.sort;")
    sort = 0
    for subj in TOS["subjects"]:
        for t in subj["topics"]:
            for c in t["competencies"]:
                sort += 1
                out.append("INSERT INTO public.tos_competencies (code, topic_code, subject_id, competency_no, competency, items, bloom, sort) VALUES ("
                           + ", ".join([s(c["code"]), s(t["code"]), s(subj["subject_id"]), s(c["no"]), s(c["text"]),
                                        str(c["items"]), j(c["bloom"]), str(sort)])
                           + ")\n  ON CONFLICT (code) DO UPDATE SET topic_code = EXCLUDED.topic_code, subject_id = EXCLUDED.subject_id, "
                             "competency_no = EXCLUDED.competency_no, competency = EXCLUDED.competency, items = EXCLUDED.items, "
                             "bloom = EXCLUDED.bloom, sort = EXCLUDED.sort;")
    out.append("")
    out.append(QUESTION_COLUMNS)
    out.append("-- 3. Move the existing questions onto the TOS topics -------------------------")
    out.append("CREATE TEMP TABLE tos_topic_map (old_subject TEXT, old_topic TEXT, tos_topic TEXT) ON COMMIT DROP;")
    rows = [f"({s(subj)}, {s(old)}, {s(code)})" for subj, m in MAP["topics"].items() for old, code in m.items()]
    out.append("INSERT INTO tos_topic_map VALUES\n  " + ",\n  ".join(rows) + ";")
    out.append("CREATE TEMP TABLE tos_question_override (id TEXT PRIMARY KEY, tos_topic TEXT) ON COMMIT DROP;")
    rows = [f"({s(qid)}, {s(code)})" for qid, code in MAP["overrides"].items()]
    out.append("INSERT INTO tos_question_override VALUES\n  " + ",\n  ".join(rows) + ";")
    out.append("CREATE TEMP TABLE tos_flagged (id TEXT PRIMARY KEY) ON COMMIT DROP;")
    out.append("INSERT INTO tos_flagged VALUES " + ", ".join(f"({s(i)})" for i in MAP["flagged"]["ids"]) + ";")
    out.append(MOVE)
    out.append(MASTERY)
    out.append(COVERAGE)
    out.append(UPLOADS)
    out.append(SUMMARY)
    out.append("COMMIT;\n")
    return "\n".join(out)


HEADER = """-- ================================================================
-- CrimiReview -- align the question bank with the PRC TOS
-- ================================================================
-- Generated by tools/tos/build_alignment.py from assets/tos/tos_2024.json
-- and assets/tos/topic_map.json. Do not edit by hand.
--
-- Source: PRB of Criminology Resolution No. 02, Series of 2024 (Tables of
-- Specifications, annexes "as of January 22, 2024"), as amended by
-- Resolution No. 06, Series of 2025 (Criminology Topic 4). See
-- content/tos/SOURCES.md.
--
-- What this does, in one transaction:
--   1. Creates public.tos_topics and public.tos_competencies and fills them
--      with the 37 TOS topics and 146 competencies (readable by everyone).
--   2. Adds questions.tos_code (a TOS topic or competency code, checked by
--      a trigger) and questions.bloom_level.
--   3. Moves every existing question onto its TOS topic (subject, topic
--      name and tos_code). The old values are kept in
--      public.tos_alignment_backup so supabase_tos_alignment_rollback.sql
--      can undo it.
--   4. Deactivates (never deletes) the questions whose topic is not in the
--      TOS and the 16 questions flagged as wrong or outdated on 2026-10-22.
--   5. Merges each student's saved topic mastery into the TOS topic names
--      (old rows kept in public.tos_alignment_mastery_backup).
--   6. Adds public.admin_tos_coverage(), which the Admin Panel uses to show
--      how many questions each competency has against its TOS items.
--   7. Adds document_uploads.tos_code, so a PDF upload can target one
--      competency.
--
-- Run this FIRST, then supabase_tos_bank.sql (the 600 TOS questions).
-- Safe to run again: it only moves questions that have no tos_code yet.
-- ================================================================

BEGIN;
"""

TABLES = """CREATE TABLE IF NOT EXISTS public.tos_topics (
  code        TEXT PRIMARY KEY,               -- e.g. 'CLJ-3'
  subject_id  TEXT NOT NULL,
  topic_no    INTEGER NOT NULL,
  title       TEXT NOT NULL,
  items       INTEGER NOT NULL CHECK (items > 0),
  bloom       JSONB NOT NULL DEFAULT '{}'::jsonb,  -- items per Bloom level
  amended_by  TEXT,
  sort        INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS public.tos_competencies (
  code           TEXT PRIMARY KEY,            -- e.g. 'CLJ-3.4'
  topic_code     TEXT NOT NULL REFERENCES public.tos_topics(code) ON DELETE CASCADE,
  subject_id     TEXT NOT NULL,
  competency_no  TEXT NOT NULL,
  competency     TEXT NOT NULL,
  items          INTEGER NOT NULL CHECK (items > 0),
  bloom          JSONB NOT NULL,
  sort           INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tos_competencies_topic ON public.tos_competencies(topic_code);

ALTER TABLE public.tos_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tos_competencies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read TOS topics" ON public.tos_topics;
CREATE POLICY "Anyone can read TOS topics" ON public.tos_topics FOR SELECT TO anon, authenticated USING (TRUE);
DROP POLICY IF EXISTS "Anyone can read TOS competencies" ON public.tos_competencies;
CREATE POLICY "Anyone can read TOS competencies" ON public.tos_competencies FOR SELECT TO anon, authenticated USING (TRUE);
-- No write policies: the TOS changes only through a new migration like this one.
GRANT SELECT ON public.tos_topics, public.tos_competencies TO anon, authenticated;
"""

QUESTION_COLUMNS = """-- 2. questions.tos_code and questions.bloom_level ------------------------------
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS tos_code    TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS bloom_level TEXT;
DO $bloom$
BEGIN
  ALTER TABLE public.questions ADD CONSTRAINT questions_bloom_level_check
    CHECK (bloom_level IS NULL OR bloom_level IN
      ('Remembering', 'Understanding', 'Applying', 'Analyzing', 'Evaluating', 'Creating'));
EXCEPTION WHEN duplicate_object THEN NULL;
END
$bloom$;
CREATE INDEX IF NOT EXISTS idx_questions_tos_code ON public.questions(tos_code) WHERE tos_code IS NOT NULL;

-- A tos_code must be a real TOS topic or competency of the question's own subject.
CREATE OR REPLACE FUNCTION public.check_question_tos_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $tos_check$
DECLARE
  code_subject TEXT;
BEGIN
  IF NEW.tos_code IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT subject_id INTO code_subject FROM public.tos_competencies WHERE code = NEW.tos_code;
  IF code_subject IS NULL THEN
    SELECT subject_id INTO code_subject FROM public.tos_topics WHERE code = NEW.tos_code;
  END IF;
  IF code_subject IS NULL THEN
    RAISE EXCEPTION 'tos_code % is not a TOS topic or competency', NEW.tos_code;
  END IF;
  IF code_subject <> NEW.subject_id THEN
    RAISE EXCEPTION 'tos_code % belongs to subject %, not %', NEW.tos_code, code_subject, NEW.subject_id;
  END IF;
  RETURN NEW;
END;
$tos_check$;

DROP TRIGGER IF EXISTS questions_check_tos_code ON public.questions;
CREATE TRIGGER questions_check_tos_code
  BEFORE INSERT OR UPDATE OF tos_code, subject_id ON public.questions
  FOR EACH ROW EXECUTE FUNCTION public.check_question_tos_code();
"""

MOVE = """
-- Old values, so the move can be undone (supabase_tos_alignment_rollback.sql).
CREATE TABLE IF NOT EXISTS public.tos_alignment_backup (
  question_id    TEXT PRIMARY KEY,
  old_subject_id TEXT NOT NULL,
  old_topic      TEXT NOT NULL,
  old_is_active  BOOLEAN NOT NULL,
  reason         TEXT NOT NULL,       -- 'mapped' | 'not_in_tos' | 'flagged' | 'duplicate_stem'
  changed_at     TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.tos_alignment_backup ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read alignment backup" ON public.tos_alignment_backup;
CREATE POLICY "Admins can read alignment backup" ON public.tos_alignment_backup
  FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.tos_alignment_backup TO authenticated;

-- Questions handled by an earlier run are left alone (faculty may have re-activated them).
CREATE TEMP TABLE tos_done ON COMMIT DROP AS SELECT question_id AS id FROM public.tos_alignment_backup;

-- Where each not-yet-linked question goes. 'known' = its topic is in the map.
CREATE TEMP TABLE tos_move ON COMMIT DROP AS
SELECT q.id,
       q.subject_id AS old_subject,
       q.topic      AS old_topic,
       q.is_active  AS old_active,
       COALESCE(o.tos_topic, m.tos_topic) AS tos_topic,
       (o.id IS NOT NULL OR m.old_topic IS NOT NULL) AS known
  FROM public.questions q
  LEFT JOIN tos_question_override o ON o.id = q.id
  LEFT JOIN tos_topic_map m
         ON m.old_subject = q.subject_id
        AND lower(trim(m.old_topic)) = lower(trim(q.topic))
 WHERE q.tos_code IS NULL
   AND q.template_id IS DISTINCT FROM 'tos_2024'
   AND q.id NOT IN (SELECT id FROM tos_done);

-- A move into another subject is skipped if that subject already has the same stem.
CREATE TEMP TABLE tos_blocked ON COMMIT DROP AS
SELECT mv.id
  FROM tos_move mv
  JOIN public.tos_topics t ON t.code = mv.tos_topic
  JOIN public.questions q ON q.id = mv.id
 WHERE t.subject_id <> mv.old_subject
   AND EXISTS (SELECT 1 FROM public.questions d
                WHERE d.subject_id = t.subject_id AND d.id <> q.id
                  AND md5(lower(d.question_text)) = md5(lower(q.question_text)));

INSERT INTO public.tos_alignment_backup (question_id, old_subject_id, old_topic, old_is_active, reason)
SELECT mv.id, mv.old_subject, mv.old_topic, mv.old_active,
       CASE WHEN mv.id IN (SELECT id FROM tos_blocked) THEN 'duplicate_stem'
            WHEN mv.tos_topic IS NULL THEN 'not_in_tos'
            ELSE 'mapped' END
  FROM tos_move mv
 WHERE mv.known
ON CONFLICT (question_id) DO NOTHING;

INSERT INTO public.tos_alignment_backup (question_id, old_subject_id, old_topic, old_is_active, reason)
SELECT q.id, q.subject_id, q.topic, q.is_active, 'flagged'
  FROM public.questions q JOIN tos_flagged f ON f.id = q.id
ON CONFLICT (question_id) DO NOTHING;

UPDATE public.questions q
   SET subject_id = t.subject_id,
       topic      = t.title,
       tos_code   = t.code
  FROM tos_move mv
  JOIN public.tos_topics t ON t.code = mv.tos_topic
 WHERE q.id = mv.id
   AND mv.id NOT IN (SELECT id FROM tos_blocked);

-- 4. Deactivate (never delete) what does not belong in the TOS bank yet ---------
UPDATE public.questions q SET is_active = FALSE
  FROM tos_move mv
 WHERE q.id = mv.id AND mv.known AND (mv.tos_topic IS NULL OR mv.id IN (SELECT id FROM tos_blocked));

UPDATE public.questions q SET is_active = FALSE
  FROM tos_flagged f
 WHERE q.id = f.id AND q.id NOT IN (SELECT id FROM tos_done);
"""

MASTERY = """
-- 5. Merge each student's topic mastery into the TOS topic names ---------------
CREATE TABLE IF NOT EXISTS public.tos_alignment_mastery_backup (LIKE public.topic_mastery INCLUDING ALL);
ALTER TABLE public.tos_alignment_mastery_backup ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can read mastery backup" ON public.tos_alignment_mastery_backup;
CREATE POLICY "Admins can read mastery backup" ON public.tos_alignment_mastery_backup
  FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.tos_alignment_mastery_backup TO authenticated;

CREATE TEMP TABLE tos_mastery_src ON COMMIT DROP AS
SELECT tm.*, t.subject_id AS new_subject, t.title AS new_topic
  FROM public.topic_mastery tm
  JOIN tos_topic_map m
    ON m.old_subject = tm.subject_id AND lower(trim(m.old_topic)) = lower(trim(tm.topic))
  JOIN public.tos_topics t ON t.code = m.tos_topic
 WHERE NOT (tm.subject_id = t.subject_id AND tm.topic = t.title);

INSERT INTO public.tos_alignment_mastery_backup
       (id, user_id, subject_id, topic, p_known, attempts, correct, consecutive_correct,
        is_mastered, last_practiced, updated_at)
SELECT id, user_id, subject_id, topic, p_known, attempts, correct, consecutive_correct,
       is_mastered, last_practiced, updated_at
  FROM tos_mastery_src
ON CONFLICT DO NOTHING;

-- Several old topics can become one TOS topic: add up the attempts and take the
-- attempt-weighted mean of p(known).
CREATE TEMP TABLE tos_mastery_merged ON COMMIT DROP AS
SELECT user_id, new_subject, new_topic,
       SUM(attempts)::INT AS attempts,
       SUM(correct)::INT AS correct,
       SUM(p_known * GREATEST(attempts, 1)) / SUM(GREATEST(attempts, 1)) AS p_known,
       MAX(consecutive_correct)::INT AS consecutive_correct,
       MAX(last_practiced) AS last_practiced
  FROM tos_mastery_src
 GROUP BY user_id, new_subject, new_topic;

DELETE FROM public.topic_mastery tm USING tos_mastery_src s WHERE tm.id = s.id;

INSERT INTO public.topic_mastery
       (user_id, subject_id, topic, p_known, attempts, correct, consecutive_correct, is_mastered, last_practiced)
SELECT user_id, new_subject, new_topic, ROUND(p_known, 5), attempts, correct, consecutive_correct,
       FALSE, last_practiced
  FROM tos_mastery_merged
ON CONFLICT (user_id, subject_id, topic) DO UPDATE SET
  p_known = ROUND((public.topic_mastery.p_known * GREATEST(public.topic_mastery.attempts, 1)
                   + EXCLUDED.p_known * GREATEST(EXCLUDED.attempts, 1))
                  / (GREATEST(public.topic_mastery.attempts, 1) + GREATEST(EXCLUDED.attempts, 1)), 5),
  attempts = public.topic_mastery.attempts + EXCLUDED.attempts,
  correct = public.topic_mastery.correct + EXCLUDED.correct,
  consecutive_correct = GREATEST(public.topic_mastery.consecutive_correct, EXCLUDED.consecutive_correct),
  last_practiced = GREATEST(public.topic_mastery.last_practiced, EXCLUDED.last_practiced);

-- Same mastery rule as the app (MasteryService): p_known >= 0.90 after 4+ attempts.
UPDATE public.topic_mastery tm
   SET is_mastered = (tm.p_known >= 0.90 AND tm.attempts >= 4)
  FROM tos_mastery_merged g
 WHERE tm.user_id = g.user_id AND tm.subject_id = g.new_subject AND tm.topic = g.new_topic;
"""

COVERAGE = """
-- 6. Coverage of the TOS, for the Admin Panel ----------------------------------
-- One row per TOS topic and competency: TOS items, active questions, drafts.
CREATE OR REPLACE FUNCTION public.admin_tos_coverage()
RETURNS TABLE (code TEXT, subject_id TEXT, topic_code TEXT, level TEXT,
               tos_items INTEGER, active INTEGER, drafts INTEGER, sort INTEGER)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $coverage$
#variable_conflict use_column
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Only faculty can view TOS coverage' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT t.code, t.subject_id, t.code, 'topic'::TEXT, t.items,
         COUNT(q.id) FILTER (WHERE q.is_active)::INTEGER,
         COUNT(q.id) FILTER (WHERE NOT q.is_active)::INTEGER,
         t.sort * 1000
    FROM public.tos_topics t
    LEFT JOIN public.questions q
           ON q.tos_code = t.code OR q.tos_code LIKE t.code || '.%'
   GROUP BY t.code, t.subject_id, t.items, t.sort
  UNION ALL
  SELECT c.code, c.subject_id, c.topic_code, 'competency'::TEXT, c.items,
         COUNT(q.id) FILTER (WHERE q.is_active)::INTEGER,
         COUNT(q.id) FILTER (WHERE NOT q.is_active)::INTEGER,
         tt.sort * 1000 + c.sort
    FROM public.tos_competencies c
    JOIN public.tos_topics tt ON tt.code = c.topic_code
    LEFT JOIN public.questions q ON q.tos_code = c.code
   GROUP BY c.code, c.subject_id, c.topic_code, c.items, c.sort, tt.sort
   ORDER BY 8;
END;
$coverage$;

REVOKE ALL ON FUNCTION public.admin_tos_coverage() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tos_coverage() TO authenticated;
"""

UPLOADS = """
-- 7. A PDF upload can target one TOS competency ---------------------------------
DO $uploads$
BEGIN
  IF to_regclass('public.document_uploads') IS NOT NULL THEN
    ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS tos_code TEXT;
  END IF;
END
$uploads$;
"""

SUMMARY = """
-- Record what was done, and show it in the SQL editor's output.
DO $summary$
DECLARE
  n_mapped INT; n_moved INT; n_off INT; n_flagged INT; n_blocked INT; n_unknown INT; n_mastery INT;
BEGIN
  SELECT COUNT(*) INTO n_mapped FROM tos_move mv WHERE mv.tos_topic IS NOT NULL AND mv.id NOT IN (SELECT id FROM tos_blocked);
  SELECT COUNT(*) INTO n_moved FROM tos_move mv JOIN public.tos_topics t ON t.code = mv.tos_topic
   WHERE t.subject_id <> mv.old_subject AND mv.id NOT IN (SELECT id FROM tos_blocked);
  SELECT COUNT(*) INTO n_off FROM tos_move mv WHERE mv.known AND mv.tos_topic IS NULL;
  SELECT COUNT(*) INTO n_flagged FROM public.questions q JOIN tos_flagged f ON f.id = q.id
   WHERE q.id NOT IN (SELECT id FROM tos_done);
  SELECT COUNT(*) INTO n_blocked FROM tos_blocked;
  SELECT COUNT(*) INTO n_unknown FROM tos_move mv WHERE NOT mv.known;
  SELECT COUNT(*) INTO n_mastery FROM tos_mastery_src;
  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, details)
  VALUES (NULL, 'tos_alignment', 'questions', 'tos_2024', jsonb_build_object(
    'linked_to_tos_topic', n_mapped, 'moved_to_other_subject', n_moved,
    'deactivated_not_in_tos', n_off, 'deactivated_flagged', n_flagged,
    'deactivated_duplicate_stem', n_blocked, 'left_unlinked_unknown_topic', n_unknown,
    'mastery_rows_merged', n_mastery));
  RAISE NOTICE 'TOS alignment: % questions linked to a TOS topic (% moved to another subject); % deactivated (topic not in TOS), % deactivated (flagged), % deactivated (same stem in target subject); % left unlinked (topic not in the map); % mastery rows merged.',
    n_mapped, n_moved, n_off, n_flagged, n_blocked, n_unknown, n_mastery;
END
$summary$;
"""

ROLLBACK = """-- ================================================================
-- CrimiReview -- undo supabase_tos_alignment.sql
-- ================================================================
-- Generated by tools/tos/build_alignment.py. Restores the subject, topic and
-- active flag of every question the alignment changed, clears their tos_code,
-- and puts back each student's topic mastery rows as they were.
--
-- It does NOT remove the 600 TOS questions (supabase_tos_bank.sql) or the
-- TOS tables; to remove the TOS questions too, run first:
--   DELETE FROM public.questions WHERE template_id = 'tos_2024';
-- ================================================================

BEGIN;

UPDATE public.questions q
   SET subject_id = b.old_subject_id,
       topic      = b.old_topic,
       is_active  = b.old_is_active,
       tos_code   = NULL
  FROM public.tos_alignment_backup b
 WHERE q.id = b.question_id;

-- Mastery: drop the merged TOS-topic rows of the affected students, restore the old rows.
DELETE FROM public.topic_mastery tm
 USING public.tos_topics t
 WHERE tm.subject_id = t.subject_id AND tm.topic = t.title
   AND tm.user_id IN (SELECT DISTINCT user_id FROM public.tos_alignment_mastery_backup);

INSERT INTO public.topic_mastery
       (id, user_id, subject_id, topic, p_known, attempts, correct, consecutive_correct,
        is_mastered, last_practiced, updated_at)
SELECT id, user_id, subject_id, topic, p_known, attempts, correct, consecutive_correct,
       is_mastered, last_practiced, updated_at
  FROM public.tos_alignment_mastery_backup
ON CONFLICT (user_id, subject_id, topic) DO NOTHING;

DELETE FROM public.tos_alignment_backup;
DELETE FROM public.tos_alignment_mastery_backup;

INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, details)
VALUES (NULL, 'tos_alignment_rollback', 'questions', 'tos_2024', NULL);

COMMIT;
"""


def main():
    problems = check_map() + check_snapshot()
    if problems:
        print(f"\n{len(problems)} PROBLEM(S):")
        print("\n".join("- " + p for p in problems[:100]))
        sys.exit(1)
    for name, text in [("supabase_tos_alignment.sql", alignment_sql()),
                       ("supabase_tos_alignment_rollback.sql", ROLLBACK)]:
        with open(os.path.join(ROOT, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("Wrote", name)


if __name__ == "__main__":
    main()
