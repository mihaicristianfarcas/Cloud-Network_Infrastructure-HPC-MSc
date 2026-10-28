# Bitemporal Football Database — Concepts and Implementation Guide

This is the long-form companion to `README.md`. It explains the ideas behind the
assignment, why the schema looks the way it does, how every query works, and how
to demonstrate the result live. The short version is in the README; this document
is for understanding and defending the design.

The database is a fictional Romanian football league on MariaDB 11.8.9. It has
six clubs, sixty players, six coaches, two named seasons, and a written history
of transfers, loans, corrections, late entries and retractions.

The one sentence that motivates everything:

> A fact has a validity period in the real world, and the database has a period
> during which it believed that fact. Those are different clocks.

A normal table can answer “what is true now?” A bitemporal table can also answer
“what did we believe on 12 September 2025 about 2 September 2025?” The second
question is the whole assignment.

---

## 1. The two clocks

### 1.1 Valid time (VT)

Valid time is the time when a fact is true in the modelled world.

For a contract, VT answers:

- When did the player actually join the club?
- When did the player actually leave?
- Which coach was actually in charge on match day?

In this schema valid time is stored as two `DATE` columns:

```text
valid_from, valid_to        half-open: [valid_from, valid_to)
```

Example: Mihai Rusu was FC Nord's head coach from 1 July 2025 to 3 September
2025. That is a valid-time fact, regardless of when a clerk typed it.

### 1.2 Transaction time (TT)

Transaction time is the time when the database held a belief.

For the same contract, TT answers:

- When did the database start believing this version?
- When did it stop believing it, because it was corrected or retracted?

TT is stored as two `DATETIME(6)` columns:

```text
tx_from, tx_to              half-open: [tx_from, tx_to)
```

TT is not “when the event happened in the real world”. It is “when this row was
the current belief in the database”. If a clerk records on 10 September that Pop
took over on 1 September, the valid time starts on 1 September but the
transaction time starts on 10 September.

### 1.3 Bitemporal

A table is bitemporal when every row has both periods. To ask a question as of a
valid date and a transaction date, both conditions must hold:

```sql
WHERE valid_from <= @valid_at
  AND @valid_at  < valid_to
  AND tx_from    <= @known_at
  AND @known_at  < tx_to
```

This predicate appears in Q1, Q2 and Q6. It is the mechanical heart of the whole
project.

### 1.4 The three-answer example

The same valid date can have different correct answers at different transaction
dates. For “Who was FC Nord's head coach on 2 September 2025?”:

| Known at | Answer | Why |
|---|---|---|
| 2025-09-05 | Mihai Rusu | The late entry of Pop has not been recorded yet. |
| 2025-09-12 | Andrei Pop | Pop was recorded on 10 September as taking over on 1 September. |
| 2026-10-15 | Mihai Rusu | The handover was corrected to 3 September, so Rusu was still coach on 2 September. |

All three answers are correct. They are answers to different historical
questions. A single valid-time table cannot represent this, because it has only
one current version of the fact.

---

## 2. Periods, sentinels and types

### 2.1 Half-open intervals

Every period is half-open:

```text
[from, to)   means   from <= x < to
```

This has three practical advantages:

1. Adjacent periods do not overlap. `[1 Jul, 3 Sep)` and `[3 Sep, 9999)` share
   the boundary date but no instant.
2. Durations are simple subtraction: `to - from`.
3. The same predicate works for valid time and transaction time.

The SQL never uses `BETWEEN` for a period, because `BETWEEN` is inclusive on both
ends and would make adjacent facts overlap at the boundary.

### 2.2 Sentinels instead of NULL

Open-ended periods use sentinel values, not `NULL`:

| Period | Open end |
|---|---|
| Valid time | `9999-12-31` |
| Transaction time | `9999-12-31 23:59:59.999999` |

Why sentinels:

- The as-of predicate stays a simple range comparison. With `NULL`, every query
  would need `valid_to IS NULL OR ...`.
- Indexes can use the end column directly.
- A sentinel is a real value, so `CHECK (valid_from < valid_to)` still works.
- `NULL` has three-valued logic and special behaviour in unique indexes; a
  sentinel avoids those traps.

The transaction-time sentinel is the maximum `DATETIME(6)` value MariaDB can
store. That is also why the core schema does not use `TIMESTAMP`: `TIMESTAMP`
ends in 2038 and cannot hold `9999-12-31 23:59:59.999999`.

### 2.3 Date versus datetime

| Clock | Type | Reason |
|---|---|---|
| Valid time | `DATE` | Football facts are day-granular; no time-of-day or time-zone ambiguity. |
| Transaction time | `DATETIME(6)` UTC | Several changes can happen in one second; microseconds preserve order. |

All scripts set `time_zone = '+00:00'`. Transaction timestamps are therefore UTC
and reproducible.

### 2.4 Current belief

“Current” in this project means:

```sql
tx_to = '9999-12-31 23:59:59.999999'
```

It does **not** mean “valid today”. A current belief can have a finite valid
period, for example a contract that ended on 1 January 2026 but has not been
corrected since. This distinction matters in Q0, Q5, Q7 and Q8.

---

## 3. Schema

### 3.1 The thirteen tables

| Table | Kind | Purpose |
|---|---|---|
| `agent` | non-temporal anchor | Stable agent identity. |
| `club` | non-temporal anchor | Stable club identity. |
| `coach` | non-temporal anchor | Stable coach identity. |
| `player` | non-temporal anchor | Stable player identity, position and agent. |
| `season` | non-temporal reference | The named periods 2025/26 and 2026/27. |
| `calendar_month` | non-temporal helper | One row per month, so Q7 can show zero months. |
| `tx_registry` | transaction log | One row per logical change: when, who, why. |
| `story_event` | non-temporal audit index | Human-authored E1–E9 labels and old/new values. |
| `club_license_version` | bitemporal | A club's licence periods; temporal parent for I2. |
| `contract_version` | bitemporal | Player ↔ club registration, salary, shirt, type. |
| `coach_assignment_version` | bitemporal | Head-coach role history; I3 lives here. |
| `player_value_version` | bitemporal | Market-value history. |
| `query_params` | non-temporal helper | One-row parameter block for the views. |

The four version tables are the history. The anchors hold identity that does not
change. This “anchor + version” split is deliberate: a player's name should not
be copied into every contract row, and a club should not be duplicated when its
coach changes.

### 3.2 The four version tables

All four share the same period columns and a `tx_id` foreign key:

