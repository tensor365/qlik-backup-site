function Backup-QlikSenseDatabases {
    [CmdletBinding()]
    param (
        [string]$PgBasePath = "C:\Program Files\Qlik\Sense\Repository\PostgreSQL",
        [string]$PgVersion = "14",
        [string]$OutputDir = "C:\QlikDBBackups",
        [string]$DbHost = "localhost",
        [int]$DbPort = 4432,
        [string]$DbUser = "postgres",
        [string]$DbPassword = "",
        [string[]]$Databases = @("QSR", "SenseServices", "QSMQ", "Licenses")
    )

    # === Résolution automatique du chemin pg_dump ===
    $pgBinPath = Join-Path -Path $PgBasePath -ChildPath "$PgVersion\bin"
    $pgDumpPath = Join-Path -Path $pgBinPath -ChildPath "pg_dump.exe"

    if (!(Test-Path $pgDumpPath)) {
        Write-Error "pg_dump.exe introuvable à : $pgDumpPath"
        return
    }

    # === Crée le dossier de sauvegarde si besoin ===
    if (!(Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }

    # === Ajout du mot de passe dans les variables d'environnement ===
    $env:PGPASSWORD = $DbPassword

    # === Sauvegarde de chaque base ===
    foreach ($db in $Databases) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path -Path $OutputDir -ChildPath "${db}_backup_$timestamp.tar"

        Write-Host "🔄 Sauvegarde de la base '$db' → $backupFile"

        & "$pgDumpPath" `
            -h $DbHost `
            -p $DbPort `
            -U $DbUser `
            -b `
            -F t `
            -f "$backupFile" `
            $db

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Sauvegarde réussie : $db" -ForegroundColor Green
        } else {
            Write-Error "Échec de la sauvegarde : $db (Code: $LASTEXITCODE)"
        }
    }

    # === Nettoyage de la variable d'environnement
    Remove-Item Env:PGPASSWORD

    Write-Host "`Toutes les bases ont été sauvegardées dans : $OutputDir" -ForegroundColor Cyan
}

