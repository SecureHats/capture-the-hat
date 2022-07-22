Function Get-GraphRequestRecursive {
    [CmdletBinding()]
    [Alias()]
    Param
    (
        # Graph access token
        [Parameter(Mandatory = $true,
            Position = 0)]
        [String] $AccessToken,

        # Graph url
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [String] $Url
    )

    Write-Debug "Fetching url $Url"
    $Result = Invoke-RestMethod $Url -Headers @{Authorization = "Bearer $AccessToken" } -Verbose:$false
    if ($Result.value) {
        $Result.value
    }

    # Calls itself when there is a nextlink, in order to get next page
    if ($Result.'@odata.nextLink') {
        Get-GraphRequestRecursive -Url $Result.'@odata.nextLink' -AccessToken $AccessToken
    }
}

Function Invoke-Main {
    Param
    (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            Position = 0)]
        $String
    )

        return "flag: {cth-BypassTheFunctionKey}"
}

Function ConvertFrom-Base64JWTLengthHelper {
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        $String
    )

    Process {
        $Length = $String.Length
        if ($String.Length % 4 -ne 0) {
            $Length += 4 - ($String.Length % 4)
        }
        return $String.PadRight($Length, "=")
    }
}

Function ConvertFrom-Base64JWT {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        $Base64JWT
    )

    Begin {
    }
    Process {
        $Spl = $Base64JWT.Split(".")
        [PSCustomObject] @{
            Header  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((ConvertFrom-Base64JWTLengthHelper $Spl[0]))) | ConvertFrom-Json
            Payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((ConvertFrom-Base64JWTLengthHelper $Spl[1]))) | ConvertFrom-Json
        }
    }
    End {
    }
}

Function Update-LocalMembership {
    [CmdletBinding()]
    param (

        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0)]
        [string]$AdGroup,

        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [string]$UserAccount,

        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 2)]
        [string]$Action

    )

    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    $AdGroupPrefix = $env:AdGroupPrefix

    if ($AdGroupPrefix) {
        if (-not($AdGroup -like "$AdGroupPrefix*")) {
            break
        }
    }

    try {
        $accessToken = Get-MSIMSGraphAccessToken
    }
    catch {
        Write-Warning "Unable to request an Access Token"
        break
    }

    try {
        $UserObject = (Get-GraphRequestRecursive `
                -Url "https://graph.microsoft.com/beta/users/?`$filter=id eq '$($UserAccount)'&`$select=onPremisesDistinguishedName, displayName" `
                -accessToken $accessToken)

        if (-not($UserObject.onPremisesDistinguishedName)) {
            Write-Warning "Group Member '$($UserObject.displayName)' in group '$($AdGroup)' is not synced from AD and will be ignored"
            break
        }
    }
    catch {
        Write-Output "Error occured in Graph API Call."
        Get-GraphPermissions -accessToken $accessToken
        break
    }

    $secretPrefix               = "$env:secretPrefix"
    $hybridEndpoint             = "$env:HybridEndpoint"
    $userName                   = (Get-AzKeyVaultSecret -VaultName $env:KeyVault -Name $secretPrefix-applicationId -AsPlainText)
    $securePassword             = (Get-AzKeyVaultSecret -VaultName $env:KeyVault -Name $secretPrefix-password).SecretValue
    [pscredential]$credential   = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)

    $arguments = @{
        ComputerName  = $HybridEndpoint
        Credential    = $credential
        Port          = 5986
        UseSSL        = $true
        ArgumentList  = "$($AdGroup)", "$($UserObject.onPremisesDistinguishedName)", $credential
        SessionOption = (New-PSSessionOption -SkipCACheck -SkipCNCheck)
    }

    switch ($Action) {
        "Add" {
            Invoke-Command @arguments `
                -ScriptBlock {
                param (
                    $adGroup,
                    $onPremDN,
                    $authObject
                )

                $serverName = '{0}.{1}' -f ($onPremDN -Split ",DC=" | Select-Object -Last 2)
                try{
                    Get-AdGroup -Identity $adGroup -Credential $authObject -Server $serverName
                }
                catch {
                    Write-Error "Request cannot be processed for group [$($adGroup)]"
                    break
                }
                Write-Output "Adding user '$($onPremDN)' to '$($adGroup)' on server '$($serverName)'"
                Add-AdGroupMember -Identity $adGroup -Members $onPremDN -Credential $authObject -Server "$($serverName)"
            }
        }
        "Remove" {
            Invoke-Command @arguments `
                -ScriptBlock {
                param (
                    $adGroup,
                    $onPremDN,
                    $authObject
                )

                $serverName = '{0}.{1}' -f ($onPremDN -Split ",DC=" | Select-Object -Last 2)
                try{
                    Get-AdGroup -Identity $adGroup -Credential $authObject -Server $serverName
                }
                catch {
                    Write-Error "Request cannot be processed for group '$($AdGroup)'"
                    break
                }
                Write-Output "Removing user '$($onPremDN)' from '$($adGroup)' on server '$($serverName)'"
                Remove-ADGroupMember -Identity $adGroup -Members $onPremDN -Credential $authObject -Server "$($serverName)" -Confirm:$false
            }
        }
        Default {}
    }
}

<#
.Synopsis
   Returns MSI access token
.DESCRIPTION
   Returns MSI access token
.EXAMPLE
   Get-MSIMSGraphAccessToken
#>
Function Get-MSIMSGraphAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    Param()

    Process {
        try {
            $ErrorVar = $null
            $_AccessToken = Invoke-RestMethod ($env:MSI_ENDPOINT + "?resource=https://graph.microsoft.com/&api-version=2017-09-01") `
                -Headers @{"Secret" = "$env:MSI_SECRET" } `
                -Verbose:$false `
                -ErrorVariable "ErrorVar"

            if ($ErrorVar) {
                Write-Error "Error when getting MSI access token: $ErrorVar"
            }
            else {
                Write-Debug "Got access token: $($_AccessToken.access_token)"
                return $_AccessToken.access_token
            }
        }
        catch {
            Write-Error "Error when getting MSI access token" -Exception $_
        }
    }
}

Function Get-GraphPermissions {
    [CmdletBinding()]
    [OutputType([string])]

    param(
        [Parameter(Mandatory = $true)]
        [string]$accessToken
    )

    $JWT = ConvertFrom-Base64JWT $accessToken
    if ($JWT.Payload.roles -notcontains "Group.Read.All") {
        Write-Warning "Could not find Group.Read.All in access token roles. Things might not work as intended. Make sure you have the correct scopes added."
    }

    if ($JWT.Payload.roles -notcontains "User.Read.All") {
        Write-Warning "Could not find User.Read.All in access token roles. Things might not work as intended. Make sure you have the correct scopes added."
    }

    if ($jwt.Payload.aud) {
        Write-Verbose " - oid:             $($jwt.payload.oid)"
        Write-Verbose " - aud:             $($jwt.payload.aud)"
        Write-Verbose " - iss:             $($jwt.payload.iss)"
        Write-Verbose " - appid:           $($jwt.payload.appid)"
        Write-Verbose " - app_displayname: $($jwt.payload.app_displayname)"
        Write-Verbose " - roles:           $($jwt.payload.roles)"
    }
}