```text
version_id  primary key
...         business columns
valid_from  DATE
valid_to    DATE
tx_from     DATETIME(6)
tx_to       DATETIME(6)
tx_id       foreign key to tx_registry
```

| Table | Business columns | Why it exists |
|---|---|---|
| `contract_version` | player, club, shirt, salary, type | Main relationship fact; used by most queries. |
| `coach_assignment_version` | coach, club, role | Role holder that changes over time; I3. |
| `player_value_version` | player, market value | Changing numeric attribute. |
| `club_license_version` | club, league, status | Temporal parent; a contract must be inside a licence. |

Every table has:

- a primary key `version_id`;
- foreign keys to its anchors and to `tx_registry`;
- `CHECK (valid_from < valid_to)`;
- `CHECK (tx_from < tx_to)`;
- indexes that support as-of lookups.

`contract_version` also has as-of indexes on
`(player_id, tx_to, valid_from)` and `(club_id, tx_to, valid_from)`;
`coach_assignment_version` has `(club_id, tx_to, valid_from)`.

### 3.3 Why no unique key on the business key and period?

A bitemporal table intentionally contains several versions of the same business
fact. A unique key such as `(player_id, valid_from)` would reject the historical
copy that is needed for a correction. The invariants are therefore enforced
semantically:

- Q0 detects violations in the final data.
- The A1 procedures check the important cases before writing.
- The A1 guard triggers prevent bypassing the write protocol.

This is a deliberate trade-off: a database constraint would be stronger, but it
cannot express “no overlap among current transaction-time beliefs” in MariaDB
without a trigger or a generated column. The assignment asks for the invariant
checks; Q0 is the evidence.

### 3.4 Why a separate `tx_registry`?

Every logical change inserts one row into `tx_registry`:

```text
tx_id, tx_time, author, reason
```

All version rows written by that change share the same `tx_id` and `tx_time`.
This is what makes a multi-table change atomic in the story:

- E9 suspends a licence, ends ten contracts and changes ten values in one
  transaction.
- E9 later reinstates the licence, restarts ten contracts and updates ten values
  in one transaction.

Without the registry, the fact that those rows belong together would be lost.
The registry is append-only: rows are inserted, never updated or deleted.

### 3.5 Why `story_event`?

`story_event` is a human-authored index of the timeline. It stores the event code
(E1–E9), a business key, the valid date, old and new values, and a note. It is not
the source of truth: every event also exists as real version rows and a real
`tx_registry` row.

It exists because “late entry” versus “proactive entry” versus “correction” is a
statement about intent, not something that can always be inferred from
timestamps:

- E3 is recorded after the valid date (positive delay).
- E2 is recorded before the valid date (negative delay, a future-dated change).
- E4 can be recorded at any time and changes a value or a date.

Q3 reads `story_event` so the classification is exact and auditable. The version
rows remain the data; `story_event` is the narrative index. Q3 also derives a
label from the version rows alone and shows it next to the authored one, so the
two can be checked against each other (see Q3 below).

### 3.6 Volumes

| Item | Count |
|---|---:|
| Players | 60 |
| Clubs | 6 |
| Coaches | 6 |
| Initial contracts (E1) | 55 |
| Current contract beliefs | 78 |
| `contract_version` rows | 101 |
| `coach_assignment_version` rows | 19 |
| `player_value_version` rows | 89 |
| `club_license_version` rows | 9 |
| All version rows | 218 |
| `story_event` rows | 69 |

The assignment's minimums are 50 players, 5 coaches, 6 clubs, 60 current
relationship facts and 120 version rows; the implementation exceeds each.

---

## 4. The story: E1–E9

The timeline is a replay of a football league, not random rows. Each event has a
valid date (when it happened) and a transaction time (when it was recorded).

| Code | Meaning | Count | Example |
|---|---|---|---:|---|
| E1 | Initial load | 1 | 6 clubs, 60 players, 55 contracts under one `tx_id`. |
| E2 | Proactive / future-dated change | 14 | A renewal recorded months before it starts. |
| E3 | Late entry | 8 | Pop recorded on 10 September as starting on 1 September. |
| E4 | Correction | 4 | The handover is corrected from 1 September to 3 September. |
| E5 | End of a fact | 15 | A player leaves; the open contract gets a finite `valid_to`. |
| E6 | Restart after a gap | 15 | A player returns to the same club after a loan or absence. |
| E7 | Role-holder change | 6 | A club changes head coach. |
| E8 | Retraction | 2 | An erroneous P6/CS Port row is removed from belief with no replacement. |
| E9 | Multi-table logical change | 4 | A licence suspension ends ten contracts at once. |

The 69 `story_event` rows are summarised in the README story log; Q3 prints the
E2/E3/E4 subset, while the verification queries count every event code.

### 4.1 The five-row Rusu/Pop pattern

This is the smallest complete bitemporal story, and the one to show in a demo.

Initial load (E1), all under transaction time `2025-07-01 09:00`:

| Row | Coach | Valid period | Transaction period |
|---|---|---|---|
| A | Rusu | `[2025-07-01, 9999-12-31)` | `[2025-07-01 09:00, 2025-09-10 14:00)` |

On 10 September 2025 (E3), the clerk records that Pop took over on 1 September.
The database closes Rusu's belief in transaction time and inserts two beliefs:
Rusu until 1 September, and Pop from 1 September.

| Row | Coach | Valid period | Transaction period |
|---|---|---|---|
| A | Rusu | `[2025-07-01, 9999-12-31)` | `[2025-07-01 09:00, 2025-09-10 14:00)` |
| B | Rusu | `[2025-07-01, 2025-09-01)` | `[2025-09-10 14:00, 2025-09-15 11:00)` |
| C | Pop | `[2025-09-01, 9999-12-31)` | `[2025-09-10 14:00, 2025-09-15 11:00)` |

On 15 September (E4), an auditor corrects the handover to 3 September. Both
10-September beliefs are closed in transaction time, and the corrected pair is
inserted. Nothing is overwritten.

| Row | Coach | Valid period | Transaction period |
|---|---|---|---|
| A | Rusu | `[2025-07-01, 9999-12-31)` | `[2025-07-01 09:00, 2025-09-10 14:00)` |
| B | Rusu | `[2025-07-01, 2025-09-01)` | `[2025-09-10 14:00, 2025-09-15 11:00)` |
| C | Pop | `[2025-09-01, 9999-12-31)` | `[2025-09-10 14:00, 2025-09-15 11:00)` |
| D | Rusu | `[2025-07-01, 2025-09-03)` | `[2025-09-15 11:00, 9999-12-31 23:59:59.999999)` |
| E | Pop | `[2025-09-03, 9999-12-31)` | `[2025-09-15 11:00, 9999-12-31 23:59:59.999999)` |

