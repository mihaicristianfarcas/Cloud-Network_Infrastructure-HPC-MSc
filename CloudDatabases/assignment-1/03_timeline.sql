-- author: Mihai-Cristian Farcaș
-- E2-E9: the history replay, one transaction per block, in tx-time order.
-- each block sets @sim_now, adds a tx_registry row, closes the old belief
-- (only tx_to changes) and inserts the new one. nothing is deleted.

USE football_bitemporal;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

SET @SENT_DATE := '9999-12-31';
SET @SENT_TS   := '9999-12-31 23:59:59.999999';

-- E3: five players sign for FC Sud, recorded 11-15 days late

SET @sim_now := '2025-07-25 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: P56 signs for FC Sud, recorded 15 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (56, 6, 11, 150000.00, 'permanent', '2025-07-10', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'contract_version', 'player:56', '2025-07-10', NULL,
        'FC Sud, 150000.00', 'Late entry, 15 days after valid_from');

SET @sim_now := '2025-07-28 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: P57 signs for FC Sud, recorded 13 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (57, 6, 12, 170000.00, 'permanent', '2025-07-15', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'contract_version', 'player:57', '2025-07-15', NULL,
        'FC Sud, 170000.00', 'Late entry, 13 days after valid_from');

SET @sim_now := '2025-08-12 09:30:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: P58 signs for FC Sud, recorded 11 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (58, 6, 13, 175000.00, 'permanent', '2025-08-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'contract_version', 'player:58', '2025-08-01', NULL,
        'FC Sud, 175000.00', 'Late entry, 11 days after valid_from');

SET @sim_now := '2025-08-20 14:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: P59 signs for FC Sud, recorded 15 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (59, 6, 14, 195000.00, 'permanent', '2025-08-05', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'contract_version', 'player:59', '2025-08-05', NULL,
        'FC Sud, 195000.00', 'Late entry, 15 days after valid_from');

SET @sim_now := '2025-08-25 16:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: P60 signs for FC Sud, recorded 15 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (60, 6, 15, 200000.00, 'permanent', '2025-08-10', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'contract_version', 'player:60', '2025-08-10', NULL,
        'FC Sud, 200000.00', 'Late entry, 15 days after valid_from');

-- E5: K2 (Pop) leaves CS Port

SET @sim_now := '2025-09-01 08:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: K2 leaves CS Port, valid_to 2025-09-01');
SET @tx := LAST_INSERT_ID();
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 2 AND club_id = 2 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2025-09-01', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 2 AND club_id = 2 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'coach_assignment_version', 'club:2', '2025-09-01',
        'K2 open-ended', 'K2 until 2025-09-01', 'K2 leaves CS Port');

-- E4: FC Sud's licence was entered as conditional, it's actually full

SET @sim_now := '2025-09-05 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'licence-officer', 'E4 correction: FC Sud licence status conditional -> full');
SET @tx := LAST_INSERT_ID();
UPDATE club_license_version
SET tx_to = @sim_now
WHERE club_id = 6 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO club_license_version
  (club_id, league_name, license_status, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT club_id, league_name, 'full', valid_from, valid_to, @sim_now, @SENT_TS, @tx
FROM club_license_version
WHERE club_id = 6 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E4', 'club_license_version', 'club:6', '2025-07-01',
        'conditional', 'full', 'Licence status corrected, same valid period');

-- E3 + E7: on 10 Sep, Pop is recorded as FC Nord's coach from 1 Sep (9 days late)

SET @sim_now := '2025-09-10 14:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: K2 takes FC Nord on 2025-09-01, recorded 9 days late');
SET @tx := LAST_INSERT_ID();

UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 1 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;

INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2025-09-01', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 1 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (2, 1, 'Head coach', '2025-09-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E3', 'coach_assignment_version', 'club:1', '2025-09-01',
   'K1 Mihai Rusu', 'K2 Andrei Pop', 'Late entry: Pop took over 9 days before recording'),
  (@tx, 'E7', 'coach_assignment_version', 'club:1', '2025-09-01',
   'K1 Mihai Rusu', 'K2 Andrei Pop', 'Head coach changed');

