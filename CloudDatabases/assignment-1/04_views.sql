-- author: Mihai-Cristian Farcaș
-- views for Q0-Q8; parameters come from query_params

USE football_bitemporal;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Q0: rows that break I1-I4 (should be empty)

CREATE OR REPLACE VIEW v_integrity_violations AS
WITH licence_gaps AS (
    SELECT l1.club_id,
           l1.valid_to AS gap_start,
           (SELECT MIN(l2.valid_from)
            FROM club_license_version l2
            WHERE l2.club_id = l1.club_id
              AND l2.tx_to = '9999-12-31 23:59:59.999999'
              AND l2.valid_from > l1.valid_from) AS gap_end
    FROM club_license_version l1
    WHERE l1.tx_to = '9999-12-31 23:59:59.999999'
)
-- I1: a player's current contracts don't overlap
SELECT 'I1' AS invariant,
       'contract_version' AS table_name,
       CONCAT('player:', a.player_id) AS business_key,
       a.version_id AS version_id,
       CONCAT('valid [', a.valid_from, ',', a.valid_to,
              ') overlaps [', b.valid_from, ',', b.valid_to, ')') AS detail
FROM contract_version a
JOIN contract_version b
  ON a.player_id = b.player_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to
UNION ALL
-- I1: a player's current market values don't overlap
SELECT 'I1', 'player_value_version', CONCAT('player:', a.player_id), a.version_id,
       CONCAT('valid [', a.valid_from, ',', a.valid_to,
              ') overlaps [', b.valid_from, ',', b.valid_to, ')')
FROM player_value_version a
JOIN player_value_version b
  ON a.player_id = b.player_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to
UNION ALL
-- I1: a club's current licences don't overlap
SELECT 'I1', 'club_license_version', CONCAT('club:', a.club_id), a.version_id,
       CONCAT('valid [', a.valid_from, ',', a.valid_to,
              ') overlaps [', b.valid_from, ',', b.valid_to, ')')
FROM club_license_version a
JOIN club_license_version b
  ON a.club_id = b.club_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to
UNION ALL
-- I2: a contract is covered by its club's licences, gaps between them included
SELECT 'I2', 'contract_version', CONCAT('player:', c.player_id, '/club:', c.club_id),
       c.version_id,
       CONCAT('contract [', c.valid_from, ',', c.valid_to,
              ') is not covered by the club licence periods')
FROM contract_version c
WHERE c.tx_to = '9999-12-31 23:59:59.999999'
  AND (
      NOT EXISTS (
          SELECT 1
          FROM club_license_version l
          WHERE l.club_id = c.club_id
            AND l.tx_to = '9999-12-31 23:59:59.999999'
      )
      OR c.valid_from < (
          SELECT MIN(l.valid_from)
          FROM club_license_version l
          WHERE l.club_id = c.club_id
            AND l.tx_to = '9999-12-31 23:59:59.999999'
      )
      OR c.valid_to > (
          SELECT MAX(l.valid_to)
          FROM club_license_version l
          WHERE l.club_id = c.club_id
            AND l.tx_to = '9999-12-31 23:59:59.999999'
      )
      OR EXISTS (
          SELECT 1
          FROM licence_gaps g
          WHERE g.club_id = c.club_id
            AND g.gap_end IS NOT NULL
            AND c.valid_from < g.gap_end
            AND g.gap_start < c.valid_to
      )
  )
UNION ALL
-- I3: one head coach per club at a time
SELECT 'I3', 'coach_assignment_version', CONCAT('club:', a.club_id), a.version_id,
       CONCAT('coach ', a.coach_id, ' [', a.valid_from, ',', a.valid_to,
              ') overlaps coach ', b.coach_id, ' [', b.valid_from, ',', b.valid_to, ')')
FROM coach_assignment_version a
JOIN coach_assignment_version b
  ON a.club_id = b.club_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to
UNION ALL
-- I4: tx intervals are well formed and not in the future
-- (immutability is enforced by the A1 triggers)
SELECT 'I4', 'contract_version', CONCAT('version:', version_id), version_id,
       CONCAT('bad tx interval [', tx_from, ',', tx_to, ')')
FROM contract_version
WHERE tx_from > tx_to
   OR (tx_to <> '9999-12-31 23:59:59.999999' AND tx_to > UTC_TIMESTAMP(6))
   OR tx_from > UTC_TIMESTAMP(6)
