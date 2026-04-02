# claude-agent.ps1 — Windows wrapper for Claude Code with Telegram bidirectional support
# Usage: powershell -ExecutionPolicy Bypass -File .claude\telegram\claude-agent.ps1 [claude args...]
#
# Automatically:
#   1. Starts bot-daemon via WSL (reuses bash scripts)
#   2. Starts response-injector.ps1 as background job
#   3. Runs Claude Code
#   4. Cleans up on exit

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ClaudeArgs
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

# Convert Windows path to WSL path for bash scripts
$WslProjectRoot = $ProjectRoot -replace '\\', '/' -replace '^([A-Z]):', '/mnt/$1'.ToLower()
# Fix: ensure drive letter is lowercase
if ($WslProjectRoot -match '^/mnt/([A-Z])') {
    $WslProjectRoot = $WslProjectRoot -replace '^/mnt/([A-Z])', { '/mnt/' + $_.Groups[1].Value.ToLower() }
}

$DaemonPidFile = Join-Path $ScriptDir "daemon.pid"
$InjectorJob = $null
$WslDaemonProcess = $null

function Write-Status {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Start-BotDaemon {
    # Check if already running (via WSL)
    $running = $false
    if (Test-Path $DaemonPidFile) {
        try {
            $pid = Get-Content $DaemonPidFile -Raw
            $check = wsl kill -0 $pid.Trim() 2>&1
            if ($LASTEXITCODE -eq 0) { $running = $true }
        } catch { }
    }

    if ($running) {
        Write-Status "Bot daemon already running"
    } else {
        Write-Status "Starting bot daemon via WSL..."
        $script:WslDaemonProcess = Start-Process -FilePath "wsl" `
            -ArgumentList "bash", "$WslProjectRoot/.claude/telegram/bot-daemon.sh" `
            -WindowStyle Hidden -PassThru
        Write-Status "Bot daemon started (PID: $($script:WslDaemonProcess.Id))"
    }
}

function Start-ResponseInjector {
    Write-Status "Starting response injector (PowerShell)..."
    $injectorScript = Join-Path $ScriptDir "response-injector.ps1"
    $script:InjectorJob = Start-Job -ScriptBlock {
        param($scriptPath, $scriptDir)
        & $scriptPath -ScriptDir $scriptDir
    } -ArgumentList $injectorScript, $ScriptDir
    Write-Status "Response injector started (Job: $($script:InjectorJob.Id))"
}

function Stop-All {
    Write-Host ""
    Write-Status "Stopping Telegram daemons..."

    # Stop response injector job
    if ($script:InjectorJob) {
        Stop-Job -Job $script:InjectorJob -ErrorAction SilentlyContinue
        Remove-Job -Job $script:InjectorJob -Force -ErrorAction SilentlyContinue
        Write-Status "Response injector stopped"
    }

    # Stop bot daemon via WSL manage.sh
    try {
        wsl bash "$WslProjectRoot/.claude/telegram/manage.sh" stop 2>$null
        Write-Status "Bot daemon stopped"
    } catch { }

    # Kill WSL process if we started it
    if ($script:WslDaemonProcess -and !$script:WslDaemonProcess.HasExited) {
        Stop-Process -Id $script:WslDaemonProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

# Register cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Stop-All } | Out-Null

try {
    # Start services
    Start-BotDaemon
    Start-ResponseInjector

    # Display status
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Green
    Write-Host " Telegram bidirectional mode: ACTIVE" -ForegroundColor Green
    Write-Host " Platform: Windows (PowerShell)"      -ForegroundColor Green
    Write-Host " Injection: SendKeys API"             -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: Keep this terminal in focus for Telegram response injection." -ForegroundColor Yellow
    Write-Host ""

    # Run Claude Code
    $claudeCmd = "claude"
    if ($ClaudeArgs) {
        & $claudeCmd @ClaudeArgs
    } else {
        & $claudeCmd
    }
} finally {
    Stop-All
}