-- E4 + E7: on 15 Sep the handover is corrected to 3 Sep.
-- FC Nord now has the five rows from the assignment's story.

SET @sim_now := '2025-09-15 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'auditor', 'E4 correction: FC Nord handover was 2025-09-03, not 2025-09-01');
SET @tx := LAST_INSERT_ID();

UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE club_id = 1 AND tx_to = @SENT_TS;

-- close both rows from 10 Sep, then insert the corrected pair
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES
  (1, 1, 'Head coach', '2025-07-01', '2025-09-03', @sim_now, @SENT_TS, @tx),
  (2, 1, 'Head coach', '2025-09-03', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E4', 'coach_assignment_version', 'club:1', '2025-09-01',
   'Pop from 2025-09-01', 'Pop from 2025-09-03', 'Handover date corrected'),
  (@tx, 'E7', 'coach_assignment_version', 'club:1', '2025-09-03',
   'K1 Mihai Rusu', 'K2 Andrei Pop', 'Corrected head coach change');

-- E5: K3 leaves Universitatea Est

SET @sim_now := '2025-09-30 18:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: K3 leaves Universitatea Est, valid_to 2025-10-01');
SET @tx := LAST_INSERT_ID();
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 3 AND club_id = 3 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2025-10-01', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 3 AND club_id = 3 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'coach_assignment_version', 'club:3', '2025-10-01',
        'K3 open-ended', 'K3 until 2025-10-01', 'K3 leaves Universitatea Est');

-- E3 + E7: K3 joins CS Port on 1 Oct, recorded 9 days late

SET @sim_now := '2025-10-10 12:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E3 late entry: K3 takes CS Port on 2025-10-01, recorded 9 days late');
SET @tx := LAST_INSERT_ID();
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (3, 2, 'Head coach', '2025-10-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E3', 'coach_assignment_version', 'club:2', '2025-10-01',
   NULL, 'K3 Vlad Ionescu', 'Late entry: K3 took over 9 days before recording'),
  (@tx, 'E7', 'coach_assignment_version', 'club:2', '2025-10-01',
   NULL, 'K3 Vlad Ionescu', 'Head coach changed after a one-month vacancy');

-- E4: P7's salary was entered as 114,500, it's 150,000 (same period)

SET @sim_now := '2025-11-10 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'payroll', 'E4 correction: P7 salary 114500 -> 150000, effective 2025-07-01');
SET @tx := LAST_INSERT_ID();
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
SELECT @tx, 'E4', 'contract_version', 'player:7', '2025-07-01',
       CAST(salary_eur AS CHAR), '150000.00', 'Salary correction, same valid period'
FROM contract_version
WHERE player_id = 7 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 7 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, 150000.00, contract_type,
       valid_from, valid_to, @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 7 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

-- E5: P6 leaves FC Nord at the end of 2025

SET @sim_now := '2025-12-20 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P6 leaves FC Nord, valid_to 2026-01-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 6 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-01-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 6 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:6', '2026-01-01',
        'FC Nord open-ended', 'FC Nord until 2026-01-01', 'Player leaves at end of 2025');

-- E5: P17 leaves CS Port at the end of 2025 (back in August)

SET @sim_now := '2025-12-20 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P17 leaves CS Port, valid_to 2026-01-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 17 AND club_id = 2 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-01-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 17 AND club_id = 2 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:17', '2026-01-01',
        'CS Port open-ended', 'CS Port until 2026-01-01', 'Player leaves at end of 2025');

-- E5 + E9: FC Sud's licence and its 10 contracts end on 2026-01-01.
-- the suspension is the gap until the licence restarts on 2026-07-01.

SET @sim_now := '2026-01-05 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'licence-officer', 'E5/E9: FC Sud licence suspended; all 10 contracts end 2026-01-01');
SET @tx := LAST_INSERT_ID();