Five rows, two coaches, one valid date, three different answers. This is exactly
what Q6 demonstrates.

### 4.2 Other important patterns

**E2 — proactive.** A change can be recorded before its valid date. For example,
P1's renewal starting 1 July 2026 is recorded on 18 January 2026. Its transaction
time is January, its valid time starts in July. There is nothing special to
enforce; the two clocks simply differ.

**E5 — end of a fact.** A player leaves. The old belief is closed in transaction
time, and a finite replacement is inserted with the same business data but
`valid_to` set to the end date. The row is not deleted. This preserves the
history “the contract existed until 1 January”.

**E6 — restart after a gap.** A player returns to the same club after a loan or a
short absence. This is an insert with a new `valid_from` after the previous
`valid_to`; Q8 detects the gap. There is no overlap, so I1 stays true.

**E8 — retraction.** The P6/CS Port row was never true. The database closes its
transaction interval with no replacement row. This is different from E5:

- E5 says “the fact was true, and then it ended”.
- E8 says “the belief was wrong; it was never true”.

The retracted row still exists, but only inside its old transaction interval. Q5
on 11 February 2026 can see it because it was believed then; Q5 after 12 February
cannot.

**E9 — one change, many tables.** A licence suspension ends ten contracts. All
eleven version writes share one `tx_registry` row. If the change were split into
eleven transactions, a query as of the middle of the change would see an
inconsistent state (a suspended licence with active contracts). One logical
change must have one timestamp.

### 4.3 Why the story is authored

The assignment asks for specific event types, and a random data generator would
not reliably produce late entries, corrections, retractions and multi-table
changes. The timeline is written as a sequence of small SQL blocks, each with:

```sql
SET @sim_now := '...';
INSERT INTO tx_registry ...;
SET @tx := LAST_INSERT_ID();
-- close old beliefs
-- insert new beliefs with @sim_now, @tx
```

`@sim_now` is the simulated clock. It makes the replay deterministic: the data
does not depend on the wall-clock time at which the script runs. A1 falls back to
`CURRENT_TIMESTAMP(6)` when the variable is not set, so the same procedures can
be used interactively.

---

## 5. Invariants and Q0

### 5.1 The four invariants

| Invariant | Meaning |
|---|---|
| I1 | Current transaction-time beliefs for one business key must not overlap in valid time. |
| I2 | A current contract's whole valid period must be covered by the union of its club's current licence periods. |
| I3 | At most one head coach per club at any valid instant. |
| I4 | Transaction intervals are well formed, no transaction is in the future, and closed history is immutable. |

I1 applies to contracts, values and licences: no two current beliefs for the same
business key may overlap. The coach table has the analogous rule I3, because the
business rule is “one head coach” rather than generic non-overlap. Q0 checks all
four tables.

I2 is the subtle one. A simple containment check against one licence row is not
enough, because a club's licence history can be a union of periods with a gap. FC
Sud is the example: licensed from 1 July 2025, suspended from 1 January 2026,
re-licensed from 1 July 2026. A contract that spans the suspension is invalid
even though it starts after the first licence start and ends before the last
licence end.

Q0 therefore checks:

- there is at least one current licence for the club;
- the contract does not start before the first licence;
- the contract does not end after the last licence;
- the contract does not overlap any gap between consecutive licences.

The gap subquery is what makes this a union coverage check rather than a single
period check.

I3 uses the same overlap pattern as I1, but the business key is `club_id` and the
role is `Head coach`. The schema currently has one role title, so “one head coach
per club” is exactly “no overlapping coach assignments per club”.

I4 is split between Q0 and the A1 triggers:

- Q0 checks well-formed intervals and future transaction times.
- The A1 triggers make closed rows immutable and block direct writes.

### 5.2 The overlap predicate

For two half-open intervals `[a_from, a_to)` and `[b_from, b_to)`, they overlap
exactly when:

```sql
a_from < b_to AND b_from < a_to
```

The equal-boundary case is not an overlap. This is used in I1 and I3. The Q0 view
joins the table to itself with `a.version_id < b.version_id` so each overlapping
pair is reported once.

### 5.3 Q0 output

On the final data:

```text
Q0 FINAL: 0 violations
```

`05_tests.sql` then deliberately breaks each invariant in its own transaction:

1. I1: insert a second current contract for player 1 at CS Port.
2. I2: insert a contract for player 51 at FC Sud during the suspension.
3. I3: insert a second FC Nord head coach.

Each transaction shows the violation row and then rolls back. The final check is
again zero. This proves the checks are live, not merely empty because the data is
too small to trigger them.

---

## 6. Queries Q1–Q8

All views read their parameters from the one-row `query_params` table, because a
MariaDB view cannot take arguments. Change the row and re-select the view.

Default parameters:

```text
valid_at      = 2026-10-15
known_at      = 2026-10-15 23:59:59.999999
period_start  = 2025-07-01
period_end    = 2026-07-01
subject_id    = 1
```

### Q1 — current facts for one player

Question: “Which contract did player 1 have on 15 October 2026, as known on that
day?”

```sql
SELECT ...
FROM query_params p
JOIN contract_version cv
  ON cv.player_id = p.subject_id
WHERE cv.valid_from <= p.valid_at
  AND p.valid_at  < cv.valid_to
  AND cv.tx_from  <= p.known_at
  AND p.known_at  < cv.tx_to;
```

The result is Alexandru Albu at FC Nord, salary 120,000, permanent, valid from
1 July 2026. This is a point query on both clocks: the row must be valid on the
date and believed on the transaction date.

### Q2 — role history, coalesced

Question: “Show FC Nord's head-coach history as known today, with tenure.”

The view:

1. selects the current coach rows for the club;
2. orders them per coach;
3. marks a new group when a row does not start exactly where the previous row
   ended;
4. sums the group markers to create a group id;
5. groups by coach and group, taking `MIN(valid_from)` and `MAX(valid_to)`.

This is the “gaps and islands” pattern. It merges adjacent valid periods for the
same coach, so a correction that split a row into two pieces does not appear as
two tenures. `05_tests.sql` proves it with a rolled-back split: Pop's row becomes
[2025-09-03, 2026-07-01) + [2026-07-01, open), the raw rows show three periods,
and Q2 still shows one Pop tenure.

Result:

