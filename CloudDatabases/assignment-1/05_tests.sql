-- author: Mihai-Cristian Farcaș
-- runs every view with fixed parameters. run after 01-04.
-- the test writes (Q0 and Q2) are rolled back.

USE football_bitemporal;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

SET @SENT_DATE := '9999-12-31';
SET @SENT_TS   := '9999-12-31 23:59:59.999999';

-- volumes

SELECT 'VOLUME' AS section,
       (SELECT COUNT(*) FROM player) AS players,
       (SELECT COUNT(*) FROM club) AS clubs,
       (SELECT COUNT(*) FROM coach) AS coaches,
       (SELECT COUNT(*) FROM contract_version)
         + (SELECT COUNT(*) FROM coach_assignment_version)
         + (SELECT COUNT(*) FROM player_value_version)
         + (SELECT COUNT(*) FROM club_license_version) AS version_rows,
       (SELECT COUNT(*) FROM contract_version
         WHERE tx_to = '9999-12-31 23:59:59.999999') AS current_contract_beliefs;

-- Q0 on the final data: expect 0

SELECT 'Q0 FINAL' AS section, COUNT(*) AS violations
FROM v_integrity_violations;

-- Q0 test: I1 overlap (P1 at FC Nord and CS Port)

START TRANSACTION;
SET @sim_now := '2026-10-20 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'test', 'temporary I1 violation');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (1, 2, 11, 100000.00, 'permanent', '2026-08-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
SELECT 'Q0 I1 VIOLATION' AS section, invariant, table_name, business_key, detail
FROM v_integrity_violations;
ROLLBACK;

-- Q0 test: I2 (P51 at FC Sud during the suspension)

START TRANSACTION;
SET @sim_now := '2026-10-20 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'test', 'temporary I2 violation');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (51, 6, 11, 100000.00, 'permanent', '2026-03-01', '2026-04-01', @sim_now, @SENT_TS, @tx);
SELECT 'Q0 I2 VIOLATION' AS section, invariant, table_name, business_key, detail
FROM v_integrity_violations;
ROLLBACK;

-- Q0 test: I3 (a second FC Nord head coach)

START TRANSACTION;
SET @sim_now := '2026-10-20 12:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'test', 'temporary I3 violation');
SET @tx := LAST_INSERT_ID();
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (5, 1, 'Head coach', '2026-01-01', '2026-02-01', @sim_now, @SENT_TS, @tx);
SELECT 'Q0 I3 VIOLATION' AS section, invariant, table_name, business_key, detail
FROM v_integrity_violations;
ROLLBACK;

SELECT 'Q0 AFTER ROLLBACK' AS section, COUNT(*) AS violations
FROM v_integrity_violations;

-- Q1: P1's contract on 2026-10-15

UPDATE query_params
SET valid_at = '2026-10-15',
    known_at = '2026-10-15 23:59:59.999999',
    period_start = '2025-07-01',
    period_end = '2026-07-01',
    subject_id = 1;
SELECT 'Q1' AS section;
SELECT player_name, club_name, salary_eur, contract_type, valid_from, valid_to
FROM v_q1_current_facts;

-- Q2: FC Nord's coaches

UPDATE query_params SET subject_id = 1, known_at = '2026-10-15 23:59:59.999999';
SELECT 'Q2' AS section;
SELECT club_name, coach_name, valid_from, valid_to, tenure_days
FROM v_q2_role_history;

-- Q2 test: split Pop's row in two adjacent periods; Q2 should still show one Pop row

