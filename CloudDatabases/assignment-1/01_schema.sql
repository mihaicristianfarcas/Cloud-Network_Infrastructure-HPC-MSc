-- author: Mihai-Cristian Farcaș
-- schema for the bitemporal football database (MariaDB 11.8)
-- safe to re-run: drops the database first

DROP DATABASE IF EXISTS football_bitemporal;
CREATE DATABASE football_bitemporal
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE football_bitemporal;

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- non-temporal anchors and reference tables

CREATE TABLE agent (
    agent_id     INT          NOT NULL AUTO_INCREMENT,
    full_name    VARCHAR(80)  NOT NULL,
    agency       VARCHAR(80)  NOT NULL,
    PRIMARY KEY (agent_id)
) ENGINE=InnoDB;

CREATE TABLE club (
    club_id       INT          NOT NULL AUTO_INCREMENT,
    name          VARCHAR(80)  NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    stadium       VARCHAR(80)  NOT NULL,
    founded_year  SMALLINT     NOT NULL,
    PRIMARY KEY (club_id),
    UNIQUE KEY uq_club_name (name),
    CHECK (founded_year BETWEEN 1850 AND 2100)
) ENGINE=InnoDB;

CREATE TABLE coach (
    coach_id     INT          NOT NULL AUTO_INCREMENT,
    full_name    VARCHAR(80)  NOT NULL,
    nationality  VARCHAR(40)  NOT NULL,
    PRIMARY KEY (coach_id)
) ENGINE=InnoDB;

CREATE TABLE player (
    player_id    INT          NOT NULL AUTO_INCREMENT,
    full_name    VARCHAR(80)  NOT NULL,
    birth_date   DATE         NOT NULL,
    nationality  VARCHAR(40)  NOT NULL,
    position     VARCHAR(20)  NOT NULL,
    agent_id     INT          NOT NULL,
    PRIMARY KEY (player_id),
    CONSTRAINT fk_player_agent FOREIGN KEY (agent_id) REFERENCES agent (agent_id),
    CHECK (position IN ('GK','DF','MF','FW')),
    CHECK (birth_date < '2010-01-01')
) ENGINE=InnoDB;

-- named periods, half-open: end_date is the day after the season ends
CREATE TABLE season (
    season_id    INT          NOT NULL AUTO_INCREMENT,
    name         VARCHAR(20)  NOT NULL,
    start_date   DATE         NOT NULL,
    end_date     DATE         NOT NULL,
    PRIMARY KEY (season_id),
    UNIQUE KEY uq_season_name (name),
    CHECK (start_date < end_date)
) ENGINE=InnoDB;

-- months for Q7, so months without contracts still show up
CREATE TABLE calendar_month (
    month_start  DATE  NOT NULL,
    PRIMARY KEY (month_start)
) ENGINE=InnoDB;

INSERT INTO calendar_month (month_start) VALUES
  ('2025-07-01'), ('2025-08-01'), ('2025-09-01'), ('2025-10-01'),
  ('2025-11-01'), ('2025-12-01'), ('2026-01-01'), ('2026-02-01'),
  ('2026-03-01'), ('2026-04-01'), ('2026-05-01'), ('2026-06-01'),
  ('2026-07-01'), ('2026-08-01'), ('2026-09-01'), ('2026-10-01'),
  ('2026-11-01'), ('2026-12-01'), ('2027-01-01'), ('2027-02-01'),
  ('2027-03-01'), ('2027-04-01'), ('2027-05-01'), ('2027-06-01');

-- one row per logical change (rule 7)

CREATE TABLE tx_registry (
    tx_id     BIGINT       NOT NULL AUTO_INCREMENT,
    tx_time   DATETIME(6)  NOT NULL,
    author    VARCHAR(60)  NOT NULL,
    reason    VARCHAR(255) NOT NULL,
    PRIMARY KEY (tx_id),
    KEY ix_tx_time (tx_time)
) ENGINE=InnoDB;

-- hand-written index of the E1-E9 events; the version rows are the real data
CREATE TABLE story_event (
    event_id     BIGINT       NOT NULL AUTO_INCREMENT,
    tx_id        BIGINT       NOT NULL,
    event_code   CHAR(2)      NOT NULL,
    table_name   VARCHAR(80)  NOT NULL,
    business_key VARCHAR(40)  NOT NULL,
    valid_date   DATE         NULL,
    old_value    VARCHAR(160) NULL,
    new_value    VARCHAR(160) NULL,
    note         VARCHAR(255) NOT NULL,
    PRIMARY KEY (event_id),
    CONSTRAINT fk_story_tx FOREIGN KEY (tx_id) REFERENCES tx_registry (tx_id),
    CHECK (event_code IN ('E1','E2','E3','E4','E5','E6','E7','E8','E9'))
) ENGINE=InnoDB;

-- bitemporal version tables (rules 1-6)