| Coach | Valid from | Valid to | Tenure |
|---|---|---|---:|
| Mihai Rusu | 2025-07-01 | 2025-09-03 | 64 days |
| Andrei Pop | 2025-09-03 | open | 407 days as of 2026-10-15 |

Tenure uses `LEAST(valid_to, known_at)` so an open-ended tenure is measured up to
the as-of date, not to the year 9999.

### Q3 — late, proactive and corrected events

Question: “Which changes were late, which were proactive, and which were
corrections, with the delay and old/new values?”

Q3 reads `story_event` and joins `tx_registry` for the transaction time:

```sql
DATEDIFF(tr.tx_time, se.valid_date) AS delay_days
```

- Positive delay: the change was recorded after it took effect (late entry).
- Negative delay: the change was recorded before it takes effect (proactive).
- Any sign: a correction can be recorded at any time.

The result is 14 proactive, 8 late and 4 corrections. Examples:

| Event | Valid date | Recorded | Delay | Old → new |
|---|---|---|---:|---|
| E3 P56 | 2025-07-10 | 2025-07-25 | 15 days | — → FC Sud, 150,000 |
| E4 P7 salary | 2025-07-01 | 2025-11-10 | 132 days | 114,500 → 150,000 |
| E2 P1 renewal | 2026-07-01 | 2026-01-18 | −164 days | FC Nord 93,500 → FC Nord 120,000 |

The negative delay is not an error. It is the signature of a future-dated change.

`derived_label` classifies the same events without looking at the authored code.
For each version row written by the event's transaction:

1. If the same key had a belief with the same `valid_from` that this transaction
   closed, the fact was re-stated. When only an open `valid_to` became finite it
   is an E5 end (not part of Q3); any other change is a **correction**.
2. If an overlapping belief for the key was closed and no row of the transaction
   keeps its `valid_from`, the date moved: also a **correction** (Pop's handover
   moving from 1 to 3 September).
3. Otherwise the row is a new fact: **proactive** if `valid_from` is after the
   recording date, **late entry** if it was recorded at least 7 days after.

All 26 rows agree; `05_tests.sql` prints `Q3 LABEL MISMATCHES = 0`. Late versus
correction is still partly intent (a late value change and a corrected value can
leave the same rows), which is why the authored label stays the primary one.

### Q4 — overlaps versus containment

Question: “Which contract facts overlap the 2025/26 season, and which are
contained throughout the season?”

Two predicates:

```sql
-- at some point
valid_from < period_end AND period_start < valid_to

-- throughout
valid_from <= period_start AND period_end <= valid_to
```

The difference is the boundary treatment:

- A contract `[2025-07-01, 2026-07-01)` starts at the season start and ends after
  the season end, so it is contained throughout.
- A contract `[2025-07-01, 2026-01-01)` starts at the season start but ends
  before the season end, so it overlaps but is not contained.
- A contract ending exactly at `period_end` is contained, because the season
  period is half-open and `period_end` itself is outside it.

Result: 18 facts overlap but are not contained; 44 are contained throughout.

### Q5 — the whole table as believed at a transaction time

Question: “What did the contract table look like on 11 February 2026, regardless
of valid time?”

The only filter is:

```sql
tx_from <= known_at AND known_at < tx_to
```

Valid time is not filtered. The view returns every version row that was believed
at that instant, including contracts that had already ended in the real world.
This is the “database snapshot” query.

At `2026-02-11 12:00`, the result has 63 rows and includes the erroneous P6/CS
Port row:

```text
tx_from = 2026-02-10 10:00
tx_to   = 2026-02-12 09:00
```

It was believed on 11 February and retracted on 12 February. Q5 is the query that
makes E8 visible. This is also the strongest test for the A2 native comparison.

### Q6 — the bitemporal point query

Question: “Who was FC Nord's head coach on 2 September 2025, as known on a given
transaction date?”

```sql
SELECT ...
FROM query_params p
JOIN coach_assignment_version ca
  ON ca.club_id = p.subject_id
WHERE ca.valid_from <= p.valid_at
  AND p.valid_at  < ca.valid_to
  AND ca.tx_from  <= p.known_at
  AND p.known_at  < ca.tx_to;
```

The result for the three transaction dates:

| Known at | Coach | Valid period | Transaction period |
|---|---|---|---|
| 2025-09-05 | Mihai Rusu | `[2025-07-01, open)` | `[2025-07-01, 2025-09-10)` |
| 2025-09-12 | Andrei Pop | `[2025-09-01, open)` | `[2025-09-10, 2025-09-15)` |
| 2026-10-15 | Mihai Rusu | `[2025-07-01, 2025-09-03)` | `[2025-09-15, open)` |

This is the query the assignment cares about most. It shows that the database is
not “wrong” at the earlier dates: it is answering with the beliefs it had.

### Q7 — monthly active contracts

Question: “How many contracts were active at each club in each month of 2025/26?”

The view cross-joins `calendar_month` with `club`, then left-joins current
contracts that overlap the month:

```sql
cv.tx_to = open
AND cv.valid_from < month_start + 1 month
AND month_start < cv.valid_to
```

The `calendar_month` cross join is essential: without it, a month with no active
contract would simply be absent. The left join plus `COUNT(cv.version_id)` turns
that absence into `0`.

FC Sud:

| Months | Active contracts |
|---|---:|
| July 2025 | 7 |
| August–December 2025 | 10 each |
| January–June 2026 | 0 each |

The six zero months are the licence suspension. They are a feature, not a missing
data problem: the club had no active contracts because it was not licensed.

### Q8 — gaps between periods

Question: “Where did a player leave a club and later return, and how long was the
gap?”

`LAG` looks at the previous valid period for the same player–club pair:

```sql
LAG(valid_from) OVER (PARTITION BY player_id, club_id ORDER BY valid_from)
LAG(valid_to)   OVER (PARTITION BY player_id, club_id ORDER BY valid_from)
```

A gap exists when `valid_from > previous_to`. The view reports the previous end,
the next start, and `DATEDIFF(next_from, previous_to)`.

Result: 15 gaps. The largest:

| Player | Club | Gap |
|---|---|---:|
| Catalin Cernat | Universitatea Est | 334 days |
| Octavian Cretu | CS Port | 212 days |
| Ten FC Sud players | FC Sud | 181 days each |
| Eduard Neagu | FC Nord | 150 days |
| Iulian Toma | CS Port | 137 days |

The ten FC Sud 181-day gaps are exactly the licence suspension from 1 January to
1 July 2026. Q8 is the query that turns “the club was suspended” into a concrete
consequence for each player.