START TRANSACTION;
SET @sim_now := '2026-10-15 13:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'test', 'temporary split: K2 extension from 2026-07-01');
SET @tx := LAST_INSERT_ID();
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 2 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES
  (2, 1, 'Head coach', '2025-09-03', '2026-07-01', @sim_now, @SENT_TS, @tx),
  (2, 1, 'Head coach', '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
SELECT 'Q2 SPLIT RAW ROWS' AS section, co.full_name AS coach_name,
       ca.valid_from, ca.valid_to
FROM coach_assignment_version ca
JOIN coach co ON co.coach_id = ca.coach_id
WHERE ca.club_id = 1 AND ca.tx_to = @SENT_TS
ORDER BY ca.valid_from;
SELECT 'Q2 SPLIT COALESCED' AS section, coach_name, valid_from, valid_to, tenure_days
FROM v_q2_role_history;
ROLLBACK;

-- Q3

SELECT 'Q3 COUNTS' AS section;
SELECT event_code, event_label, COUNT(*) AS events
FROM v_q3_events
GROUP BY event_code, event_label
ORDER BY event_code;
SELECT 'Q3 EVENTS' AS section;
SELECT event_code, event_label, derived_label, table_name, business_key, valid_date,
       tx_time, delay_days, old_value, new_value
FROM v_q3_events
ORDER BY tx_time, event_id;
-- authored and derived labels should agree
SELECT 'Q3 LABEL MISMATCHES' AS section, COUNT(*) AS mismatches
FROM v_q3_events
WHERE derived_label IS NULL OR derived_label <> event_label;

-- Q4: season 2025/26

UPDATE query_params SET period_start = '2025-07-01', period_end = '2026-07-01';
SELECT 'Q4 COUNTS' AS section;
SELECT at_some_point, throughout, COUNT(*) AS facts
FROM v_q4_period_facts
GROUP BY at_some_point, throughout;
SELECT 'Q4 THROUGHOUT EXAMPLES' AS section;
SELECT player_name, club_name, valid_from, valid_to, at_some_point, throughout
FROM v_q4_period_facts
WHERE throughout = 1
ORDER BY player_id, valid_from
LIMIT 5;
SELECT 'Q4 AT-SOME-POINT-ONLY EXAMPLES' AS section;
SELECT player_name, club_name, valid_from, valid_to, at_some_point, throughout
FROM v_q4_period_facts
WHERE throughout = 0
ORDER BY player_id, valid_from
LIMIT 5;

-- Q5: contracts as believed on 2026-02-11, with the wrong E8 row

UPDATE query_params SET known_at = '2026-02-11 12:00:00';
SELECT 'Q5 P6 AS KNOWN ON 2026-02-11' AS section;
SELECT player_name, club_name, valid_from, valid_to, tx_from, tx_to
FROM v_q5_as_known
WHERE player_id = 6;
SELECT 'Q5 ROW COUNT' AS section, COUNT(*) AS believed_rows
FROM v_q5_as_known;

-- Q6: valid 2025-09-02, known at three dates

UPDATE query_params
SET valid_at = '2025-09-02',
    known_at = '2025-09-05 23:59:59.999999',
    subject_id = 1;
SELECT 'Q6 KNOWN 2025-09-05' AS section, coach_name
FROM v_q6_bitemporal_point;
UPDATE query_params SET known_at = '2025-09-12 23:59:59.999999';
SELECT 'Q6 KNOWN 2025-09-12' AS section, coach_name
FROM v_q6_bitemporal_point;
UPDATE query_params SET known_at = '2026-10-15 23:59:59.999999';
SELECT 'Q6 KNOWN 2026-10-15' AS section, coach_name
FROM v_q6_bitemporal_point;

-- Q7: FC Sud has six empty months

UPDATE query_params
SET period_start = '2025-07-01',
    period_end = '2026-07-01';
SELECT 'Q7 FC SUD MONTHS' AS section;
SELECT month_start, club_name, active_contracts
FROM v_q7_monthly_active
WHERE club_id = 6
ORDER BY month_start;
SELECT 'Q7 ZERO-MONTH ROWS' AS section, COUNT(*) AS zero_rows
FROM v_q7_monthly_active
WHERE active_contracts = 0;

-- Q8

SELECT 'Q8 GAPS' AS section;
SELECT player_id, player_name, club_name, previous_to, next_from, gap_days
FROM v_q8_gaps
ORDER BY gap_days DESC, player_id, club_id;
SELECT 'Q8 GAP COUNT' AS section, COUNT(*) AS gaps
FROM v_q8_gaps;

-- reset the parameters
UPDATE query_params
SET valid_at = '2026-10-15',
    known_at = '2026-10-15 23:59:59.999999',
    period_start = '2025-07-01',
    period_end = '2026-07-01',
    subject_id = 1;
