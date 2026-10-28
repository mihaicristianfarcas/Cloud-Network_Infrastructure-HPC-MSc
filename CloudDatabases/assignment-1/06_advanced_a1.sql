-- author: Mihai-Cristian Farcaș
-- A1: the database manages tx time with a write API and guard triggers.
-- run after 01-05. tx time comes from @sim_now if set, else CURRENT_TIMESTAMP(6).

USE football_bitemporal;
SET NAMES utf8mb4;
SET time_zone = '+00:00';

SET @SENT_DATE := '9999-12-31';
SET @SENT_TS   := '9999-12-31 23:59:59.999999';

DROP PROCEDURE IF EXISTS sp_assert_fact;
DROP PROCEDURE IF EXISTS sp_end_fact;
DROP PROCEDURE IF EXISTS sp_correct_fact;
DROP PROCEDURE IF EXISTS sp_retract_fact;
DROP PROCEDURE IF EXISTS sp_a1_negative_tests;
DROP PROCEDURE IF EXISTS sp_test_direct_insert;
DROP PROCEDURE IF EXISTS sp_test_direct_update;
DROP PROCEDURE IF EXISTS sp_test_direct_tx_from;
DROP PROCEDURE IF EXISTS sp_test_direct_tx_update;
DROP PROCEDURE IF EXISTS sp_test_closed_update;
DROP PROCEDURE IF EXISTS sp_test_delete;
DROP TABLE IF EXISTS a1_negative_results;

-- results of the negative tests (non-temporal)
CREATE TABLE a1_negative_results (
    test_id    INT          NOT NULL AUTO_INCREMENT,
    test_name  VARCHAR(80)  NOT NULL,
    outcome    VARCHAR(20)  NOT NULL,
    error_text VARCHAR(255) NOT NULL,
    tested_at  DATETIME(6)  NOT NULL,
    PRIMARY KEY (test_id),
    CHECK (outcome IN ('REJECTED','NOT REJECTED'))
) ENGINE=InnoDB;

DELIMITER //

