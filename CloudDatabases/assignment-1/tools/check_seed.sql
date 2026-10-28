-- E1 check, run after 02_data.sql
USE football_bitemporal;
SELECT
  (SELECT COUNT(*) FROM club) AS clubs,
  (SELECT COUNT(*) FROM player) AS players,
  (SELECT COUNT(*) FROM coach) AS coaches,
  (SELECT COUNT(*) FROM agent) AS agents,
  (SELECT COUNT(*) FROM season) AS seasons,
  (SELECT COUNT(*) FROM contract_version) AS contracts,
  (SELECT COUNT(*) FROM player_value_version) AS values_rows,
  (SELECT COUNT(*) FROM club_license_version) AS licences,
  (SELECT COUNT(*) FROM coach_assignment_version) AS coach_roles;

SELECT COUNT(*) AS e1_registry_rows
FROM tx_registry
WHERE reason LIKE 'E1%';

SELECT COUNT(DISTINCT tx_id) AS distinct_e1_tx
FROM contract_version;

-- I1 on the initial load
SELECT COUNT(*) AS overlapping_current_contracts
FROM contract_version a
JOIN contract_version b
  ON a.player_id = b.player_id
 AND a.version_id < b.version_id
 AND a.tx_to = '9999-12-31 23:59:59.999999'
 AND b.tx_to = '9999-12-31 23:59:59.999999'
 AND a.valid_from < b.valid_to
 AND b.valid_from < a.valid_to;
