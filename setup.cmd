@echo off
rem Uruchamia setup.ps1 z pominieciem blokady skryptow (swiezy Windows ma polityke Restricted).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
