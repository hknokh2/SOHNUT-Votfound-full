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
Write-Host "Found opportunities: $opportunityCount"
Write-Host ""
