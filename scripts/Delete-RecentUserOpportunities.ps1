param(
    [int]$LastMinutes = 10
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$targetOrgAlias = "SOHNUT-Votfound-full"
$targetUserId = "005Ae00000I178LIAR"
$sfCommand = "sf.cmd"
$env:SF_AUTOUPDATE_DISABLE = "true"
$env:SFDX_AUTOUPDATE_DISABLE = "true"

function Invoke-SfJsonCommand {
    param(
        [string[]]$Arguments
    )

    $escapedArguments = ($Arguments + "--json") | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
    $commandText = @(
        "set SF_AUTOUPDATE_DISABLE=true",
        "set SFDX_AUTOUPDATE_DISABLE=true",
        "$sfCommand $($escapedArguments -join ' ') 2>nul"
    ) -join " && "
    $output = & cmd.exe /d /c $commandText

    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

function Invoke-SfAnonymousApex {
    param(
        [string]$ApexCode
    )

    $temporaryApexPath = Join-Path $PSScriptRoot ".codex_delete_recent_user_opportunities.apex"

    try {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporaryApexPath, $ApexCode, $utf8WithoutBom)
        $escapedArguments = @(
            "apex",
            "run",
            "--target-org", $targetOrgAlias,
            "--file", $temporaryApexPath,
            "--json"
        ) | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
        $commandText = @(
            "set SF_AUTOUPDATE_DISABLE=true",
            "set SFDX_AUTOUPDATE_DISABLE=true",
            "$sfCommand $($escapedArguments -join ' ') 2>nul"
        ) -join " && "
        $output = & cmd.exe /d /c $commandText

        if ($LASTEXITCODE -ne 0) {
            throw ($output -join [Environment]::NewLine)
        }

        return ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } finally {
        if (Test-Path $temporaryApexPath) {
            Remove-Item -Path $temporaryApexPath -Force
        }
    }
}

if ($LastMinutes -le 0) {
    throw "LastMinutes must be greater than zero."
}

$createdAfterUtc = (Get-Date).ToUniversalTime().AddMinutes(-$LastMinutes).ToString("yyyy-MM-ddTHH:mm:ssZ")

$userQuery = "SELECT Id, Name, Username FROM User WHERE Id = '$targetUserId' LIMIT 1"
$userQueryResult = Invoke-SfJsonCommand -Arguments @(
    "data", "query",
    "--target-org", $targetOrgAlias,
    "--query", $userQuery
)

if ($userQueryResult.result.totalSize -ne 1) {
    throw "Unable to resolve the target User record for Id $targetUserId."
}

$userRecord = $userQueryResult.result.records[0]
$userName = $userRecord.Name
$username = $userRecord.Username

$opportunityQuery = "SELECT COUNT() FROM Opportunity WHERE CreatedById = '$targetUserId' AND CreatedDate >= $createdAfterUtc"

$opportunityQueryResult = Invoke-SfJsonCommand -Arguments @(
    "data", "query",
    "--target-org", $targetOrgAlias,
    "--query", $opportunityQuery
)
$opportunityCount = [int]$opportunityQueryResult.result.totalSize

Write-Host ""
Write-Host "Org alias: $targetOrgAlias"
Write-Host "User: $userName ($username)"
Write-Host "User Id: $targetUserId"
Write-Host "Window: last $LastMinutes minute(s)"
Write-Host "Opportunities to delete: $opportunityCount"
Write-Host ""

if ($opportunityCount -eq 0) {
    return
}

Write-Host "Delete started..."

$anonymousApexResult = Invoke-SfAnonymousApex -ApexCode @"
DateTime createdAfterUtc = DateTime.valueOfGmt('$createdAfterUtc'.replace('T', ' ').replace('Z', ''));
List<Opportunity> opportunitiesToDelete = [
    SELECT Id
    FROM Opportunity
    WHERE CreatedById = '$targetUserId'
        AND CreatedDate >= :createdAfterUtc
];
Integer deletedCount = 0;
Integer failedCount = 0;
if (!opportunitiesToDelete.isEmpty()) {
    Database.DeleteResult[] deleteResults = Database.delete(opportunitiesToDelete, false);
    for (Database.DeleteResult deleteResult : deleteResults) {
        if (deleteResult.isSuccess()) {
            deletedCount++;
        } else {
            failedCount++;
        }
    }
}
System.debug('CODX_DELETE_RESULT deleted=' + deletedCount + ';failed=' + failedCount);
"@

if (-not $anonymousApexResult.result.success) {
    if ($anonymousApexResult.result.exceptionMessage) {
        throw $anonymousApexResult.result.exceptionMessage
    }

    throw "Anonymous Apex deletion failed."
}

$deleteSummaryMatch = [regex]::Match($anonymousApexResult.result.logs, "CODX_DELETE_RESULT deleted=(\d+);failed=(\d+)")

if (-not $deleteSummaryMatch.Success) {
    throw "Anonymous Apex deletion completed but the delete summary was not found in the logs."
}

$deletedCount = [int]$deleteSummaryMatch.Groups[1].Value
$failedCount = [int]$deleteSummaryMatch.Groups[2].Value

Write-Host ""
Write-Host "Deleted opportunities: $deletedCount"
Write-Host "Failed deletions: $failedCount"
