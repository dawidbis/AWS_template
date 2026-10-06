# Uruchom w każdym nowym terminalu w tym katalogu:   . .\env.ps1
# Ustawia AWS_PROFILE/AWS_REGION, aktywuje .venv, ładuje komendy (learn-help).
Import-Module (Join-Path $PSScriptRoot 'tools\learn.psm1') -Force -DisableNameChecking -Global
Test-LearnEnv
Write-Host "Komendy: learn-help" -ForegroundColor DarkGray
