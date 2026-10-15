-- ==============================================================================
-- 01_DWH_TRANSFORMATION / 01_Datenexploration.sql
-- Schritt 1-2: Rohdaten verstehen, BEVOR man JOINs schreibt
-- Datenbank: NexusTech_ERP (SQL Server 2022, .\SQLEXPRESS)
-- ==============================================================================
-- Grundregel: Erst die Tabelle ansehen (SELECT TOP / DISTINCT),
--             dann die Abfrage schreiben.
-- ==============================================================================

USE NexusTech_ERP;
GO

-- ------------------------------------------------------------------------------
-- 1.1 Belegkopf (Header): 1 Zeile = 1 Auftrag
-- ------------------------------------------------------------------------------
SELECT TOP 5
    BestellID,
    Bestellnummer,
    KundeID,
    Bestelldatum,
    Bestellstatus
FROM dbo.Bestellungen;

-- ------------------------------------------------------------------------------
-- 1.2 Belegpositionen (Lines): 1 Zeile = 1 Artikel im Auftrag
--     -> BestellID 100000 erscheint hier 3x (1:N Beziehung!)
-- ------------------------------------------------------------------------------
SELECT TOP 10
    PositionID,
    BestellID,
    ProduktID,
    Menge,
    Einzelpreis,
    RabattBetrag
FROM dbo.Bestellpositionen;

-- ------------------------------------------------------------------------------
-- 1.3 Erste "Hochzeit": Kopf + Positionen über BestellID
--     + erste berechnete Kennzahl (Nettoumsatz)
-- ------------------------------------------------------------------------------
SELECT TOP 15
    pos.PositionID,
    pos.ProduktID,
    pos.Menge,
    pos.Einzelpreis,
    pos.RabattBetrag,
    b.BestellID,
    b.Bestellnummer,
    b.Bestelldatum,
    b.KundeID,
    b.VertriebsID,
    b.Bestellstatus,
    CAST((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag AS DECIMAL(18, 2)) AS Nettoumsatz
FROM dbo.Bestellpositionen AS pos
INNER JOIN dbo.Bestellungen AS b
    ON pos.BestellID = b.BestellID;

-- ------------------------------------------------------------------------------
-- 1.4 Welche Statuswerte gibt es überhaupt? (DISTINCT = Aufklärungswerkzeug)
-- ------------------------------------------------------------------------------
SELECT DISTINCT Lieferstatus  FROM dbo.Lieferungen;
SELECT DISTINCT Bestellstatus FROM dbo.Bestellungen;

-- ------------------------------------------------------------------------------
-- 1.5 Wie passen Bestell- und Lieferstatus zusammen?
--     Ergebnis (Aufträge):
--       Abgeschlossen  | Zugestellt     | 37.067
--       Abgeschlossen  | Retoure        |  1.333
--       In Bearbeitung | In Zustellung  |    800
--       Storniert      | Storniert      |    800
-- ------------------------------------------------------------------------------
SELECT b.Bestellstatus, l.Lieferstatus, COUNT(*) AS Anzahl
FROM dbo.Bestellungen AS b
LEFT JOIN dbo.Lieferungen AS l ON b.BestellID = l.BestellID
GROUP BY b.Bestellstatus, l.Lieferstatus
ORDER BY b.Bestellstatus, l.Lieferstatus;

-- ------------------------------------------------------------------------------
-- 1.6 CAST / DECIMAL verstehen (Mini-Übung)
--     DECIMAL(18, 2) = max. 18 Ziffern, davon 2 nach dem Komma (Euro + Cent)
-- ------------------------------------------------------------------------------
SELECT
    10.0 / 3                         AS ohne_cast,
    CAST(10.0 / 3 AS DECIMAL(18, 2)) AS mit_cast_2,
    CAST(10.0 / 3 AS DECIMAL(18, 4)) AS mit_cast_4,
    CAST(10.0 / 3 AS DECIMAL(18, 0)) AS mit_cast_0;
GO
