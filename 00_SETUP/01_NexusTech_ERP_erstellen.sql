-- ==============================================================================
-- NEXUSTECH B2B SOLUTIONS GMBH — OPERATIVE UNTERNEHMENSDATENBANK (OLTP / ERP)
-- End-to-End Analytics Engineering Übung: Von 3NF-Rohdaten zum Power BI Sternschema
-- ==============================================================================

USE master;
GO

IF DB_ID('NexusTech_ERP') IS NOT NULL
BEGIN
    ALTER DATABASE NexusTech_ERP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE NexusTech_ERP;
END;
GO

CREATE DATABASE NexusTech_ERP;
GO

USE NexusTech_ERP;
GO

-- Schemas anlegen
CREATE SCHEMA stg;   -- Staging / Unbereinigte Rohimporte
GO
CREATE SCHEMA util;  -- Hilfstabellen (Zahlen-Hilfstabelle)
GO
CREATE SCHEMA dwh;   -- Zukünftige analytische Sicht (Sternschema Views)
GO

-- ------------------------------------------------------------------------------
-- 1. HILFSTABELLE: Tally Table (Zahlen von 1 bis 150.000)
-- ------------------------------------------------------------------------------
CREATE TABLE util.Zahlen (N INT NOT NULL PRIMARY KEY);
GO

WITH 
  E1(N) AS (SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 
            UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1 UNION ALL SELECT 1), -- 10
  E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),                                                                -- 100
  E3(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),                                                                -- 10.000
  E4(N) AS (SELECT 1 FROM E3 a CROSS JOIN E1 b)                                                                 -- 100.000
