# Input bindings are passed in via param block.
param($Request, $TriggerMetadata, $eventHubMessages)

# Main
if ($env:MSI_SECRET -and (Get-Module -ListAvailable Az.Accounts)) {
    Connect-AzAccount -Identity
}

$body = Invoke-Main

switch -Wildcard ($eventHubMessages.records.operationName) {
    "Add member to role completed (PIM activation)" {
        $properties = $eventHubMessages.records.properties `
            | Where-Object category -eq "GroupManagement" `
            | Where-Object activityDisplayName -like "Add member to role completed (PIM activation)"

        if ($properties) {
            Update-LocalMembership `
                -UserAccount $($properties.targetResources[2].id) `
                -AdGroup $($properties.targetResources[3].displayName) `
                -Action "Add"
        }
    }
    "Remove member from role completed (PIM deactivate)" {
        $properties = $eventHubMessages.records.properties `
            | Where-Object category -eq "GroupManagement" `
            | Where-Object activityDisplayName -like "Remove member from role requested (PIM deactivate)"

        if ($properties) {
            Update-LocalMembership `
                -UserAccount $($properties.targetResources[2].id) `
                -AdGroup $($properties.targetResources[-2].displayName) `
                -Action "Remove"
        }
    }
    "Remove member from role (PIM activation expired)" {
        $properties = $eventHubMessages.records.properties `
            | Where-Object category -eq "GroupManagement" `
            | Where-Object activityDisplayName -like "Remove member from role (PIM activation expired)"

        if ($properties) {
            Update-LocalMembership `
                -UserAccount $($properties.targetResources[2].id) `
                -AdGroup $($properties.targetResources[-2].displayName) `
                -Action "Remove"
        }
    }
    Default {
        # "Nothing to process"
    }
}

Push-OutputBinding -Name Response -Clobber -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $body
})