---

## 7. Writing history correctly

### 7.1 The universal pattern

Every change follows the same shape:

1. Record a transaction row in `tx_registry`.
2. Use its `tx_id` and `tx_time`.
3. Close the old current belief(s) in transaction time:
   `UPDATE ... SET tx_to = @sim_now WHERE tx_to = sentinel`.
4. If the fact changes in valid time, insert a replacement row with the same
   `tx_id`/`tx_from`.
5. If the fact was never true, insert no replacement (retraction).
6. If the fact merely ends, insert a replacement with a finite `valid_to`.
7. Never delete a version row.

The important rule is: **close and insert, never overwrite**. The old row is the
history; the new row is the new belief.

### 7.2 E3 — late entry

Pop took over on 1 September, recorded on 10 September.

```sql
SET @sim_now := '2025-09-10 14:00:00';
-- close Rusu's current belief in TT
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 1 AND club_id = 1
  AND tx_to = @SENT_TS;

-- Rusu now ends on 1 September in VT
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (1, 1, 'Head coach', '2025-07-01', '2025-09-01',
        @sim_now, @SENT_TS, @tx);

-- Pop starts on 1 September in VT, but is believed from 10 September
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (2, 1, 'Head coach', '2025-09-01', @SENT_DATE,
        @sim_now, @SENT_TS, @tx);
```

The same transaction closes the old row and inserts both replacements. The
`tx_to` of the old row equals the `tx_from` of the new rows.

### 7.3 E4 — correction

The handover is corrected from 1 September to 3 September.

```sql
SET @sim_now := '2025-09-15 11:00:00';
-- close both beliefs written on 10 September
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE club_id = 1 AND tx_to = @SENT_TS;

-- insert the corrected pair
INSERT INTO coach_assignment_version (...) VALUES
  (1, 1, 'Head coach', '2025-07-01', '2025-09-03',
   @sim_now, @SENT_TS, @tx),
  (2, 1, 'Head coach', '2025-09-03', @SENT_DATE,
   @sim_now, @SENT_TS, @tx);
```

The correction does not modify the old rows' business values or valid periods. It
closes their transaction interval and adds a new interpretation. This is why the
15 September answer can differ from the 12 September answer without destroying
the 12 September answer.

### 7.4 E5 — end of a fact

A contract ends, but was true until then.

```sql
-- close the current belief in TT
UPDATE contract_version SET tx_to = @sim_now
WHERE player_id = 6 AND club_id = 1
  AND tx_to = @SENT_TS;

-- insert the same fact with a finite valid_to
INSERT INTO contract_version (...)
VALUES (6, 1, ..., '2026-01-01', @sim_now, @SENT_TS, @tx);
```

The new row says “this contract existed until 1 January 2026”; the old row says
“the database believed the open-ended version until the change”. Both are true
statements about different clocks.

### 7.5 E8 — retraction

The P6/CS Port row was never true.

```sql
UPDATE contract_version SET tx_to = @sim_now
WHERE player_id = 6 AND club_id = 2
  AND tx_from = '2026-02-10 10:00:00'
  AND tx_to = @SENT_TS;
-- no INSERT
```

There is no replacement because there is no true fact. The retracted row remains
inside its old transaction interval. A query `AS OF` before the retraction sees
it; a query after the retraction does not.

### 7.6 E9 — multi-table atomicity

A licence suspension plus ten contract endings is one logical event. The later
re-licensing also restarts ten contracts and updates ten values. In both cases all
rows use the same `@tx` and `@sim_now`. The `tx_registry` row is the anchor that
makes the set identifiable later. Without it, an as-of query in the middle of the
change could see a half-applied state.

---

## 8. Advanced A1 — the database manages transaction time

A1 turns the manual E3/E4/E5/E8 protocol into four stored procedures and twelve
guard triggers.

### 8.1 The four procedures

| Procedure | Semantics | Transaction-time effect |
|---|---|---|
| `sp_assert_fact` | Insert a new open-ended contract after checking I1 and I2. | New open TT row. |
| `sp_end_fact` | End an open contract at a valid date. | Close old TT row; insert finite replacement. |
| `sp_correct_fact` | Correct the salary of a current contract. | Close old TT row; insert corrected replacement with the same VT. |
| `sp_retract_fact` | Remove a belief that was never true. | Close TT only; no replacement. |

All four:

- take `v_time = IFNULL(@sim_now, CURRENT_TIMESTAMP(6))`;
- insert one `tx_registry` row;
- use the same timestamp and `tx_id` for every row they write;
- set `@a1_internal = 1` around their own writes, and clear it in an exception
  handler.

`sp_assert_fact` checks two things before writing:

1. the player has no current contract that overlaps the new valid period (I1);
2. the club has an open-ended full licence that covers the new start (I2).

It only creates open-ended contracts. That is a deliberate simplification: the
procedure is a write API for the common “new registration” case, while
`sp_end_fact` handles the finite end.

### 8.2 The twelve guard triggers

There are three triggers on each of the four version tables:

| Trigger | Rule |
|---|---|
| `BEFORE INSERT` | Only the API may insert. |
| `BEFORE UPDATE` | Only `tx_to` may change; the row must still be open; the API must be active. |
| `BEFORE DELETE` | Physical deletes are always rejected. |

The update guard compares every business column, `tx_from`, and `tx_id` against
`OLD`, so a direct UPDATE cannot silently rewrite history. It also rejects an
update of an already-closed row.

The session flag `@a1_internal` is a guardrail, not a security boundary. A user
with enough privileges can set it. In production, the same design would use a
dedicated role and `REVOKE INSERT/UPDATE/DELETE` on the version tables, with the
procedures owned by a privileged definer. The flag is enough for this assignment
because it demonstrates where the enforcement lives.

### 8.3 Why not put the whole protocol in a trigger?

The first attempt used an `AFTER UPDATE` trigger to close the old row and insert
the new one. MariaDB rejected it:

```text
ERROR 1442 (HY000): Can't update table '...' in stored function/trigger because
it is already used by statement which invoked this stored function/trigger.
```

A trigger cannot modify the table that fired it. The working design is:

- **procedures** perform the close + insert sequence;
- **triggers** only guard against bypassing the procedures.

This is also the assignment's hint, but the error makes the reason concrete.

### 8.4 Negative tests

`06_advanced_a1.sql` records six forbidden operations in `a1_negative_results`:

| Attempt | Expected result |
|---|---|
| Direct `INSERT` | Rejected by `trg_contract_guard_bi`. |
| Direct update of `salary_eur` | Rejected by `trg_contract_guard_bu`. |
| Direct update of `tx_from` | Rejected. |
| Direct update of `tx_to` | Rejected. |
| Update of a closed row | Rejected because closed rows are immutable. |
| Physical `DELETE` | Rejected by `trg_contract_guard_bd`. |

The tests catch the error text with a `CONTINUE HANDLER`, roll back, and store
`REJECTED` or `NOT REJECTED`. The script still exits successfully because the
errors are evidence, not script failures.

The positive demo uses player 6, who has no current contract:

```sql
CALL sp_assert_fact(6, 1, 30, 90000.00, 'permanent', '2026-07-01');
CALL sp_correct_fact(6, 1, 95000.00);
CALL sp_retract_fact(6, 1);
CALL sp_assert_fact(6, 1, 30, 90000.00, 'permanent', '2026-07-01');
CALL sp_end_fact(6, 1, '2026-12-31');
```

It shows the version rows and the five `tx_registry` rows, then rolls the whole
demo back. The final check is `demo_rows_left = 0` and `violations = 0`.

**Important:** after A1 is installed, do not run `02_data.sql` or
`03_timeline.sql` directly. The guard triggers will correctly reject their raw
inserts. Re-run `01`–`05` first.

---

## 9. Advanced A2 — native MariaDB temporal tables

A2 answers the question: “What would the engine do for us if we used its own
temporal features?”

### 9.1 Native tables

Two tables mirror the parts needed for Q1, Q5 and Q6:

```sql
CREATE TABLE native_contract (
    ...
    valid_from DATE NOT NULL,
    valid_to   DATE NOT NULL,
    row_start  TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
    row_end    TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
    PERIOD FOR valid_time (valid_from, valid_to),
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    PRIMARY KEY (version_id)
) ENGINE=InnoDB WITH SYSTEM VERSIONING;
```

- `PERIOD FOR valid_time` is application time (what this project calls valid
  time).
- `WITH SYSTEM VERSIONING` adds the engine-managed transaction time in
  `row_start`/`row_end`.
- MariaDB keeps the history rows automatically when the table is updated.

`native_coach_assignment` is the same pattern for the coach role.

### 9.2 Loading backdated history

A normal `INSERT` into a system-versioned table stamps the row with “now”, which
would destroy the authored transaction history. The script therefore uses:

```sql
SET SESSION system_versioning_insert_history = ON;
```

and inserts both `row_start` and `row_end` explicitly. This is the special
loading mode for historical data, not normal DML.

MariaDB's open transaction-time end is the maximum `TIMESTAMP` value:

```text
2106-02-07 06:28:15.999999
```

The loader maps the core `9999-12-31 23:59:59.999999` sentinel onto that value,
and the native views map it back when they display `tx_to`. This is a concrete
engine difference: the core schema chooses its own readable sentinel, while the
native engine chooses a physical maximum.

### 9.3 Native as-of views

The native views use `FOR SYSTEM_TIME AS OF`:

```sql
SELECT ...
FROM native_coach_assignment
     FOR SYSTEM_TIME AS OF TIMESTAMP'2025-09-12 23:59:59.999999' AS ca
WHERE ca.club_id = 1
  AND ca.valid_from <= '2025-09-02'
  AND '2025-09-02' < ca.valid_to;
```

MariaDB requires the as-of argument to be a constant. It rejects a subquery:

```text
ERROR 1064 (42000): You have an error in your SQL syntax ...
```

and it rejects a view variable:

```text
ERROR 1351 (HY000): View's SELECT contains a variable or parameter
```

The solution is five small views with literal timestamps:

- `v_native_q1` at `2026-10-15`;
- `v_native_q5` at `2026-02-11 12:00`;
- `v_native_q6_20250905`, `..._20250912`, `..._20261015`.

This is less flexible than the core parameter table, but it makes the three Q6
answers explicit and easy to compare.

### 9.4 Comparison with the core views

The script compares each native view with the core view in both directions using
`EXCEPT`:

```sql
SELECT COUNT(*) FROM (
  SELECT ... FROM v_q6_bitemporal_point
  EXCEPT
  SELECT ... FROM v_native_q6_20250912
) d;
```

Every difference count is zero. The native volume check is also equal:

```text
native_contract_rows = 101, core_contract_rows = 101
native_coach_rows    = 19,  core_coach_rows    = 19
```

This proves the native engine can reproduce the same answers when the history is
loaded correctly. It does not replace the core design: the native tables are a
read-only demonstration, and the core schema still owns the write protocol and
the I1–I3 checks.

### 9.5 What the native engine does and does not enforce

Native system versioning gives:

- automatic transaction-time stamping for normal DML;
- an immutable history table;
- `FOR SYSTEM_TIME AS OF` queries.

It does not give:

- I1 non-overlap for application-time periods;
- I2 union coverage against a temporal parent;
- I3 one role holder per club;
- a way to inject authored historical transactions without the special load
  mode.

Those remain application-level invariants in both designs.

---

## 10. Engine comparison

The report compares the design with the temporal features of other engines.

| Engine | Application time | Transaction time | What it would still not enforce |
|---|---|---|---|
| MariaDB 11.8 (core) | Explicit `valid_from`/`valid_to`. | Explicit `tx_from`/`tx_to`. | Everything is explicit; Q0 + A1 enforce. |
| MariaDB 11.8 (A2 native) | `PERIOD FOR valid_time`. | `WITH SYSTEM VERSIONING`, `row_start`/`row_end`. | I1, I2, I3; backdated load is special. |
| Oracle 23ai Free | `PERIOD FOR` / `AS OF PERIOD FOR`. | Flashback Data Archive, `AS OF TIMESTAMP`, `VERSIONS BETWEEN`. | Non-overlap, union coverage, one-role constraints. |
| SQL Server 2022 | No native valid-time period. | System-versioned temporal tables, `SysStartTime`/`SysEndTime`. | I1, I2, I3; valid time must be modelled manually. |
| PostgreSQL 18/19 | Range types, `WITHOUT OVERLAPS`, `PERIOD` foreign keys, `FOR PORTION OF`. | Still triggers or an extension. | Union coverage with gaps; transaction time is not native. |

The key insight: no mainstream engine gives all four invariants for free. Native
temporal features solve the mechanical timestamping and as-of query, but the
business rules remain the designer's job.

---

## 11. Performance and EXPLAIN

Q6 filters on:

