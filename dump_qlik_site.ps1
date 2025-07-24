# Import-Module QlikSense
$modulePath = $PSScriptRoot
try {
    Import-Module (Join-Path $modulePath "dump_postgresql.psm1") -Force
    Import-Module (Join-Path $modulePath "dump_qlikshare.psm1") -Force
    Import-Module (Join-Path $modulePath "qlik_service.psm1") -Force
} catch {
    Write-Error "Erreur lors de l'import des modules : $_"
}
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001

# === Paramètres ===

# === Informations paramètres globaux ===

$outputDir = "C:\QlikBackup"
$qlikShareFolder = "\\MP2FWBPY\QlikShare"
$skipQlikShare = $true

# === Informations paramètres sur la base de données à dump ===
$PgBasePath = "C:\Program Files\Qlik\Sense\Repository\PostgreSQL"
$PgVersion = "14"
$DbHost = "localhost"
$DbPort = 4432
$DbUser = "postgres"
$DbPassword = ""

# === Informations paramètres pour se connecter en SSH au serveur ===

$sshHost = "xxxxxxx"
$sshUser =  "xxxxx"
$sshPassword = 'xxxxx'
$sshPort = 22

# === Informations paramètres sur les certificats ===
$certPassword = ConvertTo-SecureString -String "" -Force -AsPlainText

# === Informations paramètres qui permettent de gérer le zip de l'archive ===

$TempBackupPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Temp\QlikBackup"

# Crée le dossier racine s'il n'existe pas
if (-not (Test-Path $TempBackupPath)) {
    New-Item -Path $TempBackupPath -ItemType Directory | Out-Null
}

# Variables pour les sous-dossiers
$CertPath = Join-Path -Path $TempBackupPath -ChildPath "cert"
$DbPath = Join-Path -Path $TempBackupPath -ChildPath "db"
$SharePath = Join-Path -Path $TempBackupPath -ChildPath "share"

# Création des sous-dossiers si nécessaire
foreach ($path in @($CertPath, $DbPath, $SharePath)) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory | Out-Null
        Write-Host "Création du dossier : $path"
    }
    else {
        Write-Host "Le dossier existe déjà : $path"
    }
}

# Créer le dossier de sortie s’il n’existe pas
if (!(Test-Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory | Out-Null
}

# === Fonction d'export d'un certificat depuis un magasin ===
function Export-QlikCert {
    param (
        [string]$StoreLocation,
        [string]$StoreName,
        [string]$SubjectFilter,
        [string]$ExportFileName
    )

    try {
        $storeLocationEnum = [System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
        $storeNameEnum = [System.Security.Cryptography.X509Certificates.StoreName]::$StoreName

        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeNameEnum, $storeLocationEnum)
        $store.Open("ReadOnly")

        $cert = $store.Certificates | Where-Object { $_.Subject -like "*$SubjectFilter*" } | Sort-Object NotAfter -Descending | Select-Object -First 1

       if (-not $cert.HasPrivateKey) {
            Write-Warning "Le certificat '$ExportFileName' n’a pas de clé privée associée."
        }
        elseif (-not $cert.PrivateKey.CspKeyContainerInfo.Exportable) {
            Write-Warning "La clé privée du certificat '$ExportFileName' n’est pas exportable."
        }
        else {
            $bytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $certPassword)
            $path = Join-Path -Path $CertPath -ChildPath "$ExportFileName.pfx"
            [System.IO.File]::WriteAllBytes($path, $bytes)
            Write-Host "Exporté avec clé privée : $ExportFileName.pfx ($StoreLocation\$StoreName)"
        }

        $store.Close()
    }
    catch {
        Write-Error "Erreur pendant l'export de $ExportFileName : $_"
    }
}

Write-Host "=== Etape 0: Arrêt des services Qlik Sense ===" -ForegroundColor Cyan

Stop-QlikSenseServices -TimeoutSeconds 30

Write-Host "=== Etape 1: Export des certificats Qlik Sense ===" -ForegroundColor Cyan

# === Export de chaque certificat ===

# Autorité de certification (CA)
Export-QlikCert -StoreLocation "LocalMachine" -StoreName "Root" -SubjectFilter "-CA" -ExportFileName "Qlik_CA"

# Certificat serveur
Export-QlikCert -StoreLocation "LocalMachine" -StoreName "My" -SubjectFilter "$env:COMPUTERNAME" -ExportFileName "Qlik_ServerCert"

# Certificat client (CurrentUser)
Export-QlikCert -StoreLocation "CurrentUser" -StoreName "My" -SubjectFilter "QlikClient" -ExportFileName "Qlik_ClientCert"

# Certificat QlikServiceCluster
Export-QlikCert -StoreLocation "LocalMachine" -StoreName "My" -SubjectFilter "QlikServiceCluster" -ExportFileName "Qlik_ServiceCluster"

Write-Host "Tous les certificats Qlik Sense ont été exportés vers $outputDir"

Write-Host "=== Etape 2: Dump de la base de données ===" -ForegroundColor Cyan

Backup-QlikSenseDatabases -OutputDir $DbPath -PgBasePath $PgBasePath -PgVersion $PgVersion -DbHost $DbHost -DbPort $DbPort -DbUser $DbUser -DbPassword $DbPassword

Write-Host "=== Etape 3: Dump du Qlik Share ===" -ForegroundColor Cyan

if ($skipQlikShare -eq $true) {

    Copy-UncFolder -SourcePath (Join-Path $qlikShareFolder "Apps")  -DestinationPath $SharePath
    Copy-UncFolder -SourcePath (Join-Path $qlikShareFolder "StaticContent") -DestinationPath $SharePath
} else{
    Write-Host "Le dump du Qlik Share a été ignoré."
}

Write-Host "=== Etape 4: Création de l'archive ===" -ForegroundColor Cyan

$answer = New-QlikBackupArchive -SourcePath $TempBackupPath -DestinationFolder $outputDir 

$zipPath = $answer[0]
$zipName = $answer[1]

Write-Host "=== Etape 5: Envoi de l'archive ===" -ForegroundColor Cyan

Copy-FileToRemoteServer -sshHost $sshHost -sshUser $sshUser  -sshPassword $sshPassword  -localFile  $zipPath -remotePath "/data/$zipName"

Write-Host "=== Etape 5: redémarrage des services Qlik Sense ===" -ForegroundColor Cyan

Start-QlikSenseServices -TimeoutSeconds 30