UNION ALL
SELECT 'I4', 'coach_assignment_version', CONCAT('version:', version_id), version_id,
       CONCAT('bad tx interval [', tx_from, ',', tx_to, ')')
FROM coach_assignment_version
WHERE tx_from > tx_to
   OR (tx_to <> '9999-12-31 23:59:59.999999' AND tx_to > UTC_TIMESTAMP(6))
   OR tx_from > UTC_TIMESTAMP(6)
UNION ALL
SELECT 'I4', 'player_value_version', CONCAT('version:', version_id), version_id,
       CONCAT('bad tx interval [', tx_from, ',', tx_to, ')')
FROM player_value_version
WHERE tx_from > tx_to
   OR (tx_to <> '9999-12-31 23:59:59.999999' AND tx_to > UTC_TIMESTAMP(6))
   OR tx_from > UTC_TIMESTAMP(6)
UNION ALL
SELECT 'I4', 'club_license_version', CONCAT('version:', version_id), version_id,
       CONCAT('bad tx interval [', tx_from, ',', tx_to, ')')
FROM club_license_version
WHERE tx_from > tx_to
   OR (tx_to <> '9999-12-31 23:59:59.999999' AND tx_to > UTC_TIMESTAMP(6))
   OR tx_from > UTC_TIMESTAMP(6);

-- Q1: a player's contract at valid_at, as known at known_at

CREATE OR REPLACE VIEW v_q1_current_facts AS
SELECT p.subject_id AS player_id,
       pl.full_name AS player_name,
       cv.club_id,
       cl.name AS club_name,
       cv.shirt_number,
       cv.salary_eur,
       cv.contract_type,
       cv.valid_from,
       cv.valid_to,
       cv.tx_from,
       cv.tx_to
FROM query_params p
JOIN contract_version cv
  ON cv.player_id = p.subject_id
JOIN player pl ON pl.player_id = cv.player_id
JOIN club cl ON cl.club_id = cv.club_id
WHERE cv.valid_from <= p.valid_at
  AND p.valid_at < cv.valid_to
  AND cv.tx_from <= p.known_at
  AND p.known_at < cv.tx_to;

-- Q2: a club's head coaches as known at known_at, adjacent periods merged,
-- with tenure in days

CREATE OR REPLACE VIEW v_q2_role_history AS
WITH base AS (
    SELECT p.subject_id AS club_id,
           ca.coach_id,
           co.full_name AS coach_name,
           ca.valid_from,
           ca.valid_to
    FROM query_params p
    JOIN coach_assignment_version ca
      ON ca.club_id = p.subject_id
     AND ca.tx_from <= p.known_at
     AND p.known_at < ca.tx_to
    JOIN coach co ON co.coach_id = ca.coach_id
),
marked AS (
    SELECT b.*,
           CASE
               WHEN b.valid_from = LAG(b.valid_to) OVER (
                   PARTITION BY b.coach_id ORDER BY b.valid_from
               ) THEN 0
               ELSE 1
           END AS new_group
    FROM base b
),
grouped AS (
    SELECT m.*,
           SUM(m.new_group) OVER (
               PARTITION BY m.coach_id ORDER BY m.valid_from
           ) AS group_id
    FROM marked m
)
SELECT g.club_id,
       cl.name AS club_name,
       g.coach_id,
       g.coach_name,
       MIN(g.valid_from) AS valid_from,
       MAX(g.valid_to) AS valid_to,
       DATEDIFF(LEAST(MAX(g.valid_to), p.known_at), MIN(g.valid_from)) AS tenure_days
FROM grouped g
JOIN query_params p ON p.param_id = 1
JOIN club cl ON cl.club_id = g.club_id
GROUP BY g.club_id, cl.name, g.coach_id, g.coach_name, g.group_id, p.known_at
ORDER BY MIN(g.valid_from);

-- Q3: proactive, late and corrected entries with delay and old/new values.
-- event_label is the authored one (story_event); derived_label is worked out
-- from the version rows as a cross-check:
--   same key and valid_from closed and restated: correction, unless only an
--   open valid_to became finite (an E5 end)
--   an overlapping row closed and its start not kept: correction (date moved)
--   otherwise a new fact: proactive if it starts after it was recorded,
--   late if recorded 7+ days after

