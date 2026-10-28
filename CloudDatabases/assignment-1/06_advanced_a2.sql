-- author: Mihai-Cristian Farcaș
-- A2: Q1, Q5 and Q6 with MariaDB's own temporal features. run after 01-05.
-- valid time: PERIOD FOR; tx time: WITH SYSTEM VERSIONING.
-- history is loaded with system_versioning_insert_history=ON, otherwise
-- every row would get "now" as its tx time.

USE football_bitemporal;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- native copies of the contract and coach tables

DROP VIEW IF EXISTS v_native_q1;
DROP VIEW IF EXISTS v_native_q5;
DROP VIEW IF EXISTS v_native_q6_20250905;
DROP VIEW IF EXISTS v_native_q6_20250912;
DROP VIEW IF EXISTS v_native_q6_20261015;
DROP TABLE IF EXISTS native_contract;
DROP TABLE IF EXISTS native_coach_assignment;

CREATE TABLE native_contract (
    version_id     BIGINT        NOT NULL,
    player_id      INT           NOT NULL,
    club_id        INT           NOT NULL,
    shirt_number   TINYINT       NOT NULL,
    salary_eur     DECIMAL(12,2) NOT NULL,
    contract_type  VARCHAR(20)   NOT NULL,
    valid_from     DATE          NOT NULL,
    valid_to       DATE          NOT NULL,
    tx_id          BIGINT        NOT NULL,
    row_start      TIMESTAMP(6)  GENERATED ALWAYS AS ROW START,
    row_end        TIMESTAMP(6)  GENERATED ALWAYS AS ROW END,
    PERIOD FOR valid_time (valid_from, valid_to),
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    PRIMARY KEY (version_id),
    CHECK (valid_from < valid_to),
    CHECK (salary_eur >= 0),
    CHECK (shirt_number BETWEEN 1 AND 99),
    CHECK (contract_type IN ('permanent','loan'))
) ENGINE=InnoDB WITH SYSTEM VERSIONING;

CREATE TABLE native_coach_assignment (
    version_id  BIGINT       NOT NULL,
    coach_id    INT          NOT NULL,
    club_id     INT          NOT NULL,
    role_title  VARCHAR(30)  NOT NULL,
    valid_from  DATE         NOT NULL,
    valid_to    DATE         NOT NULL,
    tx_id       BIGINT       NOT NULL,
    row_start   TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
    row_end     TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
    PERIOD FOR valid_time (valid_from, valid_to),
    PERIOD FOR SYSTEM_TIME (row_start, row_end),
    PRIMARY KEY (version_id),
    CHECK (valid_from < valid_to),
    CHECK (role_title = 'Head coach')
) ENGINE=InnoDB WITH SYSTEM VERSIONING;

-- load the full history. the engine's open tx end is 2106-02-07 06:28:15.999999
-- (max TIMESTAMP), so the 9999 sentinel maps onto it.

SET SESSION system_versioning_insert_history = ON;

INSERT INTO native_contract
  (version_id, player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_id, row_start, row_end)
SELECT version_id, player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, valid_to, tx_id,
       tx_from,
       CASE WHEN tx_to = '9999-12-31 23:59:59.999999'
            THEN TIMESTAMP'2106-02-07 06:28:15.999999'
            ELSE tx_to
       END
FROM contract_version
ORDER BY version_id;

INSERT INTO native_coach_assignment
  (version_id, coach_id, club_id, role_title, valid_from, valid_to, tx_id,
   row_start, row_end)
SELECT version_id, coach_id, club_id, role_title, valid_from, valid_to, tx_id,
       tx_from,
       CASE WHEN tx_to = '9999-12-31 23:59:59.999999'
            THEN TIMESTAMP'2106-02-07 06:28:15.999999'
            ELSE tx_to
       END
FROM coach_assignment_version
ORDER BY version_id;

SET SESSION system_versioning_insert_history = OFF;

-- native views. FOR SYSTEM_TIME AS OF needs a constant, so Q6 gets one view
-- per known_at date.

CREATE OR REPLACE VIEW v_native_q1 AS
SELECT nc.player_id,
       pl.full_name AS player_name,
       nc.club_id,
       cl.name AS club_name,
       nc.shirt_number,
       nc.salary_eur,
       nc.contract_type,
       nc.valid_from,
       nc.valid_to,
       CAST(nc.row_start AS DATETIME(6)) AS tx_from,
       CAST(CASE WHEN nc.row_end = TIMESTAMP'2106-02-07 06:28:15.999999'
                 THEN '9999-12-31 23:59:59.999999'
                 ELSE DATE_FORMAT(nc.row_end, '%Y-%m-%d %H:%i:%s.%f')
            END AS DATETIME(6)) AS tx_to
FROM native_contract
     FOR SYSTEM_TIME AS OF TIMESTAMP'2026-10-15 23:59:59.999999' AS nc
JOIN player pl ON pl.player_id = nc.player_id
JOIN club cl ON cl.club_id = nc.club_id
WHERE nc.player_id = 1
  AND nc.valid_from <= '2026-10-15'
  AND '2026-10-15' < nc.valid_to;