INSERT INTO util.Zahlen (N)
SELECT TOP (150000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM E4 a CROSS JOIN E1 b;
GO

-- ------------------------------------------------------------------------------
-- 2. STAMMDATEN: Kategorien, Hersteller, Produkte (3NF Normalisiert)
-- ------------------------------------------------------------------------------
CREATE TABLE dbo.Kategorien (
    KategorieID INT IDENTITY(1,1) PRIMARY KEY,
    KategorieName NVARCHAR(50) NOT NULL,
    Warenbereich NVARCHAR(50) NOT NULL
);

INSERT INTO dbo.Kategorien (KategorieName, Warenbereich) VALUES
(N'IT-Hardware & Peripherie',   N'Hardware'),
(N'Netzwerk & Infrastruktur',    N'Infrastruktur'),
(N'Server & Cloud Storage',      N'Enterprise Systems'),
(N'Software & Lizenzen',         N'Digital & Cloud'),
(N'Büro-Ergonomie & Mobiliar',   N'Office Equipment'),
(N'Verbrauchsmaterial & Zubehör',N'Supplies');
GO

CREATE TABLE dbo.Hersteller (
    HerstellerID INT IDENTITY(1,1) PRIMARY KEY,
    HerstellerName NVARCHAR(100) NOT NULL,
    Herkunftsland NVARCHAR(50) NOT NULL,
    Partnerschaftsstatus NVARCHAR(30) NOT NULL
);

INSERT INTO dbo.Hersteller (HerstellerName, Herkunftsland, Partnerschaftsstatus) VALUES
(N'Dell Technologies',      N'USA',         N'Platinum Partner'),
(N'HP Enterprise',          N'USA',         N'Gold Partner'),
(N'Cisco Systems',          N'USA',         N'Platinum Partner'),
(N'Lenovo Group',           N'China',       N'Gold Partner'),
(N'Synology Inc.',          N'Taiwan',      N'Silver Partner'),
(N'Microsoft Corporation',  N'USA',         N'Tier-1 CSP'),
(N'VMware by Broadcom',     N'USA',         N'Certified Partner'),
(N'Logitech International', N'Schweiz',     N'Gold Partner'),
(N'Steelcase Deutschland',  N'Deutschland', N'Premium Supplier'),
(N'Schneider Electric APC', N'Frankreich',  N'Gold Partner'),
(N'Kyocera Document Solutions', N'Japan',   N'Silver Partner'),
(N'Samsung Electronics',    N'Südkorea',    N'Gold Partner');
GO

CREATE TABLE dbo.Produkte (
    ProduktID INT IDENTITY(1001,1) PRIMARY KEY,
    EAN VARCHAR(13) NOT NULL,
    ProduktName NVARCHAR(150) NOT NULL,
    KategorieID INT NOT NULL FOREIGN KEY REFERENCES dbo.Kategorien(KategorieID),
    HerstellerID INT NOT NULL FOREIGN KEY REFERENCES dbo.Hersteller(HerstellerID),
    Einkaufspreis_EUR DECIMAL(10,2) NOT NULL,
    Listenpreis_EUR DECIMAL(10,2) NOT NULL,
    IstAktiv BIT NOT NULL DEFAULT 1
);

-- 120 Produkte einfügen
INSERT INTO dbo.Produkte (EAN, ProduktName, KategorieID, HerstellerID, Einkaufspreis_EUR, Listenpreis_EUR)
SELECT 
    '40' + RIGHT('00000000000' + CAST(100000000 + z.N * 37 AS VARCHAR(11)), 11),
    CASE (z.N % 20)
        WHEN 0  THEN N'ThinkBook Enterprise 15 Zoll G4'
        WHEN 1  THEN N'EliteDesk Mini PC Core i7 32GB'
        WHEN 2  THEN N'UltraSharp 27 Zoll 4K USB-C Monitor'
        WHEN 3  THEN N'Ergonomischer 34 Zoll Curved UWQHD'
        WHEN 4  THEN N'Thunderbolt 4 Universal Dockingstation'
        WHEN 5  THEN N'Managed Gigabit Switch 24-Port PoE+'
        WHEN 6  THEN N'Enterprise Core Switch 48-Port 10GbE'
        WHEN 7  THEN N'WiFi-6 Dual-Band Access Point Pro'
        WHEN 8  THEN N'VPN-Sicherheits-Gateway Firewall Appliance'
        WHEN 9  THEN N'19 Zoll Serverschrank 42HE schallgedämmt'
        WHEN 10 THEN N'PowerServer Rack 1HE 64GB ECC Dual-Xeon'
        WHEN 11 THEN N'4-Bay Business NAS Storage System'
        WHEN 12 THEN N'Server-SSD 1.92TB NVMe Read-Intensive'
        WHEN 13 THEN N'Windows Server 2022 Standard 16-Core'
        WHEN 14 THEN N'Endpoint Security Suite 10 Clients 1Y'
        WHEN 15 THEN N'VM-Backup & Replikation Jahreslizenz'
        WHEN 16 THEN N'Ergonomischer Bürodrehstuhl Pro-Mesh'
        WHEN 17 THEN N'Elektrisch höhenverstellbarer Schreibtisch 160cm'
        WHEN 18 THEN N'Tonerkassette Schwarz XXL 10.000 Seiten'
        ELSE         N'Premium Kopierpapier Palette 100.000 Blatt'
    END + CASE WHEN z.N > 60 THEN N' (Edition Pro)' ELSE N'' END,
    ((z.N - 1) % 6) + 1,
    ((z.N * 3) % 12) + 1,
    CAST(20.00 + (z.N * 11.50) % 800 AS DECIMAL(10,2)),
    CAST((20.00 + (z.N * 11.50) % 800) * 1.55 AS DECIMAL(10,2))
FROM util.Zahlen z
WHERE z.N <= 120;
GO

-- ------------------------------------------------------------------------------
-- 3. KUNDEN & VERTRIEBSORGANISATION (B2B DACH-Region)
-- ------------------------------------------------------------------------------
CREATE TABLE dbo.Kunden (
    KundeID INT IDENTITY(1,1) PRIMARY KEY,
    Kundennummer VARCHAR(20) NOT NULL UNIQUE,
    Firmenname NVARCHAR(150) NOT NULL,
    Rechtsform NVARCHAR(30) NOT NULL,
    Branche NVARCHAR(60) NOT NULL,
    Kundensegment NVARCHAR(40) NOT NULL,
    Stadt NVARCHAR(60) NOT NULL,
    Bundesland_Kanton NVARCHAR(60) NOT NULL,
    Land NVARCHAR(50) NOT NULL,
    PLZ VARCHAR(10) NOT NULL,
    Bonitaetsklasse VARCHAR(5) NOT NULL,
    ZahlungszielTage INT NOT NULL,
    ErstelltAm DATE NOT NULL
);

INSERT INTO dbo.Kunden (Kundennummer, Firmenname, Rechtsform, Branche, Kundensegment, Stadt, Bundesland_Kanton, Land, PLZ, Bonitaetsklasse, ZahlungszielTage, ErstelltAm)
SELECT 
    'DE-KND-' + RIGHT('00000' + CAST(z.N AS VARCHAR(5)), 5),
    CASE (z.N % 10)
        WHEN 0 THEN N'Nova Systeme'
        WHEN 1 THEN N'Terra Engineering'
        WHEN 2 THEN N'Vectra Analytics'
        WHEN 3 THEN N'Apex Digital Solutions'
        WHEN 4 THEN N'Synapse Automation'
        WHEN 5 THEN N'Hanse Logistik'
        WHEN 6 THEN N'Bavaria Consulting'
        WHEN 7 THEN N'Rhein-Ruhr Industrie'
        WHEN 8 THEN N'Optima Medizintechnik'
        ELSE        N'Integris FinTech'
    END + N' ' + CASE (z.N % 4) WHEN 0 THEN N'GmbH' WHEN 1 THEN N'AG' WHEN 2 THEN N'GmbH & Co. KG' ELSE N'UG' END,
    CASE (z.N % 4) WHEN 0 THEN N'GmbH' WHEN 1 THEN N'AG' WHEN 2 THEN N'GmbH & Co. KG' ELSE N'UG' END,
    CASE (z.N % 6) 
        WHEN 0 THEN N'Maschinenbau' 
        WHEN 1 THEN N'IT & Software' 
        WHEN 2 THEN N'Gesundheitswesen & Pharma' 
        WHEN 3 THEN N'Logistik & Transport' 
        WHEN 4 THEN N'Automotive' 
        ELSE N'Unternehmensberatung' 
    END,
    CASE WHEN z.N % 10 < 6 THEN N'KMU (Mittelstand)' WHEN z.N % 10 < 9 THEN N'Großunternehmen (Enterprise)' ELSE N'Öffentlicher Sektor' END,
    CASE (z.N % 8)
        WHEN 0 THEN N'Berlin'
        WHEN 1 THEN N'München'
        WHEN 2 THEN N'Hamburg'
        WHEN 3 THEN N'Köln'
        WHEN 4 THEN N'Frankfurt am Main'
        WHEN 5 THEN N'Stuttgart'
        WHEN 6 THEN N'Wien'
        ELSE        N'Zürich'
    END,
    CASE (z.N % 8)
        WHEN 0 THEN N'Berlin'
        WHEN 1 THEN N'Bayern'
        WHEN 2 THEN N'Hamburg'
        WHEN 3 THEN N'Nordrhein-Westfalen'
        WHEN 4 THEN N'Hessen'
        WHEN 5 THEN N'Baden-Württemberg'
        WHEN 6 THEN N'Wien'
        ELSE        N'Zürich'
    END,
    CASE WHEN z.N % 8 = 6 THEN N'Österreich' WHEN z.N % 8 = 7 THEN N'Schweiz' ELSE N'Deutschland' END,
    CASE (z.N % 8)
        WHEN 0 THEN '10115' WHEN 1 THEN '80331' WHEN 2 THEN '20095' WHEN 3 THEN '50667'
        WHEN 4 THEN '60311' WHEN 5 THEN '70173' WHEN 6 THEN '1010'  ELSE '8001'
    END,
    CASE (z.N % 5) WHEN 0 THEN 'AAA' WHEN 1 THEN 'AA' WHEN 2 THEN 'A' WHEN 3 THEN 'BBB' ELSE 'BB' END,
    CASE WHEN z.N % 10 < 6 THEN 14 WHEN z.N % 10 < 9 THEN 30 ELSE 60 END,
    DATEADD(DAY, -(z.N % 1200), CAST('20251231' AS DATE))
FROM util.Zahlen z
WHERE z.N <= 2500;
GO

CREATE TABLE dbo.Vertriebsmitarbeiter (
    VertriebsID INT IDENTITY(501,1) PRIMARY KEY,
    MitarbeiterName NVARCHAR(100) NOT NULL,
    Vertriebsregion NVARCHAR(40) NOT NULL,
    Standort NVARCHAR(50) NOT NULL,
    Senioritaet NVARCHAR(40) NOT NULL,
    Zielumsatz_Jahr_EUR DECIMAL(12,2) NOT NULL
);

INSERT INTO dbo.Vertriebsmitarbeiter (MitarbeiterName, Vertriebsregion, Standort, Senioritaet, Zielumsatz_Jahr_EUR) VALUES
(N'Maximilian Müller',  N'Nord',  N'Hamburg',            N'Senior Account Manager', 850000.00),
(N'Sophie Schmidt',     N'Nord',  N'Hannover',           N'Account Manager',        500000.00),
(N'Alexander Schneider',N'West',  N'Köln',               N'Senior Account Manager', 900000.00),
(N'Laura Fischer',      N'West',  N'Düsseldorf',         N'Account Manager',        550000.00),
(N'Felix Weber',        N'Süd',   N'München',            N'Senior Account Manager', 950000.00),
(N'Anna Meyer',         N'Süd',   N'Stuttgart',          N'Account Manager',        600000.00),
(N'Lukas Wagner',       N'Ost',   N'Berlin',             N'Senior Account Manager', 800000.00),
(N'Julia Becker',       N'Ost',   N'Leipzig',            N'Account Manager',        500000.00),
(N'Niklas Schulz',      N'Mitte', N'Frankfurt am Main',  N'Senior Account Manager', 880000.00),
(N'Sarah Hoffmann',     N'Mitte', N'Nürnberg',           N'Account Manager',        520000.00),
(N'Jan Schäfer',        N'DACH',  N'Wien',               N'Key Account Manager AT', 750000.00),
(N'Katharina Koch',     N'DACH',  N'Zürich',             N'Key Account Manager CH', 980000.00);
GO

-- ------------------------------------------------------------------------------
-- 4. TRANSAKTIONEN: Bestellungen (Kopf), Positionen (Zeilen), Lieferungen
-- ------------------------------------------------------------------------------
CREATE TABLE dbo.Bestellungen (
    BestellID INT IDENTITY(100000,1) PRIMARY KEY,
    Bestellnummer VARCHAR(30) NOT NULL UNIQUE,
    KundeID INT NOT NULL FOREIGN KEY REFERENCES dbo.Kunden(KundeID),
    VertriebsID INT NOT NULL FOREIGN KEY REFERENCES dbo.Vertriebsmitarbeiter(VertriebsID),
    Bestelldatum DATE NOT NULL,
    Zahlungsart NVARCHAR(40) NOT NULL,
    Bestellstatus NVARCHAR(30) NOT NULL
);

-- 40.000 Bestellköpfe anlegen (2023 - 2025)
INSERT INTO dbo.Bestellungen (Bestellnummer, KundeID, VertriebsID, Bestelldatum, Zahlungsart, Bestellstatus)
SELECT 
    'B2B-AUF-' + CAST(100000 + z.N AS VARCHAR(10)),
    ((z.N * 7) % 2500) + 1,
    ((z.N * 5) % 12) + 501,
    DATEADD(DAY, (z.N % 1095), CAST('20230101' AS DATE)),
    CASE (z.N % 4) 
        WHEN 0 THEN N'Rechnungskauf' 
        WHEN 1 THEN N'SEPA-Firmenlastschrift' 
        WHEN 2 THEN N'Vorkasse Überweisung' 
        ELSE N'Kreditkarte Corporate' 
    END,
    CASE 
        WHEN z.N % 50 = 0 THEN N'Storniert'
        WHEN z.N % 25 = 0 THEN N'In Bearbeitung'
        ELSE N'Abgeschlossen'
    END
FROM util.Zahlen z
WHERE z.N <= 40000;
GO

CREATE TABLE dbo.Bestellpositionen (
    PositionID INT IDENTITY(1,1) PRIMARY KEY,
    BestellID INT NOT NULL FOREIGN KEY REFERENCES dbo.Bestellungen(BestellID),
    ProduktID INT NOT NULL FOREIGN KEY REFERENCES dbo.Produkte(ProduktID),
    Menge INT NOT NULL,
    Einzelpreis DECIMAL(10,2) NOT NULL,
    RabattBetrag DECIMAL(10,2) NOT NULL
);

-- 120.000 Positionen (durchschnittlich 3 Positionen je Bestellung)
INSERT INTO dbo.Bestellpositionen (BestellID, ProduktID, Menge, Einzelpreis, RabattBetrag)
SELECT 
    100000 + ((z.N - 1) / 3),
    ((z.N * 13) % 120) + 1001,
    CASE (z.N % 7) 
        WHEN 0 THEN 10 
        WHEN 1 THEN 5 
        WHEN 2 THEN 2 
        WHEN 3 THEN 1 
        WHEN 4 THEN 20 
        ELSE 1 
    END,
    p.Listenpreis_EUR,
    ROUND(p.Listenpreis_EUR * CASE (z.N % 7) WHEN 0 THEN 10 WHEN 1 THEN 5 WHEN 2 THEN 2 WHEN 3 THEN 1 WHEN 4 THEN 20 ELSE 1 END * 
          CASE WHEN z.N % 5 = 0 THEN 0.10 WHEN z.N % 11 = 0 THEN 0.05 ELSE 0.0 END, 2)
FROM util.Zahlen z
INNER JOIN dbo.Produkte p ON p.ProduktID = ((z.N * 13) % 120) + 1001
WHERE z.N <= 120000;
GO

CREATE TABLE dbo.Lieferungen (
    LieferID INT IDENTITY(1,1) PRIMARY KEY,
    BestellID INT NOT NULL FOREIGN KEY REFERENCES dbo.Bestellungen(BestellID),
    Versandart NVARCHAR(50) NOT NULL,
    Versanddatum DATE NOT NULL,
    Lieferdatum DATE NULL,
    Lieferstatus NVARCHAR(30) NOT NULL,
    TrackingCode VARCHAR(40) NOT NULL,
    Frachtkosten_EUR DECIMAL(10,2) NOT NULL
);

INSERT INTO dbo.Lieferungen (BestellID, Versandart, Versanddatum, Lieferdatum, Lieferstatus, TrackingCode, Frachtkosten_EUR)
SELECT 
    b.BestellID,
    CASE (b.BestellID % 4)
        WHEN 0 THEN N'Standard Paketdienst'
        WHEN 1 THEN N'Express Versand 24h'
        WHEN 2 THEN N'Spedition & Palettenfracht'
        ELSE N'Direktlieferung Kurier'
    END,
    DATEADD(DAY, 1, b.Bestelldatum),
    CASE 
        WHEN b.Bestellstatus = N'Storniert' THEN NULL
        ELSE DATEADD(DAY, 1 + (b.BestellID % 5) + 1, b.Bestelldatum)
    END,
    CASE 
        WHEN b.Bestellstatus = N'Storniert' THEN N'Storniert'
        WHEN b.BestellID % 30 = 0 THEN N'Retoure'
        WHEN b.Bestellstatus = N'In Bearbeitung' THEN N'In Zustellung'
        ELSE N'Zugestellt'
    END,
    'TRK-DACH-' + CAST(200000 + b.BestellID AS VARCHAR(10)),
    CASE (b.BestellID % 4)
        WHEN 0 THEN 4.90
        WHEN 1 THEN 14.90
        WHEN 2 THEN 49.00
        ELSE 0.00
    END
FROM dbo.Bestellungen b;
GO

-- ------------------------------------------------------------------------------
-- 5. STAGING BEREICH: stg.CRM_LeadImport (Unbereinigte Daten für ETL-Übungen)
-- ------------------------------------------------------------------------------
CREATE TABLE stg.CRM_LeadImport (
    ImportRowID INT IDENTITY(1,1) PRIMARY KEY,
    Raw_Firmenname NVARCHAR(200),
    Raw_Email NVARCHAR(100),
    Raw_Telefon NVARCHAR(50),
    Raw_Registrierungsdatum NVARCHAR(50),
    Raw_Umsatzpotenzial NVARCHAR(50)
);

INSERT INTO stg.CRM_LeadImport (Raw_Firmenname, Raw_Email, Raw_Telefon, Raw_Registrierungsdatum, Raw_Umsatzpotenzial) VALUES
(N'   Alpha Tech GmbH   ', N'info@alpha-tech.de', N'+49 (0) 30 123456', N'2024-03-15', N'50000'),
(N'alpha tech gmbh',       N'INFO@ALPHA-TECH.DE', N'030/123456',        N'15.03.2024', N'50.000 €'), -- Duplikat
(N'Nova Systeme AG',       N'kontakt@nova.ch',   N'+41 44 987 65 43',  N'2024/04/01', N'120000'),
(N'Müller & Partner GbR',  NULL,                 N'089-445566',        N'ungültig',   N'NULL'),
(N'Vectra Cloud Solution', N'sales@vectra.com',  N'0049 40 55443322',  N'2024-05-10', N'85000 EUR'),
(N'Vectra Cloud Solution', N'sales@vectra.com',  N'040 55443322',      N'2024-05-10', N'85000'); -- Duplikat
GO

-- ------------------------------------------------------------------------------
-- 6. PRÜFUNG & ABSCHLUSS-STATUS
-- ------------------------------------------------------------------------------
PRINT '==============================================================================';
PRINT 'NexusTech_ERP erfolgreich aufgesetzt!';
PRINT '------------------------------------------------------------------------------';
SELECT 'Kategorien' AS Tabelle, COUNT(*) AS Anzahl FROM dbo.Kategorien
UNION ALL SELECT 'Hersteller', COUNT(*) FROM dbo.Hersteller
UNION ALL SELECT 'Produkte', COUNT(*) FROM dbo.Produkte
UNION ALL SELECT 'Kunden', COUNT(*) FROM dbo.Kunden
UNION ALL SELECT 'Vertriebsmitarbeiter', COUNT(*) FROM dbo.Vertriebsmitarbeiter
UNION ALL SELECT 'Bestellungen (Kopf)', COUNT(*) FROM dbo.Bestellungen
UNION ALL SELECT 'Bestellpositionen (Zeilen)', COUNT(*) FROM dbo.Bestellpositionen
UNION ALL SELECT 'Lieferungen', COUNT(*) FROM dbo.Lieferungen
UNION ALL SELECT 'stg.CRM_LeadImport (Schmutzdaten)', COUNT(*) FROM stg.CRM_LeadImport;
PRINT '==============================================================================';
GO