-- insert a new contract; the player can't already have an overlapping one
CREATE PROCEDURE sp_assert_fact(
    IN p_player_id  INT,
    IN p_club_id    INT,
    IN p_shirt      TINYINT,
    IN p_salary     DECIMAL(12,2),
    IN p_type       VARCHAR(20),
    IN p_valid_from DATE
)
BEGIN
    DECLARE v_time DATETIME(6);
    DECLARE v_tx   BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @a1_internal = NULL;
        RESIGNAL;
    END;

    SET v_time = IFNULL(@sim_now, CURRENT_TIMESTAMP(6));

    IF p_salary < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A1: salary must be non-negative';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM contract_version
        WHERE player_id = p_player_id
          AND tx_to = '9999-12-31 23:59:59.999999'
          AND valid_from < '9999-12-31'
          AND p_valid_from < valid_to
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: player already has an overlapping current contract';
    END IF;

    -- the new fact is open-ended, so the club needs an open-ended full licence (I2)
    IF NOT EXISTS (
        SELECT 1
        FROM club_license_version
        WHERE club_id = p_club_id
          AND tx_to = '9999-12-31 23:59:59.999999'
          AND license_status = 'full'
          AND valid_from <= p_valid_from
          AND valid_to = '9999-12-31'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: club is not fully licensed for this open-ended contract';
    END IF;

    SET @a1_internal = 1;
    INSERT INTO tx_registry (tx_time, author, reason)
    VALUES (v_time, 'A1 API', CONCAT('sp_assert_fact player=', p_player_id, ' club=', p_club_id));
    SET v_tx = LAST_INSERT_ID();

    INSERT INTO contract_version
      (player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
      (p_player_id, p_club_id, p_shirt, p_salary, p_type,
       p_valid_from, '9999-12-31', v_time, '9999-12-31 23:59:59.999999', v_tx);

    SET @a1_internal = NULL;
END//

-- end an open contract: close the old belief, insert a finite one
CREATE PROCEDURE sp_end_fact(
    IN p_player_id INT,
    IN p_club_id   INT,
    IN p_valid_to  DATE
)
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_valid_from DATE;
    DECLARE v_shirt TINYINT;
    DECLARE v_salary DECIMAL(12,2);
    DECLARE v_type VARCHAR(20);
    DECLARE v_time DATETIME(6);
    DECLARE v_tx BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @a1_internal = NULL;
        RESIGNAL;
    END;

    SET v_time = IFNULL(@sim_now, CURRENT_TIMESTAMP(6));

    SELECT version_id, valid_from, shirt_number, salary_eur, contract_type
      INTO v_version, v_valid_from, v_shirt, v_salary, v_type
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = '9999-12-31 23:59:59.999999'
      AND valid_to = '9999-12-31'
    ORDER BY version_id DESC
    LIMIT 1;

    IF v_version IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: no current open contract for this player and club';
    END IF;
    IF p_valid_to <= v_valid_from THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: valid_to must be after valid_from';
    END IF;

    SET @a1_internal = 1;
    INSERT INTO tx_registry (tx_time, author, reason)
    VALUES (v_time, 'A1 API', CONCAT('sp_end_fact player=', p_player_id, ' club=', p_club_id));
    SET v_tx = LAST_INSERT_ID();

    UPDATE contract_version
    SET tx_to = v_time
    WHERE version_id = v_version
      AND tx_to = '9999-12-31 23:59:59.999999';

    INSERT INTO contract_version
      (player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
      (p_player_id, p_club_id, v_shirt, v_salary, v_type,
       v_valid_from, p_valid_to, v_time, '9999-12-31 23:59:59.999999', v_tx);

    SET @a1_internal = NULL;
END//

-- correct a contract's salary, same valid period
CREATE PROCEDURE sp_correct_fact(
    IN p_player_id INT,
    IN p_club_id   INT,
    IN p_new_salary DECIMAL(12,2)
)
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_valid_from DATE;
    DECLARE v_valid_to DATE;
    DECLARE v_shirt TINYINT;
    DECLARE v_type VARCHAR(20);
    DECLARE v_time DATETIME(6);
    DECLARE v_tx BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @a1_internal = NULL;
        RESIGNAL;
    END;

    SET v_time = IFNULL(@sim_now, CURRENT_TIMESTAMP(6));

    IF p_new_salary < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A1: salary must be non-negative';
    END IF;

    SELECT version_id, valid_from, valid_to, shirt_number, contract_type
      INTO v_version, v_valid_from, v_valid_to, v_shirt, v_type
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = '9999-12-31 23:59:59.999999'
    ORDER BY version_id DESC
    LIMIT 1;

    IF v_version IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: no current contract for this player and club';
    END IF;

    SET @a1_internal = 1;
    INSERT INTO tx_registry (tx_time, author, reason)
    VALUES (v_time, 'A1 API', CONCAT('sp_correct_fact player=', p_player_id, ' club=', p_club_id));
    SET v_tx = LAST_INSERT_ID();

    UPDATE contract_version
    SET tx_to = v_time
    WHERE version_id = v_version
      AND tx_to = '9999-12-31 23:59:59.999999';

    INSERT INTO contract_version
      (player_id, club_id, shirt_number, salary_eur, contract_type,
       valid_from, valid_to, tx_from, tx_to, tx_id)
    VALUES
      (p_player_id, p_club_id, v_shirt, p_new_salary, v_type,
       v_valid_from, v_valid_to, v_time, '9999-12-31 23:59:59.999999', v_tx);

    SET @a1_internal = NULL;
END//

-- retract a fact that was never true: close tx time only, no replacement
CREATE PROCEDURE sp_retract_fact(
    IN p_player_id INT,
    IN p_club_id   INT
)
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_time DATETIME(6);
    DECLARE v_tx BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @a1_internal = NULL;
        RESIGNAL;
    END;

    SET v_time = IFNULL(@sim_now, CURRENT_TIMESTAMP(6));

    SELECT version_id
      INTO v_version
    FROM contract_version
    WHERE player_id = p_player_id
      AND club_id = p_club_id
      AND tx_to = '9999-12-31 23:59:59.999999'
    ORDER BY version_id DESC
    LIMIT 1;

    IF v_version IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1: no current contract to retract';
    END IF;

    SET @a1_internal = 1;
    INSERT INTO tx_registry (tx_time, author, reason)
    VALUES (v_time, 'A1 API', CONCAT('sp_retract_fact player=', p_player_id, ' club=', p_club_id));
    SET v_tx = LAST_INSERT_ID();

    UPDATE contract_version
    SET tx_to = v_time
    WHERE version_id = v_version
      AND tx_to = '9999-12-31 23:59:59.999999';

    SET @a1_internal = NULL;
END//

DELIMITER ;

-- guard triggers. the procedures set @a1_internal around their own writes.

DELIMITER //

-- contract_version

DROP TRIGGER IF EXISTS trg_contract_guard_bi//
CREATE TRIGGER trg_contract_guard_bi BEFORE INSERT ON contract_version
FOR EACH ROW
BEGIN
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct INSERT into contract_version blocked; use the A1 API';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_contract_guard_bu//
CREATE TRIGGER trg_contract_guard_bu BEFORE UPDATE ON contract_version
FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: closed contract_version rows are immutable';
    END IF;
    IF NEW.version_id <> OLD.version_id
       OR NEW.player_id <> OLD.player_id
       OR NEW.club_id <> OLD.club_id
       OR NEW.shirt_number <> OLD.shirt_number
       OR NEW.salary_eur <> OLD.salary_eur
       OR NEW.contract_type <> OLD.contract_type
       OR NEW.valid_from <> OLD.valid_from
       OR NEW.valid_to <> OLD.valid_to
       OR NEW.tx_from <> OLD.tx_from
       OR NEW.tx_id <> OLD.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: only tx_to may change on an open contract_version row';
    END IF;
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct tx_to update blocked; use the A1 API';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_contract_guard_bd//
CREATE TRIGGER trg_contract_guard_bd BEFORE DELETE ON contract_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A1 guard: physical DELETE from contract_version is blocked';
END//

-- coach_assignment_version

DROP TRIGGER IF EXISTS trg_coach_guard_bi//
CREATE TRIGGER trg_coach_guard_bi BEFORE INSERT ON coach_assignment_version
FOR EACH ROW
BEGIN
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct INSERT into coach_assignment_version blocked';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_coach_guard_bu//
CREATE TRIGGER trg_coach_guard_bu BEFORE UPDATE ON coach_assignment_version
FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: closed coach_assignment_version rows are immutable';
    END IF;
    IF NEW.version_id <> OLD.version_id
       OR NEW.coach_id <> OLD.coach_id
       OR NEW.club_id <> OLD.club_id
       OR NEW.role_title <> OLD.role_title
       OR NEW.valid_from <> OLD.valid_from
       OR NEW.valid_to <> OLD.valid_to
       OR NEW.tx_from <> OLD.tx_from
       OR NEW.tx_id <> OLD.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: only tx_to may change on an open coach_assignment_version row';
    END IF;
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct tx_to update blocked; use the A1 API';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_coach_guard_bd//
CREATE TRIGGER trg_coach_guard_bd BEFORE DELETE ON coach_assignment_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A1 guard: physical DELETE from coach_assignment_version is blocked';
END//

-- player_value_version

DROP TRIGGER IF EXISTS trg_value_guard_bi//
CREATE TRIGGER trg_value_guard_bi BEFORE INSERT ON player_value_version
FOR EACH ROW
BEGIN
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct INSERT into player_value_version blocked';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_value_guard_bu//
CREATE TRIGGER trg_value_guard_bu BEFORE UPDATE ON player_value_version
FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: closed player_value_version rows are immutable';
    END IF;
    IF NEW.version_id <> OLD.version_id
       OR NEW.player_id <> OLD.player_id
       OR NEW.market_value_eur <> OLD.market_value_eur
       OR NEW.valid_from <> OLD.valid_from
       OR NEW.valid_to <> OLD.valid_to
       OR NEW.tx_from <> OLD.tx_from
       OR NEW.tx_id <> OLD.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: only tx_to may change on an open player_value_version row';
    END IF;
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct tx_to update blocked; use the A1 API';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_value_guard_bd//
CREATE TRIGGER trg_value_guard_bd BEFORE DELETE ON player_value_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A1 guard: physical DELETE from player_value_version is blocked';
END//

-- club_license_version

DROP TRIGGER IF EXISTS trg_licence_guard_bi//
CREATE TRIGGER trg_licence_guard_bi BEFORE INSERT ON club_license_version
FOR EACH ROW
BEGIN
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct INSERT into club_license_version blocked';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_licence_guard_bu//
CREATE TRIGGER trg_licence_guard_bu BEFORE UPDATE ON club_license_version
FOR EACH ROW
BEGIN
    IF OLD.tx_to <> '9999-12-31 23:59:59.999999' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: closed club_license_version rows are immutable';
    END IF;
    IF NEW.version_id <> OLD.version_id
       OR NEW.club_id <> OLD.club_id
       OR NEW.league_name <> OLD.league_name
       OR NEW.license_status <> OLD.license_status
       OR NEW.valid_from <> OLD.valid_from
       OR NEW.valid_to <> OLD.valid_to
       OR NEW.tx_from <> OLD.tx_from
       OR NEW.tx_id <> OLD.tx_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: only tx_to may change on an open club_license_version row';
    END IF;
    IF @a1_internal IS NULL OR @a1_internal <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A1 guard: direct tx_to update blocked; use the A1 API';
    END IF;
END//

DROP TRIGGER IF EXISTS trg_licence_guard_bd//
CREATE TRIGGER trg_licence_guard_bd BEFORE DELETE ON club_license_version
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A1 guard: physical DELETE from club_license_version is blocked';
END//

-- negative tests: each tries one forbidden statement, catches the error and
-- records it. the attempt is rolled back, so a missing guard changes nothing.

CREATE PROCEDURE sp_test_direct_insert()
BEGIN
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        INSERT INTO contract_version
          (player_id, club_id, shirt_number, salary_eur, contract_type,
           valid_from, valid_to, tx_from, tx_to, tx_id)
        VALUES
          (6, 1, 30, 90000.00, 'permanent',
           '2026-07-01', '9999-12-31',
           '2026-10-20 09:00:00', '9999-12-31 23:59:59.999999', 1);
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct INSERT', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct INSERT', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_test_direct_update()
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    SELECT version_id INTO v_version
    FROM contract_version
    WHERE player_id = 1
      AND tx_to = '9999-12-31 23:59:59.999999'
    ORDER BY version_id DESC
    LIMIT 1;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        UPDATE contract_version
        SET salary_eur = salary_eur + 1000
        WHERE version_id = v_version;
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of a business column', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of a business column', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_test_direct_tx_from()
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    SELECT version_id INTO v_version
    FROM contract_version
    WHERE player_id = 1
      AND tx_to = '9999-12-31 23:59:59.999999'
    ORDER BY version_id DESC
    LIMIT 1;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        UPDATE contract_version
        SET tx_from = '2026-10-19 00:00:00'
        WHERE version_id = v_version;
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of tx_from', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of tx_from', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_test_direct_tx_update()
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    SELECT version_id INTO v_version
    FROM contract_version
    WHERE player_id = 1
      AND tx_to = '9999-12-31 23:59:59.999999'
    ORDER BY version_id DESC
    LIMIT 1;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        UPDATE contract_version
        SET tx_to = '2026-10-20 00:00:00'
        WHERE version_id = v_version;
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of tx_to (bypassing the API)', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('direct UPDATE of tx_to (bypassing the API)', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_test_closed_update()
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    SELECT version_id INTO v_version
    FROM contract_version
    WHERE tx_to <> '9999-12-31 23:59:59.999999'
    ORDER BY version_id
    LIMIT 1;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        UPDATE contract_version
        SET salary_eur = salary_eur + 1000
        WHERE version_id = v_version;
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('UPDATE of a closed row', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('UPDATE of a closed row', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_test_delete()
BEGIN
    DECLARE v_version BIGINT;
    DECLARE v_msg VARCHAR(255) DEFAULT NULL;
    DECLARE v_rejected TINYINT DEFAULT 0;

    SELECT version_id INTO v_version
    FROM contract_version
    WHERE tx_to <> '9999-12-31 23:59:59.999999'
    ORDER BY version_id
    LIMIT 1;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
            SET v_rejected = 1;
        END;

        DELETE FROM contract_version
        WHERE version_id = v_version;
    END;
    ROLLBACK;

    IF v_rejected = 1 THEN
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('physical DELETE', 'REJECTED', v_msg, NOW(6));
    ELSE
        INSERT INTO a1_negative_results (test_name, outcome, error_text, tested_at)
        VALUES ('physical DELETE', 'NOT REJECTED', 'guard trigger missing', NOW(6));
    END IF;
END//

CREATE PROCEDURE sp_a1_negative_tests()
BEGIN
    CALL sp_test_direct_insert();
    CALL sp_test_direct_update();
    CALL sp_test_direct_tx_from();
    CALL sp_test_direct_tx_update();
    CALL sp_test_closed_update();
    CALL sp_test_delete();
END//

DELIMITER ;

-- installed guards

SELECT 'A1 GUARD TRIGGERS' AS section, COUNT(*) AS triggers_installed
FROM information_schema.triggers
WHERE trigger_schema = 'football_bitemporal';

-- try every forbidden operation; errors are captured so the script still exits 0

CALL sp_a1_negative_tests();

SELECT 'A1 NEGATIVE TESTS' AS section, test_name, outcome, error_text
FROM a1_negative_results
ORDER BY test_id;

-- demo of the four procedures on P6 (no current contract), rolled back after

SET @sim_now := '2026-10-20 09:00:00';
START TRANSACTION;

CALL sp_assert_fact(6, 1, 30, 90000.00, 'permanent', '2026-07-01');
SELECT 'A1 ASSERT' AS step, version_id, player_id, club_id, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM contract_version
WHERE player_id = 6 AND tx_from >= '2026-10-20 00:00:00'
ORDER BY version_id;

SET @sim_now := '2026-10-21 10:00:00';
CALL sp_correct_fact(6, 1, 95000.00);
SELECT 'A1 CORRECT SALARY' AS step, version_id, salary_eur, valid_from, valid_to,
       tx_from, tx_to
FROM contract_version
WHERE player_id = 6 AND tx_from >= '2026-10-20 00:00:00'
ORDER BY version_id;

SET @sim_now := '2026-10-22 11:00:00';
CALL sp_retract_fact(6, 1);
SELECT 'A1 RETRACT' AS step, COUNT(*) AS current_open_contracts
FROM contract_version
WHERE player_id = 6
  AND tx_to = '9999-12-31 23:59:59.999999'
  AND valid_to = '9999-12-31';

SET @sim_now := '2026-10-23 12:00:00';
CALL sp_assert_fact(6, 1, 30, 90000.00, 'permanent', '2026-07-01');
SET @sim_now := '2026-10-24 13:00:00';
CALL sp_end_fact(6, 1, '2026-12-31');

SELECT 'A1 END' AS step, version_id, player_id, club_id, salary_eur,
       valid_from, valid_to, tx_from, tx_to
FROM contract_version
WHERE player_id = 6 AND tx_from >= '2026-10-20 00:00:00'
ORDER BY version_id;

SELECT 'A1 DEMO TX REGISTRY' AS section, tx_id, tx_time, author, reason
FROM tx_registry
WHERE tx_time >= '2026-10-20 00:00:00'
ORDER BY tx_id;

ROLLBACK;
SET @sim_now := NULL;

SELECT 'A1 AFTER ROLLBACK' AS section,
       COUNT(*) AS demo_rows_left,
       (SELECT COUNT(*) FROM v_integrity_violations) AS violations
FROM contract_version
WHERE player_id = 6 AND tx_from >= '2026-10-20 00:00:00';