UPDATE club_license_version
SET tx_to = @sim_now
WHERE club_id = 6 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO club_license_version
  (club_id, league_name, license_status, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT club_id, league_name, license_status, valid_from, '2026-01-01', @sim_now, @SENT_TS, @tx
FROM club_license_version
WHERE club_id = 6 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

UPDATE contract_version
SET tx_to = @sim_now
WHERE club_id = 6 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-01-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE club_id = 6 AND tx_to = @sim_now AND valid_to = @SENT_DATE;

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E5', 'club_license_version', 'club:6', '2026-01-01',
   'full, open-ended', 'full until 2026-01-01', 'FC Sud licence suspended from 2026-01-01'),
  (@tx, 'E5', 'contract_version', 'club:6', '2026-01-01',
   '10 open contracts', '10 contracts until 2026-01-01', 'All FC Sud contracts end with the licence'),
  (@tx, 'E9', 'club_license_version+contract_version', 'club:6', '2026-01-01',
   'open licence and contracts', 'licence and contracts until 2026-01-01', 'One change touching two tables');

-- E5 + E7 + E2: coach moves from 15 Jan, in one transaction:
-- K4 Rapid Vest -> Universitatea Est, K6 FC Sud -> Rapid Vest, K1 -> FC Sud

SET @sim_now := '2026-01-05 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'director', 'E5/E7/E2: January coach moves recorded before they take effect');
SET @tx := LAST_INSERT_ID();

-- end K4 at Rapid Vest
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 4 AND club_id = 4 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2026-01-15', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 4 AND club_id = 4 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

-- end K6 at FC Sud
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 6 AND club_id = 6 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2026-01-15', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 6 AND club_id = 6 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

-- new roles
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES
  (4, 3, 'Head coach', '2026-01-15', @SENT_DATE, @sim_now, @SENT_TS, @tx),
  (6, 4, 'Head coach', '2026-01-15', @SENT_DATE, @sim_now, @SENT_TS, @tx),
  (1, 6, 'Head coach', '2026-01-15', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E5', 'coach_assignment_version', 'club:4', '2026-01-15',
   'K4 open-ended', 'K4 until 2026-01-15', 'K4 leaves Rapid Vest'),
  (@tx, 'E5', 'coach_assignment_version', 'club:6', '2026-01-15',
   'K6 open-ended', 'K6 until 2026-01-15', 'K6 leaves FC Sud'),
  (@tx, 'E2', 'coach_assignment_version', 'club:3', '2026-01-15',
   NULL, 'K4 Dan Marinescu', 'Proactive appointment'),
  (@tx, 'E2', 'coach_assignment_version', 'club:4', '2026-01-15',
   NULL, 'K6 Radu Stan', 'Proactive appointment'),
  (@tx, 'E2', 'coach_assignment_version', 'club:6', '2026-01-15',
   NULL, 'K1 Mihai Rusu', 'Proactive appointment'),
  (@tx, 'E7', 'coach_assignment_version', 'club:3', '2026-01-15',
   'vacant', 'K4 Dan Marinescu', 'Head coach changed'),
  (@tx, 'E7', 'coach_assignment_version', 'club:4', '2026-01-15',
   'K4 Dan Marinescu', 'K6 Radu Stan', 'Head coach changed'),
  (@tx, 'E7', 'coach_assignment_version', 'club:6', '2026-01-15',
   'K6 Radu Stan', 'K1 Mihai Rusu', 'Head coach changed');

-- E2 + E9: P12 goes on loan to Rapid Vest; contract and value change together

SET @sim_now := '2026-01-10 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E9: P12 loan CS Port -> Rapid Vest from 2026-01-15');
SET @tx := LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 12 AND club_id = 2 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-01-15', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 12 AND club_id = 2 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (12, 4, 11, 200000.00, 'loan', '2026-01-15', @SENT_DATE, @sim_now, @SENT_TS, @tx);

UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id = 12 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, market_value_eur, valid_from, '2026-01-15', @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id = 12 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (12, 3500000.00, '2026-01-15', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:12', '2026-01-15',
   'CS Port', 'Rapid Vest (loan)', 'Recorded 5 days before the loan starts'),
  (@tx, 'E9', 'contract_version+player_value_version', 'player:12', '2026-01-15',
   'CS Port / 3,080,000', 'Rapid Vest / 3,500,000', 'One change touching two tables');

