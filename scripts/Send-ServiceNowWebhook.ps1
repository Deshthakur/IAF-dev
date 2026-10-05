# ==============================================================================
# POWERSHELL SCRIPT: Send-ServiceNowWebhook.ps1
# Description: Sends execution status, run URL, and error logs back to ServiceNow Dev
#              Scripted REST API endpoint to update SCTASK ticket state (Auto-close / On-Hold).
# ==============================================================================

# Script parameters
param (
    [Parameter(Mandatory=$false)]
    [string]$ServiceNowUrl = "https://devinstance.service-now.com/api/custom/intune_webhook",

    [Parameter(Mandatory=$false)]
    [string]$AuthToken = "MockAuthToken123456",

    [Parameter(Mandatory=$true)]
    [string]$ScTaskId,

    [Parameter(Mandatory=$true)]
    [string]$AppName,

    [Parameter(Mandatory=$true)]
    [string]$AppVersion,

    [Parameter(Mandatory=$true)]
    [string]$Status,      # "SUCCESS" or "FAILED"

    [Parameter(Mandatory=$true)]
    [string]$Message,

    [Parameter(Mandatory=$true)]
    [string]$RunUrl
)

$ErrorActionPreference = "Stop"

Write-Host "======================================================================"
Write-Host " SENDING SERVICENOW WEBHOOK STATUS CALLBACK"
Write-Host " Ticket SCTASK : $ScTaskId"
Write-Host " Status        : $Status"
Write-Host "======================================================================"

# Step 1: Construct JSON Callback Payload
$payloadObject = @{
    sctask_id   = $ScTaskId
    app_name    = $AppName
    app_version = $AppVersion
    status      = $Status.ToUpper()
    message     = $Message
    github_run_url = $RunUrl
    timestamp   = (Get-Date -Format "o")
}

$jsonPayload = $payloadObject | ConvertTo-Json -Depth 3

Write-Host "Constructed JSON Payload:"
Write-Host $jsonPayload

# Step 2: Prepare HTTP Headers for REST Call
$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $AuthToken"
}

# Step 3: Dispatch Outbound REST Request to ServiceNow Endpoint
Write-Host "Posting status callback to ServiceNow endpoint ($ServiceNowUrl)..."

try {
    if ($ServiceNowUrl -and $ServiceNowUrl -notlike "*devinstance.service-now.com*") {
        $response = Invoke-RestMethod -Uri $ServiceNowUrl -Method Post -Body $jsonPayload -Headers $headers -ContentType "application/json"
        Write-Host "ServiceNow API Response: $($response | ConvertTo-Json)"
    } else {
        Write-Host ">>> [SIMULATION MODE] Webhook HTTP POST Request Simulated Successfully."
        Write-Host ">>> ServiceNow Ticket '$ScTaskId' Updated:"
        if ($Status.ToUpper() -eq "SUCCESS") {
            Write-Host ">>> ACTION: SCTASK State set to 'Closed Complete' (State 3). Requestor notified."
        } else {
            Write-Host ">>> ACTION: SCTASK State set to 'On Hold' (State -5). Work note added with GitHub Run URL: $RunUrl"
        }
    }
} catch {
    Write-Warning "Failed to send Webhook to ServiceNow: $_"
}

Write-Host "======================================================================"
Write-Host " WEBHOOK CALLBACK PROCESS COMPLETED"
Write-Host "======================================================================"
