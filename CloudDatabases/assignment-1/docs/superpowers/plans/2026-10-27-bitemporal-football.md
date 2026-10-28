# Bitemporal Football Database Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, runnable MariaDB 11.8 bitemporal database for the football-league domain, covering Assignment 1 core (8 pts) and both advanced tracks (2 pts), with an ER diagram, report, README and a full `docs.md` explainer.

**Architecture:** Four bitemporal version tables (`contract_version`, `coach_assignment_version`, `player_value_version`, `club_license_version`) hang off stable anchor tables (`club`, `player`, `coach`, `agent`, `season`). Every logical change gets one `tx_registry` row and is written as "close old belief + insert new belief". A one-row `query_params` table parameterises the Q1-Q8 views. A `story_event` table indexes the authored E1-E9 timeline for Q3 and the README story log. A1 adds procedures and guard triggers; A2 mirrors the contract history into a native MariaDB system-versioned + application-time table.

**Tech Stack:** MariaDB 11.8 (Docker), SQL, Python 3 (only to generate static seed SQL), Graphviz or Mermaid for the ER diagram, HTML-to-PDF for the report.

**Spec:** `Assignment1.pdf` (extracted text in this plan's context)

## Global Constraints

- Engine/version stated in README: MariaDB 11.8.x.
- Four period columns named `valid_from`, `valid_to`, `tx_from`, `tx_to`; both periods half-open.
- Open valid end `9999-12-31`; open transaction end `9999-12-31 23:59:59.999999`.
- Valid time is `DATE`; transaction time is `DATETIME(6)` in UTC.
- `CHECK (valid_from < valid_to)` and `CHECK (tx_from < tx_to)` on every version table.
- No physical `DELETE` and no update of business columns in the core timeline; only `tx_to` is updated.
- One logical change has one `tx_id` and one `tx_from`.
- At least 50 players, 6 clubs, 5 coaches, 60 current contract beliefs, 120 version rows.
- Every event type E1-E9 appears at least the required number of times and is tagged in `03_timeline.sql`.
- Q0 returns zero rows on final data; the test script breaks one invariant temporarily and rolls back.
- Q6 returns Rusu, Pop, Rusu for 2025-09-02 at three `known_at` dates.
- Scripts 01-05 run in order on an empty database without errors.

## Review Focus

- Half-open predicates: every overlap uses `from <= x AND x < to`, never `BETWEEN`.
- Sentinels: no `NULL` periods, no `TIMESTAMP` sentinel.
- I2 union coverage: license gaps must make overlapping contracts visible.
- I3: no club has two head coaches at the same valid instant.
- Re-runs: 01 drops and recreates the database; 03-06 are idempotent through 01.

---

### Task 1: Schema and local database

**Files:**
- Create: `01_schema.sql`
- Test: run against MariaDB 11.8 and inspect `SHOW TABLES`.

**Interfaces:**
- Produces: database `football_bitemporal`, tables `agent`, `club`, `player`, `coach`, `season`, `tx_registry`, `story_event`, `club_license_version`, `contract_version`, `coach_assignment_version`, `player_value_version`, `query_params`.

- [ ] Write `01_schema.sql` with anchors, version tables, constraints, indexes, `tx_registry`, `story_event`, `query_params`.
- [ ] Run `mariadb < 01_schema.sql`.
- [ ] Verify `SHOW TABLES` lists all 12 tables and `SHOW CREATE TABLE contract_version` contains both CHECKs and `ix_contract_asof`.

### Task 2: Initial load E1

**Files:**
- Create: `tools/gen_seed.py`
- Create: `02_data.sql` (generated, checked in)
- Test: row counts, one distinct `tx_id`, no overlaps.

**Interfaces:**
- Consumes: schema from Task 1.
- Produces: 6 clubs, 60 players, 6 coaches, 6 agents, 2 seasons, 55 initial contracts, 60 initial player values, 6 initial licenses, 5 initial coach assignments, all with `tx_id` of E1.

- [ ] Generate deterministic names/salaries/values with Python.
- [ ] Write `02_data.sql` with `@sim_now := '2025-07-01 09:00:00'`, E1 `tx_registry`, then anchors and version rows.
- [ ] Run 01+02; verify `SELECT COUNT(*)` and `COUNT(DISTINCT tx_id)` for E1 = 1.
- [ ] Verify no current-TT contract overlaps for the same player.

### Task 3: Timeline E2-E9

**Files:**
- Create: `03_timeline.sql`
- Test: event counts by `story_event.event_code`, I1/I2/I3 pre-check.

**Interfaces:**
- Consumes: E1 data.
- Produces: every E2-E9 event, plus `story_event` rows.

- [ ] Write coach story C1 (late entry + correction) exactly reproducing the five-row pattern.
- [ ] Write coach moves C2/C3/C4/C6 and C5 end.
- [ ] Write contract renewal/transfer/loan events, late free-agent signings, salary/value corrections, ends and restarts.
- [ ] Write C6 license suspension and restart, ending/restarting all C6 contracts.
- [ ] Write E8 retraction and two E9 multi-table transactions.
- [ ] Run 01-03; verify counts: E1>=1, E2>=3, E3>=5, E4>=3, E5>=5, E6>=3, E7>=3, E8>=1, E9>=2.
- [ ] Verify Q6 three-answer case manually with a temporary query.

### Task 4: Views Q0-Q8

**Files:**
- Create: `04_views.sql`
- Test: `SELECT * FROM each view` with parameter rows.

**Interfaces:**
- Consumes: data and `query_params`.
- Produces: `v_integrity_violations`, `v_q1_current_facts`, `v_q2_role_history`, `v_q3_events`, `v_q4_period_facts`, `v_q5_as_known`, `v_q6_bitemporal_point`, `v_q7_monthly_active`, `v_q8_gaps`.

- [ ] Write Q0 with I1/I2/I3 (and I4) union checks.
- [ ] Write Q1, Q2 with coalescing, Q3, Q4, Q5, Q6.
- [ ] Write Q7 recursive month calendar with zero months.
- [ ] Write Q8 with `LAG` over valid periods per player-club pair.
- [ ] Run all views with test parameters; Q0 returns zero.

### Task 5: Test script

**Files:**
- Create: `05_tests.sql`
- Test: full clean run of 01-05.

**Interfaces:**
- Consumes: everything above.
- Produces: reproducible output for the report.

- [ ] Add Q0 zero check, then temporary I1/I2/I3 violations each followed by rollback.
- [ ] Add Q1-Q8 calls with the exact story parameters.
- [ ] Add Q6 three known_at values; assert Rusu/Pop/Rusu.
- [ ] Run `mariadb < 01_schema.sql`, `02`, `03`, `04`, `05` in order; capture output.

### Task 6: Advanced A1

**Files:**
- Create: `06_advanced_a1.sql`
- Test: procedures, guard triggers, negative tests.

**Interfaces:**
- Consumes: core schema/data.
- Produces: `sp_assert_fact`, `sp_end_fact`, `sp_correct_fact`, `sp_retract_fact`, guard triggers on all four version tables, `a1_negative_results`.

- [ ] Write procedures with simulated clock fallback to `CURRENT_TIMESTAMP(6)`.
- [ ] Write BEFORE INSERT/UPDATE/DELETE triggers blocking direct writes, business-column updates, closed-row updates and deletes.
- [ ] Write `sp_a1_negative_tests` with exception handlers, run and show caught errors.
- [ ] Demonstrate the API on a new demo player; show tx_registry and version rows.

### Task 7: Advanced A2

**Files:**
- Create: `06_advanced_a2.sql`
- Test: native Q1/Q5/Q6 match core results.

**Interfaces:**
- Consumes: core `contract_version` / `coach_assignment_version`.
- Produces: `native_contract` (application-time period + `WITH SYSTEM VERSIONING`), loaded with explicit `ROW_START`/`ROW_END` via `system_versioning_insert_history=ON`.

- [ ] Create `native_contract` with `PERIOD FOR valid_time` and system versioning.
- [ ] Load all core contract versions with mapped sentinel (`2106-02-07 06:28:15.999999`).
- [ ] Write native Q1/Q5/Q6 queries using `FOR SYSTEM_TIME AS OF`.
- [ ] Assert row counts and values match core for the three Q6 known_at values.

### Task 8: ER diagram

**Files:**
- Create: `er_diagram.mmd` or `er_diagram.dot`
- Create: `er_diagram.pdf` / `er_diagram.png`

- [ ] Draw anchors and version tables separately; mark NT/VT/TT/bitemporal; crow's-foot cardinalities.
- [ ] Render to PDF/PNG and inspect.

### Task 9: Documentation and report

**Files:**
- Create: `README.md`
- Create: `docs.md`
- Create: `report.html` -> `report.pdf`

- [ ] README: engine/version, run commands, story log with >=10 events, volume checklist.
- [ ] docs.md: every concept, design decision, invariant, query explanation, A1/A2 explanation, live-demo script, troubleshooting.
- [ ] Report <=5 pages: domain, modeling, write protocol SQL, failed attempt, insights, EXPLAIN, Q outputs.
- [ ] Verify PDF page count <=5 and all sections present.

### Task 10: Final clean run

- [ ] Destroy and recreate container database; run 01-05 in order, then 06 files.
- [ ] Check every assignment checkbox.
- [ ] Commit to git.