-- E2: P1 renews with FC Nord for 2026/27, recorded six months early

SET @sim_now := '2026-01-18 12:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2: P1 renews with FC Nord from 2026-07-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 1 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 1 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (1, 1, 1, 120000.00, 'permanent', '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E2', 'contract_version', 'player:1', '2026-07-01',
        'FC Nord, 93,500', 'FC Nord, 120,000', 'Renewal recorded before it takes effect');

-- E4: P8's market value was entered as 1,690,000, it's 3,200,000

SET @sim_now := '2026-01-20 15:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'analyst', 'E4 correction: P8 market value 1,690,000 -> 3,200,000');
SET @tx := LAST_INSERT_ID();
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
SELECT @tx, 'E4', 'player_value_version', 'player:8', '2025-07-01',
       CAST(market_value_eur AS CHAR), '3200000.00', 'Market value correction'
FROM player_value_version
WHERE player_id = 8 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id = 8 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, 3200000.00, valid_from, valid_to, @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id = 8 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;

-- E5: P7, P16 and P27 leave on 31 Jan (P7 and P27 come back later: E6)

SET @sim_now := '2026-01-20 16:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P7 leaves FC Nord, valid_to 2026-02-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 7 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-02-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 7 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:7', '2026-02-01',
        'FC Nord open-ended', 'FC Nord until 2026-02-01', 'Player leaves');

SET @sim_now := '2026-01-25 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P16 leaves CS Port, valid_to 2026-02-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 16 AND club_id = 2 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-02-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 16 AND club_id = 2 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:16', '2026-02-01',
        'CS Port open-ended', 'CS Port until 2026-02-01', 'Player leaves');

SET @sim_now := '2026-01-25 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P27 leaves Universitatea Est, valid_to 2026-02-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 27 AND club_id = 3 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-02-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 27 AND club_id = 3 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:27', '2026-02-01',
        'Universitatea Est open-ended', 'Universitatea Est until 2026-02-01', 'Player leaves');

-- E2: P10's value rises on 1 Mar, recorded on 1 Feb

SET @sim_now := '2026-02-01 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'analyst', 'E2: P10 market value rises from 2026-03-01');
SET @tx := LAST_INSERT_ID();
UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id = 10 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, market_value_eur, valid_from, '2026-03-01', @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id = 10 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (10, 2800000.00, '2026-03-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E2', 'player_value_version', 'player:10', '2026-03-01',
        '2,330,000', '2,800,000', 'Proactive value change');

-- E8: a wrong P6/CS Port contract is inserted, then retracted (tx time only)

SET @sim_now := '2026-02-10 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'clerk', 'E8 erroneous insert: P6 at CS Port, never true');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (6, 2, 11, 100000.00, 'permanent', '2026-01-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E8', 'contract_version', 'player:6', '2026-01-01', NULL,
        'CS Port, 100,000', 'Erroneous belief inserted');

SET @sim_now := '2026-02-12 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'auditor', 'E8 retraction: P6 at CS Port was never true');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 6 AND club_id = 2
  AND tx_from = '2026-02-10 10:00:00.000000' AND tx_to = @SENT_TS;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E8', 'contract_version', 'player:6', '2026-01-01',
        'CS Port, 100,000', NULL, 'Retracted in transaction time, no replacement');

-- E3: P30's new value, recorded 14 days late

SET @sim_now := '2026-02-15 14:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'analyst', 'E3 late value: P30 value effective 2026-02-01, recorded 14 days late');
SET @tx := LAST_INSERT_ID();
UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id = 30 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, market_value_eur, valid_from, '2026-02-01', @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id = 30 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (30, 6100000.00, '2026-02-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E3', 'player_value_version', 'player:30', '2026-02-01',
        '5,300,000', '6,100,000', 'Late value entry, 14 days after valid_from');

-- E5: K5 leaves CSM Centru at the end of May

