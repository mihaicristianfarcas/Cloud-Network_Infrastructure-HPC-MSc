-- schema check, run after 01_schema.sql
SELECT COUNT(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'football_bitemporal'
  AND table_name IN ('agent','club','player','coach','season','calendar_month','tx_registry',
                     'story_event','club_license_version','contract_version',
                     'coach_assignment_version','player_value_version','query_params');

SELECT COUNT(*) AS contract_checks
FROM information_schema.table_constraints
WHERE constraint_schema = 'football_bitemporal'
  AND table_name = 'contract_version'
  AND constraint_type = 'CHECK';

SELECT COUNT(*) AS contract_asof_index
FROM information_schema.statistics
WHERE table_schema = 'football_bitemporal'
  AND table_name = 'contract_version'
  AND index_name = 'ix_contract_asof';

SELECT COUNT(*) AS params_rows FROM football_bitemporal.query_params;
