param(
    [string]$InputCsv  = ".\spns.csv",
    [string]$OutputCsv = ".\spn-direct-rbac.csv",
    [switch]$SkipManagementGroups
)

$spnIds = Import-Csv $InputCsv |
    ForEach-Object { $_.SPNId.Trim().ToLower() } |
    Where-Object { $_ } |
    Sort-Object -Unique

$results = @()

foreach ($sub in Get-AzSubscription | Where-Object State -eq "Enabled") {
    Write-Host "Scanning subscription $($sub.Name)"

    try {
        Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId | Out-Null

        $results += Get-AzRoleAssignment |
            Where-Object { $spnIds -contains $_.ObjectId.ToLower() } |
            Select-Object `
                @{n="SPNId";e={$_.ObjectId}},
                DisplayName,
                ObjectType,
                RoleDefinitionName,
                RoleDefinitionId,
                Scope,
                @{n="ScopeType";e={
                    switch -Regex ($_.Scope) {
                        "^/subscriptions/[^/]+$" { "Subscription"; break }
                        "^/subscriptions/[^/]+/resourceGroups/[^/]+$" { "ResourceGroup"; break }
                        "^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/.+" { "Resource"; break }
                        default { "Other" }
                    }
                }},
                @{n="SubscriptionId";e={$sub.Id}},
                @{n="SubscriptionName";e={$sub.Name}},
                RoleAssignmentId
    }
    catch {
        Write-Warning "Failed on subscription $($sub.Name): $($_.Exception.Message)"
    }
}

if (-not $SkipManagementGroups) {
    foreach ($mg in Get-AzManagementGroup) {
        Write-Host "Scanning management group $($mg.Name)"

        try {
            $results += Get-AzRoleAssignment -Scope $mg.Id -AtScope |
                Where-Object { $spnIds -contains $_.ObjectId.ToLower() } |
                Select-Object `
                    @{n="SPNId";e={$_.ObjectId}},
                    DisplayName,
                    ObjectType,
                    RoleDefinitionName,
                    RoleDefinitionId,
                    Scope,
                    @{n="ScopeType";e={"ManagementGroup"}},
                    @{n="SubscriptionId";e={$null}},
                    @{n="SubscriptionName";e={$null}},
                    RoleAssignmentId
        }
        catch {
            Write-Warning "Failed on management group $($mg.Name): $($_.Exception.Message)"
        }
    }
}

$results |
    Sort-Object SPNId, Scope, RoleDefinitionName -Unique |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Export completed: $OutputCsv"