SET @sim_now := '2026-05-20 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: K5 leaves CSM Centru, valid_to 2026-06-01');
SET @tx := LAST_INSERT_ID();
UPDATE coach_assignment_version
SET tx_to = @sim_now
WHERE coach_id = 5 AND club_id = 5 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO coach_assignment_version
  (coach_id, club_id, role_title, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT coach_id, club_id, role_title, valid_from, '2026-06-01', @sim_now, @SENT_TS, @tx
FROM coach_assignment_version
WHERE coach_id = 5 AND club_id = 5 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'coach_assignment_version', 'club:5', '2026-06-01',
        'K5 open-ended', 'K5 until 2026-06-01', 'K5 leaves CSM Centru');

-- E5 + E6: P12's loan is cut short, back at CS Port on 1 Jun

SET @sim_now := '2026-05-20 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E5/E6: P12 loan cut short; returns to CS Port 2026-06-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 12 AND club_id = 4 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-06-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 12 AND club_id = 4 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (12, 2, 2, 200000.00, 'permanent', '2026-06-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E5', 'contract_version', 'player:12', '2026-06-01',
   'Rapid Vest loan open-ended', 'Rapid Vest loan until 2026-06-01', 'Loan cut short'),
  (@tx, 'E6', 'contract_version', 'player:12', '2026-06-01',
   'CS Port until 2026-01-15', 'CS Port from 2026-06-01', 'Restart after a loan gap');

-- E5: P46 and P26 leave at the end of 2025/26 (both come back later)

SET @sim_now := '2026-05-20 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P46 leaves CSM Centru, valid_to 2026-07-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 46 AND club_id = 5 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 46 AND club_id = 5 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:46', '2026-07-01',
        'CSM Centru open-ended', 'CSM Centru until 2026-07-01', 'Player leaves');

SET @sim_now := '2026-06-15 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'secretary', 'E5 end: P26 leaves Universitatea Est, valid_to 2026-07-01');
SET @tx := LAST_INSERT_ID();
UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 26 AND club_id = 3 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 26 AND club_id = 3 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES (@tx, 'E5', 'contract_version', 'player:26', '2026-07-01',
        'Universitatea Est open-ended', 'Universitatea Est until 2026-07-01', 'Player leaves');

-- E2 + E6: P7 re-joins FC Nord on 1 Jul after a five-month gap

SET @sim_now := '2026-06-15 11:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E6: P7 re-joins FC Nord from 2026-07-01');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (7, 1, 8, 160000.00, 'permanent', '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:7', '2026-07-01',
   'free agent', 'FC Nord, 160,000', 'Proactive re-signing'),
  (@tx, 'E6', 'contract_version', 'player:7', '2026-07-01',
   'FC Nord until 2026-02-01', 'FC Nord from 2026-07-01', 'Restart after a five-month gap');

-- E2 + E6 + E9: FC Sud is re-licensed: licence, 10 contracts and 10 values
-- in one transaction

SET @sim_now := '2026-06-20 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'licence-officer', 'E2/E6/E9: FC Sud re-licensed; 10 contracts and values restart 2026-07-01');
SET @tx := LAST_INSERT_ID();

INSERT INTO club_license_version
  (club_id, league_name, license_status, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (6, 'SuperLiga', 'full', '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, ROUND(salary_eur * 1.05, 2), contract_type,
       '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE club_id = 6 AND tx_to = @SENT_TS AND valid_to = '2026-01-01';

UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id BETWEEN 51 AND 60 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, market_value_eur, valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id BETWEEN 51 AND 60 AND tx_to = @sim_now AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, ROUND(market_value_eur * 1.10, 2), '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id BETWEEN 51 AND 60 AND tx_to = @sim_now AND valid_to = @SENT_DATE;

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'club_license_version', 'club:6', '2026-07-01',
   'suspended', 'full', 'Licence reinstated before it takes effect'),
  (@tx, 'E2', 'contract_version', 'club:6', '2026-07-01',
   '10 ended contracts', '10 contracts from 2026-07-01', 'Ten proactive contract restarts'),
  (@tx, 'E2', 'player_value_version', 'club:6', '2026-07-01',
   '10 values', '10 values +10%', 'Ten proactive value changes'),
  (@tx, 'E9', 'club_license_version+contract_version+player_value_version', 'club:6', '2026-07-01',
   'suspended licence / ended contracts', 'full licence / restarted contracts / new values', 'One change touching three tables');

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
SELECT @tx, 'E6', 'contract_version', CONCAT('player:', player_id), '2026-07-01',
       'FC Sud until 2026-01-01', 'FC Sud from 2026-07-01', 'Restart after the licence gap'
FROM contract_version
WHERE club_id = 6 AND tx_from = @sim_now AND valid_from = '2026-07-01';

-- E2 + E9: P2 moves FC Nord -> Universitatea Est; contract and value together

SET @sim_now := '2026-06-20 10:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E9: P2 transfer FC Nord -> Universitatea Est from 2026-07-01');
SET @tx := LAST_INSERT_ID();