```sql
ca.club_id = 1
AND ca.valid_from <= '2025-09-02'
AND '2025-09-02' < ca.valid_to
AND ca.tx_from <= known_at
AND known_at < ca.tx_to
```

The index:

```sql
KEY ix_coach_asof (club_id, tx_to, valid_from)
```

supports the club filter and the transaction-time range. The plan with the index:

| Table | Type | Key | Rows | Extra |
|---|---|---|---|---|
| `ca` | `range` | `ix_coach_asof` | 4 | Using index condition; Using where |

Without the index (using `IGNORE INDEX (ix_coach_asof)`):

| Table | Type | Key | Rows | Extra |
|---|---|---|---|---|
| `ca` | `ALL` | `NULL` | 19 | Using where |

The dataset is tiny, so the absolute difference is small. The point is the access
path: a range scan on a few rows versus a full table scan. On a real league with
thousands of historical coach rows, the index is the difference between constant
and linear work.

The index cannot be dropped directly because it also supports the foreign key on
`club_id` (error 1553). `IGNORE INDEX` gives the without-index plan while keeping
the schema valid.

---

## 12. Failed attempts and what they taught

### 12.1 Trigger 1442

Trying to close and insert from the same trigger:

```text
ERROR 1442 (HY000): Can't update table 'coach_assignment_version' in stored
function/trigger because it is already used by statement which invoked this
stored function/trigger.
```

Lesson: triggers are guards, not the write protocol. The close + insert belongs in
a procedure.

### 12.2 Native AS OF with a subquery

```sql
FOR SYSTEM_TIME AS OF (SELECT known_at FROM query_params)
```

MariaDB rejects it with a syntax error (`ERROR 1064`). The as-of argument must be
a constant.

### 12.3 Native AS OF with a variable in a view

```sql
FOR SYSTEM_TIME AS OF @native_known_at
```

Rejected with:

```text
ERROR 1351 (HY000): View's SELECT contains a variable or parameter
```

Lesson: native as-of views need literal timestamps. Five small views are the
simplest correct solution.

### 12.4 Dropping the as-of index

```sql
DROP INDEX ix_coach_asof ON coach_assignment_version;
```

fails with error 1553 because the index supports the `club_id` foreign key. The
EXPLAIN comparison uses `IGNORE INDEX` instead.

### 12.5 The 9999 sentinel versus TIMESTAMP

`TIMESTAMP` cannot hold `9999-12-31 23:59:59.999999`; its range ends in 2038. This
is why the core schema uses `DATETIME(6)` for transaction time. The A2 native
table must use `TIMESTAMP(6)` because MariaDB's system versioning requires it, so
the loader translates between the two sentinels.

---

## 13. Live demo script

A ten-minute demonstration that tells the whole story.

### Step 1 — start the engine and run the core

```bash
docker run -d --name bitemporal-mariadb \
  -e MARIADB_ROOT_PASSWORD=root \
  -p 3307:3306 \
  mariadb:11.8

for f in 01_schema.sql 02_data.sql 03_timeline.sql 04_views.sql 05_tests.sql; do
  docker exec -i bitemporal-mariadb mariadb -uroot -proot < "$f" || exit 1
done
```

Narration: “The five scripts create the schema, load the initial world, replay the
story, create the views, and run the checks.”

### Step 2 — show zero violations

```bash
docker exec -it bitemporal-mariadb mariadb -uroot -proot football_bitemporal
```

```sql
SELECT COUNT(*) AS violations FROM v_integrity_violations;  -- 0
```

Narration: “Q0 is the invariant dashboard. It is empty because the story is
consistent.”

### Step 3 — show the bitemporal answer

```sql
UPDATE query_params
SET valid_at = '2025-09-02',
    known_at = '2025-09-05 23:59:59.999999',
    subject_id = 1;
SELECT coach_name FROM v_q6_bitemporal_point;

UPDATE query_params SET known_at = '2025-09-12 23:59:59.999999';
SELECT coach_name FROM v_q6_bitemporal_point;

UPDATE query_params SET known_at = '2026-10-15 23:59:59.999999';
SELECT coach_name FROM v_q6_bitemporal_point;
```

Expected: `Rusu`, `Pop`, `Rusu`.

Narration: “Same valid date, three transaction dates, three correct answers. The
database did not change its mind by magic; it recorded three beliefs.”

### Step 4 — show the retraction

```sql
UPDATE query_params SET known_at = '2026-02-11 12:00:00';
SELECT player_name, club_name, valid_from, valid_to, tx_from, tx_to
FROM v_q5_as_known
WHERE player_id = 6;

UPDATE query_params SET known_at = '2026-02-12 09:00:00';
SELECT player_name, club_name, valid_from, valid_to, tx_from, tx_to
FROM v_q5_as_known
WHERE player_id = 6;
```

Expected: the erroneous CS Port row is present at 11 February and absent after the
retraction. The row still exists in history; it is simply not believed after
12 February.

### Step 5 — show the gaps

```sql
UPDATE query_params
SET period_start = '2025-07-01', period_end = '2026-07-01';
SELECT player_name, club_name, previous_to, next_from, gap_days
FROM v_q8_gaps
ORDER BY gap_days DESC
LIMIT 5;
```

Expected: Cernat 334 days, Cretu 212 days, FC Sud players 181 days.

Narration: “A suspension is not an abstract licence row. It becomes a 181-day gap
for ten players.”

### Step 6 — install A1 and show the guards

```bash
docker exec -i bitemporal-mariadb mariadb -uroot -proot < 06_advanced_a1.sql
```

```sql
SELECT test_name, outcome, error_text FROM a1_negative_results ORDER BY test_id;
```

Expected: six `REJECTED` rows.

Narration: “After A1, the database owns transaction time. Direct writes are
blocked; the procedures are the only supported path.”

### Step 7 — install A2 and compare

```bash
docker exec -i bitemporal-mariadb mariadb -uroot -proot < 06_advanced_a2.sql
```

Look for:

```text
Q1 DIFF core -> native: 0
Q5 DIFF core -> native: 0
Q6 DIFF 2025-09-12 core -> native: 0
A2 NATIVE VOLUME: 101 / 101 / 19 / 19
```

Narration: “The native MariaDB temporal tables reproduce the core answers exactly,
including the retracted row at the historical transaction time.”

### Step 8 — explain the trade-off

Close with:

- The core schema is explicit and portable; it can represent backdated history
  and enforce the four invariants.
