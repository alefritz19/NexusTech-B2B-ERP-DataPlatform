-- ==============================================================================
-- 01_DWH_TRANSFORMATION / 01_Wie_man_Fakten_und_Dimensionen_baut.sql
-- Übung: Transformation von 3NF-Operativdaten in ein Kimball-Sternschema (Star Schema)
-- Datenbank: NexusTech_ERP
-- ==============================================================================

USE NexusTech_ERP;
GO

-- ------------------------------------------------------------------------------
-- 1. SCHRITT: FAKTENTABELLE ERSTELLEN (Belegkopf + Zeilen + Logistik zusammenführen)
-- ------------------------------------------------------------------------------
-- In operativen ERP-Systemen liegen Belegkopf (Bestellungen) und Zeilen (Positionen)
-- getrennt vor. Für ein DWH führen wir sie zu einer granularen Faktentabelle zusammen.
-- ------------------------------------------------------------------------------

CREATE OR ALTER VIEW dwh.vw_fct_bestellungen AS
SELECT 
    pos.PositionID,
    pos.BestellID,
    b.Bestellnummer,
    b.KundeID,
    b.VertriebsID,
    pos.ProduktID,
    
    -- Datumsschlüssel für Star Schema Verknüpfung
    b.Bestelldatum,
    CAST(CONVERT(VARCHAR(8), b.Bestelldatum, 112) AS INT) AS BestelldatumKey,
    
    -- Mengengerüst & Preise
    pos.Menge,
    pos.Einzelpreis,
    pos.RabattBetrag,
    
    -- Berechnete Finanz-Kennzahlen
    CAST((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag AS DECIMAL(12,2)) AS UmsatzNetto,
    CAST(pos.Menge * p.Einkaufspreis_EUR AS DECIMAL(12,2)) AS WareneinsatzNetto,
    CAST(((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag) - (pos.Menge * p.Einkaufspreis_EUR) AS DECIMAL(12,2)) AS DeckungsbeitragNetto,
    
    -- Margenberechnung mit Absicherung gegen Division durch 0
    CAST(ROUND(
        (((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag) - (pos.Menge * p.Einkaufspreis_EUR)) / 
        NULLIF((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag, 0), 4) AS DECIMAL(6,4)) AS DeckungsbeitragMarge,
        
    -- Zahlungs- und Bestellstatus
    b.Zahlungsart,
    b.Bestellstatus,
    
    -- Logistik-Informationen aus der Tabelle Lieferungen
    l.Versandart,
    l.Versanddatum,
    l.Lieferdatum,
    l.Lieferstatus,
    DATEDIFF(DAY, b.Bestelldatum, l.Lieferdatum) AS TatsaechlicheLieferdauerTage,
    l.Frachtkosten_EUR
FROM dbo.Bestellpositionen pos
INNER JOIN dbo.Bestellungen b 
    ON pos.BestellID = b.BestellID
INNER JOIN dbo.Produkte p 
    ON pos.ProduktID = p.ProduktID
LEFT JOIN dbo.Lieferungen l 
    ON b.BestellID = l.BestellID;
GO

-- ------------------------------------------------------------------------------
-- 2. SCHRITT: DIMENSIONEN DENORMALISIEREN (Snowflake -> Star Schema)
-- ------------------------------------------------------------------------------
-- Im OLTP sind Produkte, Kategorien und Hersteller auf 3 Tabellen aufgeteilt.
-- Im DWH denormalisieren wir alles in EINE flache Dimension dim_produkte.
-- ------------------------------------------------------------------------------

CREATE OR ALTER VIEW dwh.vw_dim_produkte AS
SELECT 
    p.ProduktID,
    p.EAN,
    p.ProduktName,
    p.Einkaufspreis_EUR,
    p.Listenpreis_EUR,
    p.IstAktiv,
    
    -- Aus Tabelle dbo.Kategorien
    k.KategorieID,
    k.KategorieName,
    k.Warenbereich,
    
    -- Aus Tabelle dbo.Hersteller
    h.HerstellerID,
    h.HerstellerName,
    h.Herkunftsland AS HerstellerLand,
    h.Partnerschaftsstatus
FROM dbo.Produkte p
INNER JOIN dbo.Kategorien k 
    ON p.KategorieID = k.KategorieID
INNER JOIN dbo.Hersteller h 
    ON p.HerstellerID = h.HerstellerID;
GO

CREATE OR ALTER VIEW dwh.vw_dim_kunden AS
SELECT 
    k.KundeID,
    k.Kundennummer,
    k.Firmenname,
    k.Rechtsform,
    k.Branche,
    k.Kundensegment,
    k.Stadt,
    k.Bundesland_Kanton,
    k.Land,
    k.PLZ,
    k.Bonitaetsklasse,
    k.ZahlungszielTage,
    k.ErstelltAm AS KundeSeitDatum,
    DATEDIFF(YEAR, k.ErstelltAm, '2026-01-01') AS KundenalterJahre
FROM dbo.Kunden k;
GO

CREATE OR ALTER VIEW dwh.vw_dim_vertrieb AS
SELECT 
    v.VertriebsID,
    v.MitarbeiterName,
    v.Vertriebsregion,
    v.Standort,
    v.Senioritaet,
    v.Zielumsatz_Jahr_EUR,
    CAST(v.Zielumsatz_Jahr_EUR / 4.0 AS DECIMAL(12,2)) AS Zielumsatz_Quartal_EUR
FROM dbo.Vertriebsmitarbeiter v;
GO

-- ------------------------------------------------------------------------------
-- 3. SCHRITT: VOLLSTÄNDIGE KALENDERTABELLE GENERIEREN (dim_datum)
-- ------------------------------------------------------------------------------
IF OBJECT_ID('dwh.dim_datum', 'U') IS NOT NULL
    DROP TABLE dwh.dim_datum;
GO

CREATE TABLE dwh.dim_datum (
    DatumKey INT PRIMARY KEY,
    Datum DATE NOT NULL,
    Jahr INT NOT NULL,
    Quartal VARCHAR(2) NOT NULL,
    JahrQuartal VARCHAR(7) NOT NULL,
    MonatNr INT NOT NULL,
    MonatName VARCHAR(20) NOT NULL,
    MonatKurz VARCHAR(3) NOT NULL,
    JahrMonat VARCHAR(7) NOT NULL,
    Kalenderwoche INT NOT NULL,
    TagImMonat INT NOT NULL,
    WochentagNr INT NOT NULL,
    WochentagName VARCHAR(20) NOT NULL,
    IstWerktag BIT NOT NULL,
    IstWochenende BIT NOT NULL
);
GO

SET DATEFIRST 1; -- Montag = 1

WITH DatumCTE AS (
    SELECT CAST('2023-01-01' AS DATE) AS Datum
    UNION ALL
    SELECT DATEADD(DAY, 1, Datum)
    FROM DatumCTE
    WHERE Datum < '2025-12-31'
)
INSERT INTO dwh.dim_datum
SELECT 
    CAST(CONVERT(VARCHAR(8), Datum, 112) AS INT) AS DatumKey,
    Datum,
    YEAR(Datum) AS Jahr,
    'Q' + CAST(DATEPART(QUARTER, Datum) AS VARCHAR(1)) AS Quartal,
    CAST(YEAR(Datum) AS VARCHAR(4)) + '-Q' + CAST(DATEPART(QUARTER, Datum) AS VARCHAR(1)) AS JahrQuartal,
    MONTH(Datum) AS MonatNr,
    CASE MONTH(Datum)
        WHEN 1 THEN 'Januar'   WHEN 2 THEN 'Februar'   WHEN 3 THEN 'März'
        WHEN 4 THEN 'April'    WHEN 5 THEN 'Mai'       WHEN 6 THEN 'Juni'
        WHEN 7 THEN 'Juli'     WHEN 8 THEN 'August'    WHEN 9 THEN 'September'
        WHEN 10 THEN 'Oktober' WHEN 11 THEN 'November' ELSE 'Dezember'
    END AS MonatName,
    CASE MONTH(Datum)
        WHEN 1 THEN 'Jan' WHEN 2 THEN 'Feb' WHEN 3 THEN 'Mrz'
        WHEN 4 THEN 'Apr' WHEN 5 THEN 'Mai' WHEN 6 THEN 'Jun'
        WHEN 7 THEN 'Jul' WHEN 8 THEN 'Aug' WHEN 9 THEN 'Sep'
        WHEN 10 THEN 'Okt' WHEN 11 THEN 'Nov' ELSE 'Dez'
    END AS MonatKurz,
    LEFT(CONVERT(VARCHAR(10), Datum, 120), 7) AS JahrMonat,
    DATEPART(ISO_WEEK, Datum) AS Kalenderwoche,
    DAY(Datum) AS TagImMonat,
    DATEPART(WEEKDAY, Datum) AS WochentagNr,
    CASE DATEPART(WEEKDAY, Datum)
        WHEN 1 THEN 'Montag' WHEN 2 THEN 'Dienstag' WHEN 3 THEN 'Mittwoch'
        WHEN 4 THEN 'Donnerstag' WHEN 5 THEN 'Freitag' WHEN 6 THEN 'Samstag' ELSE 'Sonntag'
    END AS WochentagName,
    CASE WHEN DATEPART(WEEKDAY, Datum) IN (6, 7) THEN 0 ELSE 1 END AS IstWerktag,
    CASE WHEN DATEPART(WEEKDAY, Datum) IN (6, 7) THEN 1 ELSE 0 END AS IstWochenende
FROM DatumCTE
OPTION (MAXRECURSION 1200);
GO

-- ------------------------------------------------------------------------------
-- 4. ERFOLGSKONTROLLE
-- ------------------------------------------------------------------------------
SELECT 'dwh.vw_fct_bestellungen' AS ViewName, COUNT(*) AS Zeilen FROM dwh.vw_fct_bestellungen
UNION ALL SELECT 'dwh.vw_dim_produkte', COUNT(*) FROM dwh.vw_dim_produkte
UNION ALL SELECT 'dwh.vw_dim_kunden', COUNT(*) FROM dwh.vw_dim_kunden
UNION ALL SELECT 'dwh.vw_dim_vertrieb', COUNT(*) FROM dwh.vw_dim_vertrieb
UNION ALL SELECT 'dwh.dim_datum', COUNT(*) FROM dwh.dim_datum;
GO
