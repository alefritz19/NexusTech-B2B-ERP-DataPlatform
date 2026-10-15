# 🏗️ Der vollständige Data-Engineering- & BI-Workflow: Vom OLTP zum Power BI Star Schema

Dieses Projekt führt dich durch den **vollständigen, praxisnahen End-to-End-Prozess**, wie ihn Data Analysts und Analytics Engineers in Unternehmen umsetzen:
Von relationalen Rohdaten (3NF OLTP) über SQL-Transformationen und CSV-Exporte bis hin zu Power BI, DAX Studio und Microsoft Fabric.

---

## 🗺️ Der 5-Stufen-Architekturpfad

```
[1. Operatives ERP / SQL Server]
    ├── dbo.Bestellungen (Kopf)
    ├── dbo.Bestellpositionen (Zeilen)
    ├── dbo.Produkte + dbo.Kategorien + dbo.Hersteller (3NF)
    └── dbo.Lieferungen
           │
           ▼
[2. SQL Transformation & DWH-Modellierung]
    ├── dwh.vw_fct_bestellungen (Kopf + Zeilen + Marge berechnet)
    ├── dwh.vw_dim_produkte (Denormalisiert)
    ├── dwh.vw_dim_kunden & dwh.vw_dim_vertrieb
    └── dwh.dim_datum (Vollständiger Kalender)
           │
           ▼
[3. CSV-Export / File Data Layer]
    └── 02_CSV_EXPORTS/*.csv (Vorbereitet für File-Ingestion & Lakehouse)
           │
           ▼
[4. Power BI & DAX Studio]
    ├── Sternschema (1:n Beziehungen)
    └── Explizite DAX-Measures im DAX Studio testen
           │
           ▼
[5. Microsoft Fabric Cloud Lakehouse]
    ├── Bronze (Raw CSVs in OneLake)
    ├── Silver (PySpark Delta Lake: Cleansing & Star Schema)
    └── Gold / Direct Lake Power BI
```

---

## 🛠️ Phase 1: Die relationale Rohdatenbank (`NexusTech_ERP`)

In echten ERP- und CRM-Systemen (SAP, Navision, Salesforce) liegen Daten **nicht** als fertiges Sternschema vor, sondern **normalisiert (3. Normalform / 3NF)**:

* **Belegkopf & Belegzeilen getrennt:**  
  * `dbo.Bestellungen`: Enthält Datum, KundeID, VertriebsID, Zahlungsart.
  * `dbo.Bestellpositionen`: Enthält Menge, Einzelpreis, Rabatt, ProduktID.
* **Stammdaten aufgesplittet:**  
  * Ein Produkt verweist auf `KategorieID` und `HerstellerID`. Drei getrennte Tabellen!
* **Logistik getrennt:**  
  * `dbo.Lieferungen` enthält Frachtkosten, Tracking-Codes und Lieferdaten.

> 🚀 **Setup-Befehl:**  
> Die Datenbank `NexusTech_ERP` ist bereits auf deinem SQL Server eingerichtet (120.000 Positionen). Falls du sie neu erstellen willst:  
> `sqlcmd -S .\SQLEXPRESS -E -f 65001 -i 00_SETUP\01_NexusTech_ERP_erstellen.sql`

---

## 🧠 Phase 2: Wie man eine Faktentabelle (Fact Table) baut

Das Skript liegt in: [`01_DWH_TRANSFORMATION/01_Wie_man_Fakten_und_Dimensionen_baut.sql`](01_DWH_TRANSFORMATION/01_Wie_man_Fakten_und_Dimensionen_baut.sql)

