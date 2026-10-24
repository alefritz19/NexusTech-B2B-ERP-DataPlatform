-- ==============================================================================
-- 01_DWH_TRANSFORMATION / 03_DWH_Views_erstellen.sql
-- Schritt 8: Geprüfte Logik dauerhaft im Schema dwh speichern
-- Ergebnis: 4 Views + 1 physische Kalendertabelle -> Quelle für CSV & Power BI
-- ==============================================================================

USE NexusTech_ERP;
GO

-- 1. Schema dwh (Trennung: dbo = ERP-Rohdaten, dwh = Analyse-Schicht)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dwh')
    EXEC('CREATE SCHEMA dwh');
GO

-- ------------------------------------------------------------------------------
-- 2. FAKTENTABELLE: dwh.vw_fct_bestellungen  (120.000 Zeilen)
-- ------------------------------------------------------------------------------
CREATE OR ALTER VIEW dwh.vw_fct_bestellungen AS
SELECT
    pos.PositionID,
    pos.BestellID,
    b.Bestellnummer,
    b.Bestelldatum,
    CAST(FORMAT(b.Bestelldatum, 'yyyyMMdd') AS INT) AS DatumID,   -- Schlüssel zu dim_datum
    b.KundeID,
    b.VertriebsID,
    pos.ProduktID,
    pos.Menge,
    pos.Einzelpreis,
    pos.RabattBetrag,
    prod.Einkaufspreis_EUR,
    CAST((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag AS DECIMAL(18, 2)) AS Nettoumsatz,
    CAST(pos.Menge * prod.Einkaufspreis_EUR AS DECIMAL(18, 2))               AS Gesamtkosten,
    CAST(((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag)
         - (pos.Menge * prod.Einkaufspreis_EUR) AS DECIMAL(18, 2))           AS Deckungsbeitrag,
    l.Versandart,
    l.Lieferdatum,
    l.Lieferstatus,
    DATEDIFF(day, b.Bestelldatum, l.Lieferdatum) AS Lieferzeit_Tage,
    CASE WHEN l.Lieferstatus = 'Zugestellt' THEN 1 ELSE 0 END AS IstUmsatzrelevant
FROM dbo.Bestellpositionen AS pos
INNER JOIN dbo.Bestellungen AS b    ON pos.BestellID = b.BestellID
INNER JOIN dbo.Produkte     AS prod ON pos.ProduktID = prod.ProduktID
LEFT  JOIN dbo.Lieferungen  AS l    ON b.BestellID   = l.BestellID;
GO

-- ------------------------------------------------------------------------------
-- 3. DIMENSION: dwh.vw_dim_produkte  (120 Zeilen, Produkte + Kategorien + Hersteller)
-- ------------------------------------------------------------------------------
CREATE OR ALTER VIEW dwh.vw_dim_produkte AS
SELECT
    p.ProduktID,
    p.ProduktName,
    p.EAN,
    p.Einkaufspreis_EUR,
    p.Listenpreis_EUR,
    p.IstAktiv,
    k.KategorieName,
    k.Warenbereich,
    h.HerstellerName,
    h.Herkunftsland,
    h.Partnerschaftsstatus
FROM dbo.Produkte AS p
INNER JOIN dbo.Kategorien AS k ON p.KategorieID  = k.KategorieID
INNER JOIN dbo.Hersteller AS h ON p.HerstellerID = h.HerstellerID;
GO

-- ------------------------------------------------------------------------------
-- 4. DIMENSION: dwh.vw_dim_kunden  (2.500 Zeilen)
-- ------------------------------------------------------------------------------
CREATE OR ALTER VIEW dwh.vw_dim_kunden AS
SELECT
    KundeID, Kundennummer, Firmenname, Rechtsform, Branche, Kundensegment,
    Stadt, Bundesland_Kanton, Land, PLZ, Bonitaetsklasse, ZahlungszielTage, ErstelltAm
FROM dbo.Kunden;
GO

-- ------------------------------------------------------------------------------
-- 5. DIMENSION: dwh.vw_dim_vertrieb  (12 Zeilen)
-- ------------------------------------------------------------------------------
CREATE OR ALTER VIEW dwh.vw_dim_vertrieb AS
SELECT
    VertriebsID, MitarbeiterName, Vertriebsregion, Standort, Senioritaet, Zielumsatz_Jahr_EUR
FROM dbo.Vertriebsmitarbeiter;
GO

-- ------------------------------------------------------------------------------
-- 6. KALENDER: dwh.dim_datum  (1.096 Zeilen, physische Tabelle)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dwh.dim_datum;
GO

SET LANGUAGE German;
SET DATEFIRST 1;

DECLARE @Start DATE = CAST('20230101' AS DATE);
DECLARE @Ende  DATE = CAST('20251231' AS DATE);

WITH Kalender AS (
    SELECT @Start AS Datum
    UNION ALL
    SELECT DATEADD(day, 1, Datum)
    FROM Kalender
    WHERE Datum < @Ende
)
SELECT
    CAST(FORMAT(Datum, 'yyyyMMdd') AS INT) AS DatumID,
    Datum,
    YEAR(Datum)                            AS Jahr,
    DATEPART(quarter, Datum)               AS Quartal,
    CONCAT('Q', DATEPART(quarter, Datum))  AS Quartal_Name,
    MONTH(Datum)                           AS Monat,
    DATENAME(month, Datum)                 AS Monatsname,
    FORMAT(Datum, 'yyyy-MM')               AS Jahr_Monat,
    DATEPART(iso_week, Datum)              AS Kalenderwoche,
    DATEPART(weekday, Datum)               AS Wochentag_Nr,
    DATENAME(weekday, Datum)               AS Wochentag,
    CASE WHEN DATEPART(weekday, Datum) IN (6, 7) THEN 1 ELSE 0 END AS IstWochenende
INTO dwh.dim_datum
FROM Kalender
OPTION (MAXRECURSION 2000);
GO

-- ------------------------------------------------------------------------------
-- 7. ERFOLGSKONTROLLE
-- Erwartet: 120000 | 120 | 2500 | 12 | 1096
-- ------------------------------------------------------------------------------
SELECT 'dwh.vw_fct_bestellungen' AS Objekt, COUNT(*) AS Zeilen FROM dwh.vw_fct_bestellungen
UNION ALL SELECT 'dwh.vw_dim_produkte', COUNT(*) FROM dwh.vw_dim_produkte
UNION ALL SELECT 'dwh.vw_dim_kunden',   COUNT(*) FROM dwh.vw_dim_kunden
UNION ALL SELECT 'dwh.vw_dim_vertrieb', COUNT(*) FROM dwh.vw_dim_vertrieb
UNION ALL SELECT 'dwh.dim_datum',       COUNT(*) FROM dwh.dim_datum;
GO
