-- timeline check, run after 03_timeline.sql
USE football_bitemporal;

SELECT event_code, COUNT(*) AS events
FROM story_event
GROUP BY event_code
ORDER BY event_code;

SELECT
  (SELECT COUNT(*) FROM contract_version WHERE tx_to = '9999-12-31 23:59:59.999999') AS current_contract_beliefs,
  (SELECT COUNT(DISTINCT player_id) FROM contract_version WHERE tx_to = '9999-12-31 23:59:59.999999') AS players_with_beliefs,
  (SELECT COUNT(*) FROM contract_version) AS contract_version_rows,
  (SELECT COUNT(*) FROM coach_assignment_version) AS coach_rows,
  (SELECT COUNT(*) FROM player_value_version) AS value_rows,
  (SELECT COUNT(*) FROM club_license_version) AS licence_rows;

-- I1
SELECT COUNT(*) AS i1_violations
FROM contract_version a
JOIN contract_version b
  ON a.player_id = b.player_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to;

-- I2, simple version: each contract fits inside one licence period (Q0 has the full check)
SELECT COUNT(*) AS i2_violations
FROM contract_version c
WHERE c.tx_to = '9999-12-31 23:59:59.999999'
  AND NOT EXISTS (
      SELECT 1
      FROM club_license_version l
      WHERE l.club_id = c.club_id
        AND l.tx_to = '9999-12-31 23:59:59.999999'
        AND l.valid_from <= c.valid_from
        AND c.valid_to <= l.valid_to
  );

-- I3
SELECT COUNT(*) AS i3_violations
FROM coach_assignment_version a
JOIN coach_assignment_version b
  ON a.club_id = b.club_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to;

-- Q6: the three answers
SELECT '2025-09-05' AS known_at, coach_id, valid_from, valid_to
FROM coach_assignment_version
WHERE club_id = 1
  AND valid_from <= '2025-09-02' AND '2025-09-02' < valid_to
  AND tx_from <= '2025-09-05 23:59:59.999999' AND '2025-09-05 23:59:59.999999' < tx_to
UNION ALL
SELECT '2025-09-12', coach_id, valid_from, valid_to
FROM coach_assignment_version
WHERE club_id = 1
  AND valid_from <= '2025-09-02' AND '2025-09-02' < valid_to
  AND tx_from <= '2025-09-12 23:59:59.999999' AND '2025-09-12 23:59:59.999999' < tx_to
UNION ALL
SELECT '2026-10-15', coach_id, valid_from, valid_to
FROM coach_assignment_version
WHERE club_id = 1
  AND valid_from <= '2025-09-02' AND '2025-09-02' < valid_to
  AND tx_from <= '2026-10-15 23:59:59.999999' AND '2026-10-15 23:59:59.999999' < tx_to;

-- Q8 gaps
WITH periods AS (
    SELECT player_id, club_id, valid_from, valid_to,
           LAG(valid_to) OVER (PARTITION BY player_id, club_id ORDER BY valid_from) AS previous_to
    FROM contract_version
    WHERE tx_to = '9999-12-31 23:59:59.999999'
)
SELECT player_id, club_id, previous_to, valid_from,
       DATEDIFF(valid_from, previous_to) AS gap_days
FROM periods
WHERE previous_to IS NOT NULL AND valid_from > previous_to
ORDER BY player_id, club_id, valid_from;