-- club licence: the temporal parent for I2
CREATE TABLE club_license_version (
    version_id      BIGINT       NOT NULL AUTO_INCREMENT,
    club_id         INT          NOT NULL,
    league_name     VARCHAR(40)  NOT NULL,
    license_status  VARCHAR(20)  NOT NULL,
    valid_from      DATE         NOT NULL,
    valid_to        DATE         NOT NULL DEFAULT '9999-12-31',
    tx_from         DATETIME(6)  NOT NULL,
    tx_to           DATETIME(6)  NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id           BIGINT       NOT NULL,
    PRIMARY KEY (version_id),
    CONSTRAINT fk_licence_club FOREIGN KEY (club_id) REFERENCES club (club_id),
    CONSTRAINT fk_licence_tx   FOREIGN KEY (tx_id)   REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    CHECK (license_status IN ('full','conditional','suspended'))
) ENGINE=InnoDB;

-- main relationship: player <-> club
CREATE TABLE contract_version (
    version_id    BIGINT        NOT NULL AUTO_INCREMENT,
    player_id     INT           NOT NULL,
    club_id       INT           NOT NULL,
    shirt_number  TINYINT       NOT NULL,
    salary_eur    DECIMAL(12,2) NOT NULL,
    contract_type VARCHAR(20)   NOT NULL,
    valid_from    DATE          NOT NULL,
    valid_to      DATE          NOT NULL DEFAULT '9999-12-31',
    tx_from       DATETIME(6)   NOT NULL,
    tx_to         DATETIME(6)   NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id         BIGINT        NOT NULL,
    PRIMARY KEY (version_id),
    CONSTRAINT fk_contract_player FOREIGN KEY (player_id) REFERENCES player (player_id),
    CONSTRAINT fk_contract_club   FOREIGN KEY (club_id)   REFERENCES club (club_id),
    CONSTRAINT fk_contract_tx     FOREIGN KEY (tx_id)     REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    CHECK (salary_eur >= 0),
    CHECK (shirt_number BETWEEN 1 AND 99),
    CHECK (contract_type IN ('permanent','loan')),
    KEY ix_contract_asof (player_id, tx_to, valid_from),
    KEY ix_contract_club_asof (club_id, tx_to, valid_from),
    KEY ix_contract_tx (tx_id)
) ENGINE=InnoDB;

-- role: one head coach per club at a time (I3)
CREATE TABLE coach_assignment_version (
    version_id  BIGINT       NOT NULL AUTO_INCREMENT,
    coach_id    INT          NOT NULL,
    club_id     INT          NOT NULL,
    role_title  VARCHAR(30)  NOT NULL DEFAULT 'Head coach',
    valid_from  DATE         NOT NULL,
    valid_to    DATE         NOT NULL DEFAULT '9999-12-31',
    tx_from     DATETIME(6)  NOT NULL,
    tx_to       DATETIME(6)  NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id       BIGINT       NOT NULL,
    PRIMARY KEY (version_id),
    CONSTRAINT fk_coach_assign_coach FOREIGN KEY (coach_id) REFERENCES coach (coach_id),
    CONSTRAINT fk_coach_assign_club  FOREIGN KEY (club_id)  REFERENCES club (club_id),
    CONSTRAINT fk_coach_assign_tx    FOREIGN KEY (tx_id)    REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    CHECK (role_title = 'Head coach'),
    KEY ix_coach_asof (club_id, tx_to, valid_from),
    KEY ix_coach_tx (tx_id)
) ENGINE=InnoDB;

-- changing numeric attribute: market value
CREATE TABLE player_value_version (
    version_id       BIGINT        NOT NULL AUTO_INCREMENT,
    player_id        INT           NOT NULL,
    market_value_eur DECIMAL(14,2) NOT NULL,
    valid_from       DATE          NOT NULL,
    valid_to         DATE          NOT NULL DEFAULT '9999-12-31',
    tx_from          DATETIME(6)   NOT NULL,
    tx_to            DATETIME(6)   NOT NULL DEFAULT '9999-12-31 23:59:59.999999',
    tx_id            BIGINT        NOT NULL,
    PRIMARY KEY (version_id),
    CONSTRAINT fk_value_player FOREIGN KEY (player_id) REFERENCES player (player_id),
    CONSTRAINT fk_value_tx     FOREIGN KEY (tx_id)     REFERENCES tx_registry (tx_id),
    CHECK (valid_from < valid_to),
    CHECK (tx_from < tx_to),
    CHECK (market_value_eur >= 0),
    KEY ix_value_asof (player_id, tx_to, valid_from),
    KEY ix_value_tx (tx_id)
) ENGINE=InnoDB;

-- one-row parameter table, since views can't take arguments

CREATE TABLE query_params (
    param_id      TINYINT      NOT NULL DEFAULT 1,
    valid_at      DATE         NOT NULL,
    known_at      DATETIME(6)  NOT NULL,
    period_start  DATE         NOT NULL,
    period_end    DATE         NOT NULL,
    subject_id    INT          NOT NULL,
    PRIMARY KEY (param_id),
    CHECK (param_id = 1),
    CHECK (period_start < period_end)
) ENGINE=InnoDB;

INSERT INTO query_params (param_id, valid_at, known_at, period_start, period_end, subject_id)
VALUES (1, '2026-10-15', '2026-10-15 23:59:59.999999', '2025-07-01', '2026-07-01', 1);
