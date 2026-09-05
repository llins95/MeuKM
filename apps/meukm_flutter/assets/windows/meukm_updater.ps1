param(
  [Parameter(Mandatory = $true)][int]$HostProcessId,
  [Parameter(Mandatory = $true)][string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$InstallDirectory,
  [Parameter(Mandatory = $true)][string]$ExecutablePath,
  [Parameter(Mandatory = $true)][string]$ReadyPath,
  [Parameter(Mandatory = $true)][string]$ResultPath,
  [Parameter(Mandatory = $true)][string]$CancelPath,
  [Parameter(Mandatory = $true)][string]$BackupPath,
  [Parameter(Mandatory = $true)][string]$LogPath,
  [Parameter(Mandatory = $true)][string]$ScriptPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "MeuKM-Update-$HostProcessId"
$backupCreated = $false
$readySignaled = $false
$updateSucceeded = $false

function Write-UpdateLog {
  param([Parameter(Mandatory = $true)][string]$Message)
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  Add-Content -LiteralPath $LogPath -Value "[$timestamp] $Message" -Encoding UTF8
}

function Test-HostProcessRunning {
  $hostProcess = Get-Process -Id $HostProcessId -ErrorAction SilentlyContinue
  return $null -ne $hostProcess
}

function Invoke-RobustCopy {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$Description
  )
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
  if (-not (Test-Path -LiteralPath $robocopy -PathType Leaf)) { throw 'O Windows nao encontrou o Robocopy.' }
  Write-UpdateLog "$Description iniciada."
  & $robocopy $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:10 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "$Description falhou. Codigo do Robocopy: $LASTEXITCODE." }
  Write-UpdateLog "$Description concluida. Codigo do Robocopy: $LASTEXITCODE."
}

function Start-MeuKM {
  Start-Process -FilePath $ExecutablePath -WorkingDirectory $InstallDirectory -PassThru
}

try {
  Set-Content -LiteralPath $LogPath -Value 'MeuKM Windows Updater' -Encoding UTF8
  foreach ($marker in @($ReadyPath, $ResultPath, $CancelPath)) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
  foreach ($directory in @($staging, $BackupPath)) { if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force } }

  New-Item -ItemType Directory -Path $staging -Force | Out-Null
  if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw 'O pacote validado nao foi encontrado.' }
  if (-not (Test-Path -LiteralPath $InstallDirectory -PathType Container)) { throw 'A pasta de instalacao do MeuKM nao foi encontrada.' }
  if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { throw 'A versao instalada do MeuKM nao foi encontrada.' }

  Set-Content -LiteralPath $ReadyPath -Value 'ready' -Encoding ASCII
  $readySignaled = $true
  Write-UpdateLog 'Atualizador pronto. Aguardando o MeuKM fechar.'

  while (Test-HostProcessRunning) {
    if (Test-Path -LiteralPath $CancelPath -PathType Leaf) { throw 'A atualizacao foi cancelada antes do fechamento do MeuKM.' }
    Start-Sleep -Milliseconds 200
  }
  Start-Sleep -Milliseconds 1000
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $staging -Force

  $newExecutable = Join-Path $staging 'meukm.exe'
  if (-not (Test-Path -LiteralPath $newExecutable -PathType Leaf)) {
    $newExecutable = Join-Path $staging 'MeuKM.exe'
  }
  if (-not (Test-Path -LiteralPath $newExecutable -PathType Leaf)) { throw 'O pacote baixado nao contem o executavel do MeuKM.' }

  Invoke-RobustCopy -Source $InstallDirectory -Destination $BackupPath -Description 'Copia de seguranca'
  $backupCreated = $true
  Invoke-RobustCopy -Source $staging -Destination $InstallDirectory -Description 'Instalacao da nova versao'

  $newProcess = Start-MeuKM
  Start-Sleep -Seconds 2
  $newProcess.Refresh()
  if ($newProcess.HasExited) { throw 'A nova versao fechou imediatamente depois de ser iniciada.' }

  Set-Content -LiteralPath $ResultPath -Value 'success' -Encoding ASCII
  $updateSucceeded = $true
  Write-UpdateLog 'Atualizacao concluida e nova versao iniciada.'
  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $BackupPath -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue
  exit 0
} catch {
  $failure = $_ | Out-String
  try { Write-UpdateLog "ERRO: $failure" } catch {}
  if ($backupCreated -and (Test-Path -LiteralPath $BackupPath)) {
    try { Invoke-RobustCopy -Source $BackupPath -Destination $InstallDirectory -Description 'Restauracao da versao anterior' } catch { $failure = "$failure`r`nFalha ao restaurar: $($_ | Out-String)" }
  }
  Set-Content -LiteralPath $ResultPath -Value "failure`r`n$failure" -Encoding UTF8
  if ($readySignaled -and -not (Test-HostProcessRunning)) {
    try { Start-MeuKM | Out-Null } catch {}
  }
  exit 1
} finally {
  if ($updateSucceeded) { Remove-Item -LiteralPath $ScriptPath -Force -ErrorAction SilentlyContinue }
}