### Die Kernlogik der Faktentabelle (`dwh.vw_fct_bestellungen`):
```sql
CREATE OR ALTER VIEW dwh.vw_fct_bestellungen AS
SELECT 
    pos.PositionID,
    pos.BestellID,
    b.KundeID,
    b.VertriebsID,
    pos.ProduktID,
    
    -- Datumsverknüpfung
    CAST(CONVERT(VARCHAR(8), b.Bestelldatum, 112) AS INT) AS BestelldatumKey,
    
    -- Basiszahlen
    pos.Menge,
    pos.Einzelpreis,
    pos.RabattBetrag,
    
    -- Berechnete Geschäftskennzahlen
    CAST((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag AS DECIMAL(12,2)) AS UmsatzNetto,
    CAST(pos.Menge * p.Einkaufspreis_EUR AS DECIMAL(12,2)) AS WareneinsatzNetto,
    CAST(((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag) - (pos.Menge * p.Einkaufspreis_EUR) AS DECIMAL(12,2)) AS DeckungsbeitragNetto,
    
    -- Margenberechnung (Absicherung gegen Division durch 0 via NULLIF)
    CAST(ROUND(
        (((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag) - (pos.Menge * p.Einkaufspreis_EUR)) / 
        NULLIF((pos.Menge * pos.Einzelpreis) - pos.RabattBetrag, 0), 4) AS DECIMAL(6,4)) AS DeckungsbeitragMarge,
        
    -- Logistik
    l.Versandart,
    l.Lieferstatus,
    DATEDIFF(DAY, b.Bestelldatum, l.Lieferdatum) AS LieferdauerTage
FROM dbo.Bestellpositionen pos
INNER JOIN dbo.Bestellungen b ON pos.BestellID = b.BestellID
INNER JOIN dbo.Produkte p ON pos.ProduktID = p.ProduktID
LEFT JOIN dbo.Lieferungen l ON b.BestellID = l.BestellID;
```

---

## 📤 Phase 3: Export zu CSV (Für File-Ingestion & Lakehouse)

Führe das PowerShell-Skript aus:
```powershell
powershell -ExecutionPolicy Bypass -File 02_CSV_EXPORTS\export_views_to_csv.ps1
```
Danach liegen alle 5 Tabellen als saubere CSV-Dateien im Ordner `02_CSV_EXPORTS/` bereit.

---

## 📊 Phase 4: Power BI & DAX Studio

1. **Power BI Desktop öffnen** ➔ `Daten abrufen` ➔ Entweder direkt über SQL Server (`NexusTech_ERP`) oder über die erzeugten CSV-Dateien.
2. **Modellansicht prüfen:**
   * Verbinde `dim_kunden[KundeID]` mit `vw_fct_bestellungen[KundeID]` (`1 : *`)
   * Verbinde `dim_produkte[ProduktID]` mit `vw_fct_bestellungen[ProduktID]` (`1 : *`)
   * Verbinde `dim_vertrieb[VertriebsID]` mit `vw_fct_bestellungen[VertriebsID]` (`1 : *`)
   * Verbinde `dim_datum[DatumKey]` mit `vw_fct_bestellungen[BestelldatumKey]` (`1 : *`)
3. **DAX Studio starten:**
   Verbinde dich mit dem Modell und teste deine Measures per `EVALUATE`:
   ```dax
   EVALUATE
   SUMMARIZECOLUMNS(
       'dwh vw_dim_produkte'[KategorieName],
       "Nettoumsatz", SUM('dwh vw_fct_bestellungen'[UmsatzNetto]),
       "Deckungsbeitrag", SUM('dwh vw_fct_bestellungen'[DeckungsbeitragNetto]),
       "Ø_Lieferzeit", AVERAGE('dwh vw_fct_bestellungen'[LieferdauerTage])
   )
   ```

---

## ☁️ Phase 5: Übergang zu Microsoft Fabric

Sobald dein Power BI-Modell steht, nehmen wir denselben Datensatz für Microsoft Fabric:
1. **Bronze:** Wir laden die CSVs unverändert in das Lakehouse `lh_bronze`.
2. **Silver:** Mit einem PySpark-Notebook führen wir Bereinigung, Typisierung und Z-Ordering durch.
3. **Gold / Direct Lake:** Wir binden Power BI per Direct Lake ohne Datenimport an!
