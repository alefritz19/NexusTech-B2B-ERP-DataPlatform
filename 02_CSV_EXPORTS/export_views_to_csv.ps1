# ==============================================================================
# EXPORT DER DWH-VIEWS ALS CSV-DATEIEN
# Datenbank: NexusTech_ERP (.\SQLEXPRESS)
# ==============================================================================

$connString = "Server=.\SQLEXPRESS;Database=NexusTech_ERP;Integrated Security=True;TrustServerCertificate=True"
$outDir = "C:\Users\alexf\Desktop\NexusTech_B2B_ERP_Project\02_CSV_EXPORTS"

$views = @{
    "fct_bestellungen.csv" = "SELECT * FROM dwh.vw_fct_bestellungen"
    "dim_produkte.csv"     = "SELECT * FROM dwh.vw_dim_produkte"
    "dim_kunden.csv"       = "SELECT * FROM dwh.vw_dim_kunden"
    "dim_vertrieb.csv"     = "SELECT * FROM dwh.vw_dim_vertrieb"
    "dim_datum.csv"        = "SELECT * FROM dwh.dim_datum"
}

Write-Host "Starte sauberen CSV-Export aus NexusTech_ERP..." -ForegroundColor Cyan

$conn = New-Object System.Data.SqlClient.SqlConnection($connString)
$conn.Open()

foreach ($file in $views.Keys) {
    $outFile = Join-Path $outDir $file
    Write-Host "Exportiere $file..." -ForegroundColor Yellow
    
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $views[$file]
    $cmd.CommandTimeout = 300
    
    $reader = $cmd.ExecuteReader()
    $writer = New-Object System.IO.StreamWriter($outFile, $false, [System.Text.Encoding]::UTF8)
    
    # Header schreiben
    $fieldCount = $reader.FieldCount
    $headers = 0..($fieldCount - 1) | ForEach-Object { $reader.GetName($_) }
    $writer.WriteLine(($headers -join ","))
    
    # Zeilen schreiben
    while ($reader.Read()) {
        $values = 0..($fieldCount - 1) | ForEach-Object {
            $val = $reader.GetValue($_)
            if ($val -is [System.DBNull]) {
                ""
            } else {
                $str = $val.ToString().Replace('"', '""')
                if ($str.Contains(",") -or $str.Contains("`n") -or $str.Contains('"')) {
                    "`"$str`""
                } else {
                    $str
                }
            }
        }
        $writer.WriteLine(($values -join ","))
    }
    
    $writer.Close()
    $reader.Close()
    Write-Host "   OK: $file fertig!" -ForegroundColor Green
}

$conn.Close()
Write-Host "`nAlle CSV-Dateien erfolgreich exportiert nach: $outDir" -ForegroundColor Green