UPDATE contract_version
SET tx_to = @sim_now
WHERE player_id = 2 AND club_id = 1 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM contract_version
WHERE player_id = 2 AND club_id = 1 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (2, 3, 11, 140000.00, 'permanent', '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);

UPDATE player_value_version
SET tx_to = @sim_now
WHERE player_id = 2 AND tx_to = @SENT_TS AND valid_to = @SENT_DATE;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
SELECT player_id, market_value_eur, valid_from, '2026-07-01', @sim_now, @SENT_TS, @tx
FROM player_value_version
WHERE player_id = 2 AND tx_to = @sim_now AND valid_to = @SENT_DATE
ORDER BY version_id DESC LIMIT 1;
INSERT INTO player_value_version
  (player_id, market_value_eur, valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (2, 1200000.00, '2026-07-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);

INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:2', '2026-07-01',
   'FC Nord', 'Universitatea Est', 'Transfer recorded before it takes effect'),
  (@tx, 'E9', 'contract_version+player_value_version', 'player:2', '2026-07-01',
   'FC Nord / 950,000', 'Universitatea Est / 1,200,000', 'One change touching two tables');

-- E2 + E6: P17 re-joins CS Port on 1 Aug

SET @sim_now := '2026-07-20 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E6: P17 re-joins CS Port from 2026-08-01');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (17, 2, 7, 195000.00, 'permanent', '2026-08-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:17', '2026-08-01',
   'free agent', 'CS Port, 195,000', 'Proactive re-signing'),
  (@tx, 'E6', 'contract_version', 'player:17', '2026-08-01',
   'CS Port until 2026-01-01', 'CS Port from 2026-08-01', 'Restart after a seven-month gap');

-- E2 + E6: P46 re-joins CSM Centru on 1 Sep

SET @sim_now := '2026-08-20 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E6: P46 re-joins CSM Centru from 2026-09-01');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (46, 5, 6, 140000.00, 'permanent', '2026-09-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:46', '2026-09-01',
   'free agent', 'CSM Centru, 140,000', 'Proactive re-signing'),
  (@tx, 'E6', 'contract_version', 'player:46', '2026-09-01',
   'CSM Centru until 2026-07-01', 'CSM Centru from 2026-09-01', 'Restart after a two-month gap');

-- E2 + E6: P27 re-joins Universitatea Est on 1 Jan 2027, recorded early

SET @sim_now := '2026-09-01 09:00:00';
INSERT INTO tx_registry (tx_time, author, reason)
VALUES (@sim_now, 'sporting-director', 'E2/E6: P27 re-joins Universitatea Est from 2027-01-01');
SET @tx := LAST_INSERT_ID();
INSERT INTO contract_version
  (player_id, club_id, shirt_number, salary_eur, contract_type,
   valid_from, valid_to, tx_from, tx_to, tx_id)
VALUES (27, 3, 7, 135000.00, 'permanent', '2027-01-01', @SENT_DATE, @sim_now, @SENT_TS, @tx);
INSERT INTO story_event
  (tx_id, event_code, table_name, business_key, valid_date, old_value, new_value, note)
VALUES
  (@tx, 'E2', 'contract_version', 'player:27', '2027-01-01',
   'free agent', 'Universitatea Est, 135,000', 'Proactive re-signing'),
  (@tx, 'E6', 'contract_version', 'player:27', '2027-01-01',
   'Universitatea Est until 2026-02-01', 'Universitatea Est from 2027-01-01', 'Restart after an eleven-month gap');