CREATE OR REPLACE VIEW v_q3_events AS
WITH versions AS (
    SELECT 'contract_version' AS table_name,
           CONCAT(player_id, '/', club_id) AS business_key,
           CONCAT_WS('|', shirt_number, salary_eur, contract_type) AS business_value,
           valid_from, valid_to, tx_from, tx_to, tx_id
    FROM contract_version
    UNION ALL
    SELECT 'coach_assignment_version', CONCAT(club_id, '/', coach_id), role_title,
           valid_from, valid_to, tx_from, tx_to, tx_id
    FROM coach_assignment_version
    UNION ALL
    SELECT 'player_value_version', CAST(player_id AS CHAR), CAST(market_value_eur AS CHAR),
           valid_from, valid_to, tx_from, tx_to, tx_id
    FROM player_value_version
    UNION ALL
    SELECT 'club_license_version', CAST(club_id AS CHAR),
           CONCAT_WS('|', league_name, license_status),
           valid_from, valid_to, tx_from, tx_to, tx_id
    FROM club_license_version
),
-- p.tx_to = v.tx_from means p was closed by the transaction that wrote v
row_labels AS (
    SELECT v.tx_id,
           v.table_name,
           CASE
               WHEN EXISTS (
                   SELECT 1 FROM versions p
                   WHERE p.table_name = v.table_name
                     AND p.business_key = v.business_key
                     AND p.tx_to = v.tx_from
                     AND p.valid_from = v.valid_from)
               THEN CASE
                        WHEN EXISTS (
                            SELECT 1 FROM versions p
                            WHERE p.table_name = v.table_name
                              AND p.business_key = v.business_key
                              AND p.tx_to = v.tx_from
                              AND p.valid_from = v.valid_from
                              AND p.business_value = v.business_value
                              AND p.valid_to = '9999-12-31'
                              AND v.valid_to < '9999-12-31')
                        THEN NULL
                        ELSE 'Correction'
                    END
               WHEN EXISTS (
                   SELECT 1 FROM versions p
                   WHERE p.table_name = v.table_name
                     AND p.business_key = v.business_key
                     AND p.tx_to = v.tx_from
                     AND p.valid_from < v.valid_to
                     AND v.valid_from < p.valid_to
                     AND NOT EXISTS (
                         SELECT 1 FROM versions k
                         WHERE k.table_name = p.table_name
                           AND k.business_key = p.business_key
                           AND k.tx_from = p.tx_to
                           AND k.valid_from = p.valid_from))
               THEN 'Correction'
               WHEN v.valid_from > DATE(v.tx_from) THEN 'Proactive'
               WHEN DATEDIFF(v.tx_from, v.valid_from) >= 7 THEN 'Late entry'
           END AS label
    FROM versions v
)
SELECT se.event_id,
       se.event_code,
       CASE se.event_code
            WHEN 'E2' THEN 'Proactive'
            WHEN 'E3' THEN 'Late entry'
            WHEN 'E4' THEN 'Correction'
       END AS event_label,
       (SELECT GROUP_CONCAT(DISTINCT rl.label ORDER BY rl.label SEPARATOR ', ')
        FROM row_labels rl
        WHERE rl.tx_id = se.tx_id
          AND rl.label IS NOT NULL
          AND FIND_IN_SET(rl.table_name, REPLACE(se.table_name, '+', ',')) > 0
       ) AS derived_label,
       se.table_name,
       se.business_key,
       se.valid_date,
       tr.tx_time,
       DATEDIFF(tr.tx_time, se.valid_date) AS delay_days,
       se.old_value,
       se.new_value,
       se.note
FROM story_event se
JOIN tx_registry tr ON tr.tx_id = se.tx_id
WHERE se.event_code IN ('E2','E3','E4')
ORDER BY tr.tx_time, se.event_id;

-- Q4: contracts in a period: overlapping it at some point vs covering it
-- throughout (both half-open)

CREATE OR REPLACE VIEW v_q4_period_facts AS
SELECT p.period_start,
       p.period_end,
       cv.player_id,
       pl.full_name AS player_name,
       cv.club_id,
       cl.name AS club_name,
       cv.valid_from,
       cv.valid_to,
       CASE
           WHEN cv.valid_from < p.period_end
            AND p.period_start < cv.valid_to THEN 1
           ELSE 0
       END AS at_some_point,
       CASE
           WHEN cv.valid_from <= p.period_start
            AND p.period_end <= cv.valid_to THEN 1
           ELSE 0
       END AS throughout