CREATE OR REPLACE VIEW v_native_q5 AS
SELECT CAST('2026-02-11 12:00:00' AS DATETIME(6)) AS known_at,
       nc.player_id,
       pl.full_name AS player_name,
       nc.club_id,
       cl.name AS club_name,
       nc.shirt_number,
       nc.salary_eur,
       nc.contract_type,
       nc.valid_from,
       nc.valid_to,
       CAST(nc.row_start AS DATETIME(6)) AS tx_from,
       CAST(CASE WHEN nc.row_end = TIMESTAMP'2106-02-07 06:28:15.999999'
                 THEN '9999-12-31 23:59:59.999999'
                 ELSE DATE_FORMAT(nc.row_end, '%Y-%m-%d %H:%i:%s.%f')
            END AS DATETIME(6)) AS tx_to,
       nc.tx_id
FROM native_contract
     FOR SYSTEM_TIME AS OF TIMESTAMP'2026-02-11 12:00:00' AS nc
JOIN player pl ON pl.player_id = nc.player_id
JOIN club cl ON cl.club_id = nc.club_id
ORDER BY nc.player_id, nc.valid_from;

CREATE OR REPLACE VIEW v_native_q6_20250905 AS
SELECT ca.club_id,
       cl.name AS club_name,
       ca.coach_id,
       co.full_name AS coach_name,
       ca.role_title,
       ca.valid_from,
       ca.valid_to,
       CAST(ca.row_start AS DATETIME(6)) AS tx_from,
       CAST(CASE WHEN ca.row_end = TIMESTAMP'2106-02-07 06:28:15.999999'
                 THEN '9999-12-31 23:59:59.999999'
                 ELSE DATE_FORMAT(ca.row_end, '%Y-%m-%d %H:%i:%s.%f')
            END AS DATETIME(6)) AS tx_to
FROM native_coach_assignment
     FOR SYSTEM_TIME AS OF TIMESTAMP'2025-09-05 23:59:59.999999' AS ca
JOIN club cl ON cl.club_id = ca.club_id
JOIN coach co ON co.coach_id = ca.coach_id
WHERE ca.club_id = 1
  AND ca.valid_from <= '2025-09-02'
  AND '2025-09-02' < ca.valid_to;

CREATE OR REPLACE VIEW v_native_q6_20250912 AS
SELECT ca.club_id,
       cl.name AS club_name,
       ca.coach_id,
       co.full_name AS coach_name,
       ca.role_title,
       ca.valid_from,
       ca.valid_to,
       CAST(ca.row_start AS DATETIME(6)) AS tx_from,
       CAST(CASE WHEN ca.row_end = TIMESTAMP'2106-02-07 06:28:15.999999'
                 THEN '9999-12-31 23:59:59.999999'
                 ELSE DATE_FORMAT(ca.row_end, '%Y-%m-%d %H:%i:%s.%f')
            END AS DATETIME(6)) AS tx_to
FROM native_coach_assignment
     FOR SYSTEM_TIME AS OF TIMESTAMP'2025-09-12 23:59:59.999999' AS ca
JOIN club cl ON cl.club_id = ca.club_id
JOIN coach co ON co.coach_id = ca.coach_id
WHERE ca.club_id = 1
  AND ca.valid_from <= '2025-09-02'
  AND '2025-09-02' < ca.valid_to;

CREATE OR REPLACE VIEW v_native_q6_20261015 AS
SELECT ca.club_id,
       cl.name AS club_name,
       ca.coach_id,
       co.full_name AS coach_name,
       ca.role_title,
       ca.valid_from,
       ca.valid_to,
       CAST(ca.row_start AS DATETIME(6)) AS tx_from,
       CAST(CASE WHEN ca.row_end = TIMESTAMP'2106-02-07 06:28:15.999999'
                 THEN '9999-12-31 23:59:59.999999'
                 ELSE DATE_FORMAT(ca.row_end, '%Y-%m-%d %H:%i:%s.%f')
            END AS DATETIME(6)) AS tx_to
FROM native_coach_assignment
     FOR SYSTEM_TIME AS OF TIMESTAMP'2026-10-15 23:59:59.999999' AS ca
JOIN club cl ON cl.club_id = ca.club_id
JOIN coach co ON co.coach_id = ca.coach_id
WHERE ca.club_id = 1
  AND ca.valid_from <= '2025-09-02'
  AND '2025-09-02' < ca.valid_to;

-- every core row made it into the native history

SELECT 'A2 NATIVE VOLUME' AS section,
       (SELECT COUNT(*) FROM native_contract FOR SYSTEM_TIME ALL) AS native_contract_rows,
       (SELECT COUNT(*) FROM contract_version) AS core_contract_rows,
       (SELECT COUNT(*) FROM native_coach_assignment FOR SYSTEM_TIME ALL) AS native_coach_rows,
       (SELECT COUNT(*) FROM coach_assignment_version) AS core_coach_rows;

-- Q1: P1's contract on 2026-10-15, core vs native

UPDATE query_params
SET valid_at = '2026-10-15',
    known_at = '2026-10-15 23:59:59.999999',
    subject_id = 1;