- The native schema is shorter for ordinary DML but needs literal as-of views,
  a special historical load, and still cannot enforce I1–I3.
- Q6 is the proof that both clocks matter.

---

## 14. Verification

Run from an empty database:

```bash
for f in 01_schema.sql 02_data.sql 03_timeline.sql 04_views.sql 05_tests.sql; do
  docker exec -i bitemporal-mariadb mariadb -uroot -proot < "$f" || exit 1
done
```

Expected final checks:

```sql
SELECT COUNT(*) AS violations FROM v_integrity_violations;  -- 0
SELECT COUNT(*) FROM player;                                -- 60
SELECT COUNT(*) FROM contract_version;                      -- 101
SELECT COUNT(*) FROM coach_assignment_version;              -- 19
SELECT COUNT(*) FROM player_value_version;                  -- 89
SELECT COUNT(*) FROM club_license_version;                  -- 9
SELECT COUNT(*) FROM contract_version
WHERE tx_to = '9999-12-31 23:59:59.999999';                 -- 78
```

Q6 must produce:

```text
2025-09-05  Rusu
2025-09-12  Pop
2026-10-15  Rusu
```

Then:

```bash
docker exec -i bitemporal-mariadb mariadb -uroot -proot < 06_advanced_a1.sql
docker exec -i bitemporal-mariadb mariadb -uroot -proot < 06_advanced_a2.sql
```

Expected A1:

- 12 guard triggers installed;
- six negative tests `REJECTED`;
- demo rows left = 0;
- violations = 0.

Expected A2:

- native contract rows = 101;
- native coach rows = 19;
- all Q1/Q5/Q6 `EXCEPT` differences = 0.

The submission checklist in `README.md` mirrors these checks.

---

## 15. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Container not found | The name or port differs. | Use `docker ps`; adjust `-p` and `--name`. |
| `ERROR 1049 Unknown database` | Scripts run before `01_schema.sql`. | Run `01`–`05` in order. |
| `ERROR 1442` in A1 | A trigger tried to modify its own table. | Keep close + insert in procedures; triggers only guard. |
| `ERROR 1351` / `1064` in A2 | Variable or subquery in `FOR SYSTEM_TIME AS OF`. | Use literal timestamps in the native views. |
| `ERROR 1553` dropping `ix_coach_asof` | The index supports the `club_id` foreign key. | Use `IGNORE INDEX` for EXPLAIN, do not drop it. |
| A1 rejects `02_data.sql` / `03_timeline.sql` | Guard triggers block direct writes. | Re-run `01`–`05` first, then A1/A2. |
| Q0 reports a future transaction | Your machine clock is earlier than an authored `@sim_now`. | Run with a clock after 2026-09-01, or adjust the simulated times. |
| Q0 reports an I1/I2/I3 row after a demo | A test or demo was not rolled back. | Re-run `01`–`05`; the scripts are repeatable. |

---

## 16. Design decisions recap

| Decision | Why |
|---|---|
| Four period columns on every version table | Makes bitemporality uniform and queries mechanical. |
| Half-open intervals | No boundary overlap; simple overlap predicate. |
| Sentinels, not NULL | Indexable, checkable, no special-case predicates. |
| `DATE` for valid time | Football facts are day-granular. |
| `DATETIME(6)` UTC for transaction time | Microsecond ordering; no 2038 limit. |
| Anchor + version tables | Stable identity separate from changing facts. |
| `tx_registry` | One logical change, one timestamp, one audit row. |
| `story_event` | Intent (late/proactive/correction) is not always inferable. |
| Q0 as a view | One place for all invariants, usable in tests and demos. |
| `query_params` | MariaDB views cannot take arguments. |
| A1 procedures + triggers | Procedures write; triggers guard. |
| A2 native copies | Demonstrates what the engine can and cannot do. |
| `IGNORE INDEX` for EXPLAIN | The as-of index also supports the foreign key. |

The project deliberately chooses the explicit schema for the core. It is more
verbose than native temporal tables, but it can represent the authored history
exactly, enforce the four invariants, and run on any MariaDB 11.8 without relying
on special loading modes. The native A2 copy is the comparison, not the
replacement.

---

## Appendix A — file map

| File | What it contains |
|---|---|
| `Assignment1.pdf` | The assignment statement. |
| `01_schema.sql` | Database, 13 tables, keys, checks, indexes, calendar, parameters. |
| `02_data.sql` | E1 initial load. |
| `03_timeline.sql` | E2–E9 story replay. |
| `04_views.sql` | Q0–Q8 views. |
| `05_tests.sql` | Parameters, outputs, deliberate violations and rollbacks. |
| `06_advanced_a1.sql` | Four write procedures, twelve guard triggers, negative tests, demo. |
| `06_advanced_a2.sql` | Native temporal tables, five views, Q1/Q5/Q6 comparisons. |
| `README.md` | Run instructions, schema summary, story log, quick checks. |
| `docs.md` | This guide. |
| `report.tex` / `report.pdf` | Four-page report with SQL, outputs, failed attempts and EXPLAIN. |
| `er_diagram.tex` / `.pdf` / `.png` | ER diagram with temporal labels and cardinalities. |
| `tools/gen_seed.py` | Seed-data generator. |
| `tools/check_schema.sql` | Standalone schema checks. |
| `tools/check_seed.sql` | Standalone seed checks. |
| `tools/check_timeline.sql` | Standalone timeline checks. |
| `tools/explain_q6.sql` | EXPLAIN with and without the as-of index. |

## Appendix B — glossary

| Term | Meaning |
|---|---|
| Anchor | A non-temporal table holding stable identity (club, player, coach). |
| Version table | A table with one row per belief about a fact over time. |
| Valid time (VT) | When the fact is true in the modelled world. |
| Transaction time (TT) | When the database believed the fact. |
| Bitemporal | Having both valid time and transaction time. |
| Half-open | `[from, to)`: includes `from`, excludes `to`. |
| Sentinel | A real value used for an open end (`9999-12-31`). |
| Current belief | A row whose `tx_to` is the open transaction sentinel. |
| As-of query | A query that reconstructs the database at a past transaction time. |
| Coalescing | Merging adjacent valid periods into one continuous tenure. |
| Retraction | Closing a belief in transaction time with no replacement. |
| Invariant | A rule the data must satisfy (I1–I4). |
| Q0 | The view that returns every invariant violation. |
| Guard trigger | A trigger that rejects a forbidden write, not one that performs the write. |

If you understand the five-row Rusu/Pop table, the Q6 query and the difference
between E5 and E8, you understand the project.
