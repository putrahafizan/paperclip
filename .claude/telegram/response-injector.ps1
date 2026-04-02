# response-injector.ps1 — Watches for Telegram responses and types into terminal via SendKeys
# Windows equivalent of response-injector.sh (which uses tmux send-keys)
# Run as background job by claude-agent.ps1

param(
    [string]$ScriptDir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [int]$PollInterval = 1,
    [int]$Timeout = 600
)

Add-Type -AssemblyName System.Windows.Forms

$PendingFile = Join-Path $ScriptDir "pending-question.json"
$ResponseFile = Join-Path $ScriptDir "question-response.json"
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] INJECTOR: $Message"
}

function Send-TelegramNotify {
    param([string]$Text)
    try {
        $notifyScript = Join-Path $ProjectRoot ".claude\hooks\notify.sh"
        if (Test-Path $notifyScript) {
            wsl bash $notifyScript $Text 2>$null
        }
    } catch { }
}

Write-Log "Response injector started (PowerShell). Watching for question-response.json..."

while ($true) {
    # Check if response file exists
    if (Test-Path $ResponseFile) {
        try {
            $responseData = Get-Content $ResponseFile -Raw | ConvertFrom-Json
            $respQId = $responseData.id
            $response = $responseData.response
            $source = $responseData.source

            if ([string]::IsNullOrEmpty($response)) {
                Write-Log "Empty response, cleaning up"
                Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds $PollInterval
                continue
            }

            # Validate against pending question
            if (Test-Path $PendingFile) {
                $pendingData = Get-Content $PendingFile -Raw | ConvertFrom-Json
                $pendingQId = $pendingData.id

                if ($respQId -ne $pendingQId) {
                    Write-Log "Question ID mismatch: response=$respQId pending=$pendingQId. Discarding."
                    Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds $PollInterval
                    continue
                }

                # Inject response via SendKeys
                # SendKeys types into the currently focused window
                Write-Log "Injecting response '$response' via SendKeys..."

                # Escape special SendKeys characters: +, ^, %, ~, (, ), {, }, [, ]
                $escapedResponse = $response -replace '([+^%~(){}[\]])', '{$1}'

                # Type the response + Enter
                [System.Windows.Forms.SendKeys]::SendWait($escapedResponse)
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

                Write-Log "Injected response '$response' via SendKeys"

                # Send confirmation to Telegram
                Send-TelegramNotify "Response '$response' injected into terminal."

                # Cleanup
                Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
                Remove-Item $PendingFile -Force -ErrorAction SilentlyContinue
                Write-Log "Cleanup done for $respQId"

            } else {
                Write-Log "No pending question for response $respQId. Discarding."
                Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Log "Error processing response: $_"
            Remove-Item $ResponseFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Check for timeout on pending questions
    if (Test-Path $PendingFile) {
        try {
            $pendingData = Get-Content $PendingFile -Raw | ConvertFrom-Json
            $pendingTs = [DateTime]::Parse($pendingData.timestamp)
            $elapsed = (Get-Date) - $pendingTs

            if ($elapsed.TotalSeconds -gt $Timeout) {
                $qId = $pendingData.id
                Write-Log "Question $qId timed out after $($elapsed.TotalSeconds)s"
                Send-TelegramNotify "Question timed out ($Timeout s). Please respond in terminal."
                Remove-Item $PendingFile -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    Start-Sleep -Seconds $PollInterval
}