SELECT 'Q1 CORE' AS section, player_id, player_name, club_name, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM v_q1_current_facts;

SELECT 'Q1 NATIVE' AS section, player_id, player_name, club_name, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM v_native_q1;

SELECT 'Q1 DIFF core -> native' AS section, COUNT(*) AS mismatches
FROM (
    SELECT player_id, player_name, club_id, club_name, shirt_number, salary_eur,
           contract_type, valid_from, valid_to, tx_from, tx_to
    FROM v_q1_current_facts
    EXCEPT
    SELECT player_id, player_name, club_id, club_name, shirt_number, salary_eur,
           contract_type, valid_from, valid_to, tx_from, tx_to
    FROM v_native_q1
) d;

SELECT 'Q1 DIFF native -> core' AS section, COUNT(*) AS mismatches
FROM (
    SELECT player_id, player_name, club_id, club_name, shirt_number, salary_eur,
           contract_type, valid_from, valid_to, tx_from, tx_to
    FROM v_native_q1
    EXCEPT
    SELECT player_id, player_name, club_id, club_name, shirt_number, salary_eur,
           contract_type, valid_from, valid_to, tx_from, tx_to
    FROM v_q1_current_facts
) d;

-- Q5: contracts as believed on 2026-02-11 12:00 (includes the E8 row)

UPDATE query_params SET known_at = '2026-02-11 12:00:00';

SELECT 'Q5 COUNTS' AS section,
       (SELECT COUNT(*) FROM v_q5_as_known) AS core_rows,
       (SELECT COUNT(*) FROM v_native_q5) AS native_rows;

SELECT 'Q5 SAMPLE (P6 AND P51)' AS section,
       known_at, player_id, player_name, club_name, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM v_q5_as_known
WHERE player_id IN (6, 51)
ORDER BY player_id, valid_from;

SELECT 'Q5 NATIVE SAMPLE (P6 AND P51)' AS section,
       known_at, player_id, player_name, club_name, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM v_native_q5
WHERE player_id IN (6, 51)
ORDER BY player_id, valid_from;

SELECT 'Q5 DIFF core -> native' AS section, COUNT(*) AS mismatches
FROM (
    SELECT known_at, player_id, player_name, club_id, club_name, shirt_number,
           salary_eur, contract_type, valid_from, valid_to, tx_from, tx_to, tx_id
    FROM v_q5_as_known
    EXCEPT
    SELECT known_at, player_id, player_name, club_id, club_name, shirt_number,
           salary_eur, contract_type, valid_from, valid_to, tx_from, tx_to, tx_id
    FROM v_native_q5
) d;

SELECT 'Q5 DIFF native -> core' AS section, COUNT(*) AS mismatches
FROM (
    SELECT known_at, player_id, player_name, club_id, club_name, shirt_number,
           salary_eur, contract_type, valid_from, valid_to, tx_from, tx_to, tx_id
    FROM v_native_q5
    EXCEPT
    SELECT known_at, player_id, player_name, club_id, club_name, shirt_number,
           salary_eur, contract_type, valid_from, valid_to, tx_from, tx_to, tx_id
    FROM v_q5_as_known
) d;

-- Q6: the three answers, through FOR SYSTEM_TIME AS OF

UPDATE query_params
SET valid_at = '2025-09-02',
    known_at = '2025-09-05 23:59:59.999999',
    subject_id = 1;

SELECT 'Q6 CORE 2025-09-05' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_q6_bitemporal_point;
SELECT 'Q6 NATIVE 2025-09-05' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_native_q6_20250905;

SELECT 'Q6 DIFF 2025-09-05 core -> native' AS section, COUNT(*) AS mismatches
FROM (
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_q6_bitemporal_point
    EXCEPT
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_native_q6_20250905
) d;

UPDATE query_params SET known_at = '2025-09-12 23:59:59.999999';

SELECT 'Q6 CORE 2025-09-12' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_q6_bitemporal_point;
SELECT 'Q6 NATIVE 2025-09-12' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_native_q6_20250912;

SELECT 'Q6 DIFF 2025-09-12 core -> native' AS section, COUNT(*) AS mismatches
FROM (
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_q6_bitemporal_point
    EXCEPT
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_native_q6_20250912
) d;

UPDATE query_params SET known_at = '2026-10-15 23:59:59.999999';

SELECT 'Q6 CORE 2026-10-15' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_q6_bitemporal_point;
SELECT 'Q6 NATIVE 2026-10-15' AS section, club_name, coach_name, valid_from, valid_to, tx_from, tx_to
FROM v_native_q6_20261015;

SELECT 'Q6 DIFF 2026-10-15 core -> native' AS section, COUNT(*) AS mismatches
FROM (
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_q6_bitemporal_point
    EXCEPT
    SELECT club_id, club_name, coach_id, coach_name, role_title,
           valid_from, valid_to, tx_from, tx_to
    FROM v_native_q6_20261015
) d;

-- reset the parameters

UPDATE query_params
SET valid_at = '2026-10-15',
    known_at = '2026-10-15 23:59:59.999999',
    period_start = '2025-07-01',
    period_end = '2026-07-01',
    subject_id = 1;
