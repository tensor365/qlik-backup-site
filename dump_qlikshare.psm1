function Copy-UncFolder {
    param (
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (!(Test-Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath | Out-Null
    }

    $logPath = Join-Path -Path $env:TEMP -ChildPath "CopyLog.log"
    
    Write-Host "Copie de $SourcePath vers $DestinationPath..."
    robocopy $SourcePath $DestinationPath /MIR /Z /R:2 /W:5 /MT:16 /LOG:$logPath
    $code = $LASTEXITCODE

    if ($code -ge 8) {
        throw "Robocopy a retourné un code d’erreur : $code. Vérifiez le fichier $logPath"
    } else {
        Write-Host "Copie terminée avec code $code"
    }
}