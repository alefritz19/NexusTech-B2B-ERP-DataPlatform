-- ==============================================================================
-- 01_DWH_TRANSFORMATION / 02_Sandbox_mit_Temp_Tabellen.sql
-- Schritt 3-7: Faktentabelle + Dimensionen in temporären #Tabellen entwickeln und prüfen
-- ==============================================================================
-- #Tabelle = lebt nur in DIESEM Abfragefenster (tempdb).
-- Fenster schließen -> Tabelle weg. Ideal zum Experimentieren.
-- ==============================================================================

USE NexusTech_ERP;
GO

-- ==============================================================================
-- SCHRITT 3: FAKTENTABELLE (Granularität = 1 verkaufte Auftragsposition)
-- ==============================================================================
DROP TABLE IF EXISTS #temp_fct_bestellungen;

SELECT
    -- Schlüssel für das Sternschema
    pos.PositionID,
    pos.BestellID,
    b.Bestellnummer,
    b.Bestelldatum,
    b.KundeID,
    b.VertriebsID,
    pos.ProduktID,

    -- Mengen & Preise
    pos.Menge,
    pos.Einzelpreis,
    pos.RabattBetrag,
    prod.Einkaufspreis_EUR,

    -- KENNZAHL 1: Nettoumsatz = (Menge * Preis) - Rabatt
    CAST((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag AS DECIMAL(18, 2)) AS Nettoumsatz,

    -- KENNZAHL 2: Gesamtkosten (Wareneinsatz) = Menge * Einkaufspreis
    CAST(pos.Menge * prod.Einkaufspreis_EUR AS DECIMAL(18, 2)) AS Gesamtkosten,

    -- KENNZAHL 3: Deckungsbeitrag = Nettoumsatz - Gesamtkosten
    CAST(((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag)
         - (pos.Menge * prod.Einkaufspreis_EUR) AS DECIMAL(18, 2)) AS Deckungsbeitrag,

    -- Logistik
    l.Versandart,
    l.Lieferdatum,
    l.Lieferstatus,

    -- KENNZAHL 4: Lieferzeit in Tagen
    DATEDIFF(day, b.Bestelldatum, l.Lieferdatum) AS Lieferzeit_Tage

INTO #temp_fct_bestellungen

FROM dbo.Bestellpositionen AS pos
INNER JOIN dbo.Bestellungen AS b    ON pos.BestellID = b.BestellID      -- Kopf: immer vorhanden
INNER JOIN dbo.Produkte     AS prod ON pos.ProduktID = prod.ProduktID   -- Produkt: immer vorhanden
LEFT  JOIN dbo.Lieferungen  AS l    ON b.BestellID   = l.BestellID;     -- Lieferung: evtl. fehlend -> LEFT!

SELECT TOP 10
    PositionID, Bestellnummer, Bestelldatum,
    Nettoumsatz, Gesamtkosten, Deckungsbeitrag,
    Versandart, Lieferzeit_Tage
FROM #temp_fct_bestellungen;

-- ==============================================================================
-- SCHRITT 4: DATENABGLEICH (vorher / nachher)
-- Erwartet: 120.000 = 120.000 | ohne_Lieferung = 2.400 (= stornierte Positionen)
-- ==============================================================================
SELECT
    (SELECT COUNT(*) FROM dbo.Bestellpositionen)  AS Positionen_Quelle,
    (SELECT COUNT(*) FROM #temp_fct_bestellungen) AS Positionen_Fakt,
    (SELECT COUNT(*) FROM #temp_fct_bestellungen
      WHERE Lieferdatum IS NULL)                  AS ohne_Lieferung;

-- Woher kommen die 2.400 NULLs?
-- Ergebnis: Zugestellt 111.201 | Retoure 3.999 | In Zustellung 2.400 | Storniert 2.400 (alle NULL)
SELECT
    Lieferstatus,
    COUNT(*) AS Anzahl_Positionen,
    SUM(CASE WHEN Lieferdatum IS NULL THEN 1 ELSE 0 END) AS ohne_Lieferdatum
FROM #temp_fct_bestellungen
GROUP BY Lieferstatus
ORDER BY Anzahl_Positionen DESC;

-- ==============================================================================
-- SCHRITT 5: BUSINESS-FLAG IstUmsatzrelevant
-- WICHTIG: ALTER und UPDATE in getrennten Batches ausführen (GO dazwischen),
--          sonst Fehler "Ungültiger Spaltenname".
-- ==============================================================================
ALTER TABLE #temp_fct_bestellungen
ADD IstUmsatzrelevant TINYINT;
GO

UPDATE #temp_fct_bestellungen
SET IstUmsatzrelevant = CASE
                            WHEN Lieferstatus = 'Zugestellt' THEN 1
                            ELSE 0
                        END;

SELECT Lieferstatus, IstUmsatzrelevant, COUNT(*) AS Anzahl
FROM #temp_fct_bestellungen
GROUP BY Lieferstatus, IstUmsatzrelevant
ORDER BY Lieferstatus;

-- Finanzieller Effekt des Flags
-- Ergebnis: 390.285.124,97 | 363.823.132,90 | 26.461.992,07
SELECT
    CAST(SUM(Nettoumsatz) AS DECIMAL(18, 2))                                          AS Umsatz_BRUTTO_ALLE,
    CAST(SUM(CASE WHEN IstUmsatzrelevant = 1 THEN Nettoumsatz END) AS DECIMAL(18, 2)) AS Umsatz_REAL_NETTO,
    CAST(SUM(CASE WHEN IstUmsatzrelevant = 0 THEN Nettoumsatz END) AS DECIMAL(18, 2)) AS Differenz_Storno_Retoure
FROM #temp_fct_bestellungen;

-- ==============================================================================
-- SCHRITT 6: DIMENSIONEN (Snowflake-Schema -> Sternschema: denormalisieren)
-- ==============================================================================
DROP TABLE IF EXISTS #temp_dim_produkte;

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
INTO #temp_dim_produkte
FROM dbo.Produkte AS p
INNER JOIN dbo.Kategorien AS k ON p.KategorieID  = k.KategorieID
INNER JOIN dbo.Hersteller AS h ON p.HerstellerID = h.HerstellerID;

-- Kontrolle: 120 = 120
SELECT
    (SELECT COUNT(*) FROM dbo.Produkte)       AS Quelle,
    (SELECT COUNT(*) FROM #temp_dim_produkte) AS Ergebnis;

DROP TABLE IF EXISTS #temp_dim_kunden;
DROP TABLE IF EXISTS #temp_dim_vertrieb;

SELECT
    KundeID, Kundennummer, Firmenname, Rechtsform, Branche, Kundensegment,
    Stadt, Bundesland_Kanton, Land, PLZ, Bonitaetsklasse, ZahlungszielTage, ErstelltAm
INTO #temp_dim_kunden
FROM dbo.Kunden;

SELECT
    VertriebsID, MitarbeiterName, Vertriebsregion, Standort,
    Senioritaet,            -- Achtung Schreibweise! (nicht "Seniioritaet")
    Zielumsatz_Jahr_EUR
INTO #temp_dim_vertrieb
FROM dbo.Vertriebsmitarbeiter;

SELECT COUNT(*) AS Kunden   FROM #temp_dim_kunden;    -- 2.500
SELECT COUNT(*) AS Vertrieb FROM #temp_dim_vertrieb;  -- 12

-- ==============================================================================
-- SCHRITT 7: KALENDER (rekursive CTE)
-- ==============================================================================
SET LANGUAGE German;   -- deutsche Monats-/Tagesnamen
SET DATEFIRST 1;       -- Woche beginnt am Montag

DROP TABLE IF EXISTS #temp_dim_datum;

DECLARE @Start DATE = CAST('20230101' AS DATE);   -- kulturunabhängiges Format!
DECLARE @Ende  DATE = CAST('20251231' AS DATE);

WITH Kalender AS (
    SELECT @Start AS Datum                 -- Anker: erster Tag
    UNION ALL
    SELECT DATEADD(day, 1, Datum)          -- Rekursion: +1 Tag
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
INTO #temp_dim_datum
FROM Kalender
OPTION (MAXRECURSION 2000);               -- Standardlimit 100 reicht nicht (1.096 Tage)

-- Kontrolle: 1.096 Tage (365 + 366 + 365)
SELECT COUNT(*) AS Tage_Gesamt, MIN(Datum) AS Von, MAX(Datum) AS Bis FROM #temp_dim_datum;
GO
