function Stop-QlikSenseServices {
    [CmdletBinding()]
    param (
        [int]$TimeoutSeconds = 30
    )

    $qlikServices = @(
        "QlikSenseServiceDispatcher",
        "QlikSenseRepositoryService",
        "QlikSenseEngineService",
        "QlikSensePrintingService",
        "QlikSenseProxyService",
        "QlikSenseSchedulerService"
    )

    Write-Host "Arrêt des services Qlik Sense..." -ForegroundColor Cyan

    foreach ($serviceName in $qlikServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -ne 'Stopped') {
            Write-Host "→ Arrêt de $serviceName..." -NoNewline
            try {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($TimeoutSeconds))
                Write-Host " OK" -ForegroundColor Green
            }
            catch {
                Write-Host " Échec" -ForegroundColor Red
                Write-Warning "Erreur lors de l'arrêt de $serviceName : $_"
            }
        }
        elseif ($service) {
            Write-Host "$serviceName est déjà arrêté." -ForegroundColor Yellow
        }
        else {
            Write-Warning "Service introuvable : $serviceName"
        }
    }

    Write-Host " Tous les services Qlik Sense sont arrêtés (ou déjà arrêtés)." -ForegroundColor Cyan
}


function Start-QlikSenseServices {
    [CmdletBinding()]
    param (
        [int]$TimeoutSeconds = 30
    )

    # Ordre de démarrage recommandé
    $qlikServices = @(
        "QlikSenseRepositoryService",      # Doit démarrer en premier
        "QlikSenseServiceDispatcher",      # Dépend du Repository
        "QlikSenseProxyService",
        "QlikSenseEngineService",
        "QlikSenseSchedulerService",
        "QlikSensePrintingService"
    )

    Write-Host "Redémarrage des services Qlik Sense..." -ForegroundColor Cyan

    foreach ($serviceName in $qlikServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

        if ($service -and $service.Status -ne 'Running') {
            Write-Host "→ Démarrage de $serviceName..." -NoNewline
            try {
                Start-Service -Name $serviceName -ErrorAction Stop
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSeconds))
                Write-Host " OK" -ForegroundColor Green
            }
            catch {
                Write-Host " Échec" -ForegroundColor Red
                Write-Warning "Erreur lors du démarrage de $serviceName : $_"
            }
        }
        elseif ($service) {
            Write-Host "$serviceName est déjà en cours d'exécution." -ForegroundColor Yellow
        }
        else {
            Write-Warning "Service introuvable : $serviceName"
        }
    }

    Write-Host "`Tous les services Qlik Sense sont démarrés (ou déjà actifs)." -ForegroundColor Cyan
}

function New-QlikBackupArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [string]$DestinationFolder = "$env:TEMP"
    )

    if (-not (Test-Path -Path $SourcePath -PathType Container)) {
        Write-Warning "Le chemin source spécifié n'existe pas ou n'est pas un dossier : $SourcePath"
        return
    }

    # Générer le timestamp et le nom du fichier zip
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipName = "Archive_$timestamp.zip"
    $zipPath = Join-Path -Path $DestinationFolder -ChildPath $zipName

    try {
        # Créer le dossier de destination s'il n'existe pas
        if (-not (Test-Path -Path $DestinationFolder)) {
            New-Item -Path $DestinationFolder -ItemType Directory | Out-Null
        }

        # Compresser le contenu du dossier source (les fichiers et sous-dossiers)
        Compress-Archive -Path (Join-Path $SourcePath '*') -DestinationPath $zipPath -Force
        Write-Host "Archive créée : $zipPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Erreur lors de la création de l'archive : $_"
    }
}