FROM query_params p
JOIN contract_version cv
  ON cv.tx_to = '9999-12-31 23:59:59.999999'
JOIN player pl ON pl.player_id = cv.player_id
JOIN club cl ON cl.club_id = cv.club_id
WHERE cv.valid_from < p.period_end
  AND p.period_start < cv.valid_to;

-- Q5: the contract table as believed at known_at, any valid time

CREATE OR REPLACE VIEW v_q5_as_known AS
SELECT p.known_at,
       cv.player_id,
       pl.full_name AS player_name,
       cv.club_id,
       cl.name AS club_name,
       cv.shirt_number,
       cv.salary_eur,
       cv.contract_type,
       cv.valid_from,
       cv.valid_to,
       cv.tx_from,
       cv.tx_to,
       cv.tx_id
FROM query_params p
JOIN contract_version cv
  ON cv.tx_from <= p.known_at
 AND p.known_at < cv.tx_to
JOIN player pl ON pl.player_id = cv.player_id
JOIN club cl ON cl.club_id = cv.club_id
ORDER BY cv.player_id, cv.valid_from;

-- Q6: a club's head coach at valid_at, as known at known_at

CREATE OR REPLACE VIEW v_q6_bitemporal_point AS
SELECT p.subject_id AS club_id,
       cl.name AS club_name,
       ca.coach_id,
       co.full_name AS coach_name,
       ca.role_title,
       ca.valid_from,
       ca.valid_to,
       ca.tx_from,
       ca.tx_to
FROM query_params p
JOIN coach_assignment_version ca
  ON ca.club_id = p.subject_id
JOIN club cl ON cl.club_id = ca.club_id
JOIN coach co ON co.coach_id = ca.coach_id
WHERE ca.valid_from <= p.valid_at
  AND p.valid_at < ca.valid_to
  AND ca.tx_from <= p.known_at
  AND p.known_at < ca.tx_to;

-- Q7: active contracts per club per month, as known today (empty months show 0)

CREATE OR REPLACE VIEW v_q7_monthly_active AS
SELECT cm.month_start,
       c.club_id,
       c.name AS club_name,
       COUNT(cv.version_id) AS active_contracts
FROM query_params p
JOIN calendar_month cm
  ON cm.month_start >= DATE_SUB(p.period_start, INTERVAL DAYOFMONTH(p.period_start) - 1 DAY)
 AND cm.month_start < p.period_end
CROSS JOIN club c
LEFT JOIN contract_version cv
  ON cv.club_id = c.club_id
 AND cv.tx_to = '9999-12-31 23:59:59.999999'
 AND cv.valid_from < DATE_ADD(cm.month_start, INTERVAL 1 MONTH)
 AND cm.month_start < cv.valid_to
GROUP BY cm.month_start, c.club_id, c.name
ORDER BY cm.month_start, c.club_id;

-- Q8: gaps between periods of the same player-club pair, using LAG

CREATE OR REPLACE VIEW v_q8_gaps AS
WITH periods AS (
    SELECT cv.player_id,
           cv.club_id,
           cv.valid_from,
           cv.valid_to,
           LAG(cv.valid_from) OVER (
               PARTITION BY cv.player_id, cv.club_id ORDER BY cv.valid_from
           ) AS previous_from,
           LAG(cv.valid_to) OVER (
               PARTITION BY cv.player_id, cv.club_id ORDER BY cv.valid_from
           ) AS previous_to
    FROM contract_version cv
    WHERE cv.tx_to = '9999-12-31 23:59:59.999999'
)
SELECT p.player_id,
       pl.full_name AS player_name,
       p.club_id,
       cl.name AS club_name,
       p.previous_from,
       p.previous_to,
       p.valid_from AS next_from,
       p.valid_to AS next_to,
       DATEDIFF(p.valid_from, p.previous_to) AS gap_days
FROM periods p
JOIN player pl ON pl.player_id = p.player_id
JOIN club cl ON cl.club_id = p.club_id
WHERE p.previous_to IS NOT NULL
  AND p.valid_from > p.previous_to
ORDER BY gap_days DESC, p.player_id, p.club_id;
