-- the EXPLAIN comparison from the report: Q6 with and without ix_coach_asof
USE football_bitemporal;
SET time_zone = '+00:00';

-- closing a belief changes tx_to, which is in the index, and InnoDB keeps the
-- old entries until purge runs. wait for purge so the row estimate is stable.
SET GLOBAL innodb_max_purge_lag_wait = 0;

UPDATE query_params
SET valid_at = '2025-09-02',
    known_at = '2025-09-12 23:59:59.999999',
    subject_id = 1;

SELECT 'Q6 WITH ix_coach_asof' AS plan;

EXPLAIN
SELECT ca.club_id, ca.coach_id, ca.valid_from, ca.valid_to,
       ca.tx_from, ca.tx_to
FROM query_params p
JOIN coach_assignment_version ca
  ON ca.club_id = p.subject_id
 AND ca.valid_from <= p.valid_at
 AND p.valid_at < ca.valid_to
 AND ca.tx_from <= p.known_at
 AND p.known_at < ca.tx_to
WHERE p.param_id = 1;

SELECT 'Q6 WITHOUT ix_coach_asof (IGNORE INDEX)' AS plan;

EXPLAIN
SELECT ca.club_id, ca.coach_id, ca.valid_from, ca.valid_to,
       ca.tx_from, ca.tx_to
FROM query_params p
JOIN coach_assignment_version ca IGNORE INDEX (ix_coach_asof)
  ON ca.club_id = p.subject_id
 AND ca.valid_from <= p.valid_at
 AND p.valid_at < ca.valid_to
 AND ca.tx_from <= p.known_at
 AND p.known_at < ca.tx_to
WHERE p.param_id = 1;

UPDATE query_params
SET valid_at = '2026-10-15',
    known_at = '2026-10-15 23:59:59.999999',
    period_start = '2025-07-01',
    period_end = '2026-07-01',
    subject_id = 1;
