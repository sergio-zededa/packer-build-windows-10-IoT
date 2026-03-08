@echo off
setlocal EnableExtensions EnableDelayedExpansion
set LOG=C:\Windows\Temp\enable-winrm-cmd.log

echo [%DATE% %TIME%] WinRM bootstrap begin>>"%LOG%"

reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f >>"%LOG%" 2>&1
sc.exe config WinRM start= auto >>"%LOG%" 2>&1
sc.exe start WinRM >>"%LOG%" 2>&1

:: Wait up to ~60s for WinRM to reach RUNNING.
:: Uses ping for sleeping — unlike "timeout", ping works in headless/non-console
:: contexts (specialize, SYSTEM scheduled tasks) where stdin is not a TTY.
:: If WinRM can't start in time (e.g. during specialize before full OS is up),
:: we skip config and rely on the FirstLogonCommands run to do it properly.
set WAIT_COUNT=0
:wait_winrm
sc query WinRM | find "RUNNING" >nul 2>&1
if not errorlevel 1 goto winrm_ready
set /a WAIT_COUNT+=1
if %WAIT_COUNT% GEQ 30 goto winrm_timeout
ping -n 3 127.0.0.1 >nul 2>&1
goto wait_winrm

:winrm_timeout
echo [%DATE% %TIME%] WinRM did not reach RUNNING within 60s -- deferring config>>"%LOG%"
goto done

:winrm_ready
echo [%DATE% %TIME%] WinRM is RUNNING, configuring...>>"%LOG%"

:: Enable-PSRemoting replaces winrm quickconfig + winrm create + winrm set entirely.
:: -Force         : suppresses all confirmation prompts
:: -SkipNetworkProfileCheck : bypasses the Public/Unidentified network restriction
::                            that causes winrm quickconfig to deadlock
:: Internally it creates the HTTP listener, enables firewall rules, and sets
:: the service to auto-start — with no HTTP round-trip back to the service itself.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Enable-PSRemoting -Force -SkipNetworkProfileCheck" >>"%LOG%" 2>&1

:: Configure Basic auth + unencrypted transport required by Packer.
:: These use the WSMan PSProvider (registry-backed), not the WS-Man HTTP client,
:: so they cannot deadlock the service the way winrm set commands can.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true" >>"%LOG%" 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true" >>"%LOG%" 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024" >>"%LOG%" 2>&1

netsh advfirewall firewall add rule name="WinRM HTTP 5985" dir=in action=allow protocol=TCP localport=5985 >>"%LOG%" 2>&1

:: Enable RDP
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f >>"%LOG%" 2>&1
netsh advfirewall firewall set rule group="remote desktop" new enable=yes >>"%LOG%" 2>&1

:done
schtasks /create /tn "EnableWinRMAtStartup" /sc onstart /ru "SYSTEM" /rl highest /tr "cmd /c C:\Windows\Temp\enable-winrm.cmd" /f >>"%LOG%" 2>&1

echo [%DATE% %TIME%] WinRM bootstrap end>>"%LOG%"
exit /b 0
