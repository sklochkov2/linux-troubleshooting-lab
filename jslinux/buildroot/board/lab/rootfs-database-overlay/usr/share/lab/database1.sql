CREATE DATABASE IF NOT EXISTS lab;
USE lab;

CREATE TABLE events (
    id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    lookup_key VARCHAR(32) NOT NULL,
    created_at DATETIME NOT NULL,
    payload VARCHAR(160) NOT NULL
) ENGINE=InnoDB;

CREATE TEMPORARY TABLE digits (n TINYINT UNSIGNED NOT NULL);
INSERT INTO digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

INSERT INTO events (id, lookup_key, created_at, payload)
SELECT
    sequence_number,
    IF(
        sequence_number = 77777,
        'needle',
        CONCAT('key-', LPAD(sequence_number, 5, '0'))
    ),
    TIMESTAMP('2025-01-01 00:00:00') +
        INTERVAL MOD(sequence_number, 31536000) SECOND,
    RPAD(CONCAT('event-', sequence_number, '-'), 160, 'x')
FROM (
    SELECT
        a.n +
        b.n * 10 +
        c.n * 100 +
        d.n * 1000 +
        e.n * 10000 AS sequence_number
    FROM digits AS a
    CROSS JOIN digits AS b
    CROSS JOIN digits AS c
    CROSS JOIN digits AS d
    CROSS JOIN digits AS e
) AS generated;

CREATE USER IF NOT EXISTS 'lab'@'localhost' IDENTIFIED BY '';
GRANT SELECT ON lab.* TO 'lab'@'localhost';
FLUSH PRIVILEGES;
ANALYZE TABLE events;
