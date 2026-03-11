# Scripts

This folder contains PowerShell scripts for working only with the Salesforce org alias `SOHNUT-Votfound-full`.

Both scripts are hardcoded to the Salesforce user:
- `005Ae00000I178LIAR`

## 1. Get recent Opportunities

Script:
- `.\scripts\Get-RecentUserOpportunities.ps1`

What it does:
- finds `Opportunity` records created by user `005Ae00000I178LIAR`
- searches only in org alias `SOHNUT-Votfound-full`
- limits the search to the last `N` minutes
- runs a fast `COUNT()` query and prints only the total number of found records
- does not delete or modify anything

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-RecentUserOpportunities.ps1 -LastMinutes 10
```

Example:
- search for Opportunities created in the last 30 minutes

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-RecentUserOpportunities.ps1 -LastMinutes 30
```

## 2. Delete recent Opportunities

Script:
- `.\scripts\Delete-RecentUserOpportunities.ps1`

What it does:
- finds `Opportunity` records created by user `005Ae00000I178LIAR`
- searches only in org alias `SOHNUT-Votfound-full`
- limits the search to the last `N` minutes
- prints only the total number of records that match the window
- prints that deletion has started
- deletes those `Opportunity` records from the org through one Anonymous Apex execution
- prints how many deletes succeeded and how many failed

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Delete-RecentUserOpportunities.ps1 -LastMinutes 10
```

Example:
- delete Opportunities created in the last 15 minutes

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Delete-RecentUserOpportunities.ps1 -LastMinutes 15
```

## Notes

- `-LastMinutes` must be greater than `0`
- time filtering is calculated in UTC and converted to a Salesforce `CreatedDate >= ...Z` filter
- the delete script removes only the `Opportunity` records found by that exact search window
- if related `Payment` records are children through `Master-Detail`, Salesforce deletes them automatically together with the parent `Opportunity`
