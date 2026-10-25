#!/usr/bin/env bash
# Counted checks of supabase_tos_alignment.sql, supabase_tos_bank.sql and the rollback (Table 21 of the manuscript).
# Needs a local PostgreSQL on port 55432 with a database "tosfresh": the bootstrap stand-in for Supabase, the schema,
# and the 759 imported questions, before any TOS file. Result on 2026-10-25: 25 of 25 checks passed.
set -e
export PGPASSWORD=postgres PGCLIENTENCODING=UTF8
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO=/c/crimireview
P="psql -h localhost -p 55432 -U postgres -X -q -v ON_ERROR_STOP=1"
$P -d postgres -c "DROP DATABASE IF EXISTS tosrun" -c "CREATE DATABASE tosrun TEMPLATE tosfresh"
DB="$P -d tosrun"
$DB -f "$HERE/00_before.sql"
$DB -f "$REPO/supabase_tos_alignment.sql" > /dev/null
$DB -f "$REPO/supabase_tos_bank.sql" > /dev/null
$DB -f "$HERE/10_after_first_run.sql"
$DB -f "$HERE/20_roles.sql"
$DB -f "$HERE/30_prepare_rerun.sql"
$DB -f "$REPO/supabase_tos_alignment.sql" > /dev/null
$DB -f "$REPO/supabase_tos_bank.sql" > /dev/null
$DB -f "$HERE/40_after_rerun.sql"
$DB -c "DELETE FROM public.questions WHERE template_id = 'tos_2024'"
$DB -f "$REPO/supabase_tos_alignment_rollback.sql" > /dev/null
$DB -f "$HERE/50_after_rollback.sql"
$P -d tosrun -c "SELECT n, name, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, detail FROM zz.chk ORDER BY n"
$P -d tosrun -At -c "SELECT COUNT(*) FILTER (WHERE ok) || ' of ' || COUNT(*) || ' checks passed' FROM zz.chk"
