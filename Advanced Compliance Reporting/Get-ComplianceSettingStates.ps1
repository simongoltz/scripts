<#.  
SCRIPTNAME: Get-ComplianceSettingStates.ps1
AUTHOR: Simon Goltz
COMPANY: synalis GmbH
WEBSITE: https://www.synalis.de

Last Updated: 11/09/2022
Version 1.0

This script retreives compliance settings from Graph and ships it to log analytics. 
It is supposed to run in an Azure Automation Workbook.

Prerequisites:
- App Registration with Read Access to DeviceManagement
- Get Log Analytics Workspace
- Import MSAL.PS Module
- Set Variables in Automation Account as per names

If the above requirements are not met, results will be inconsistent.
This script is provided as-is, without support.

BSD 3-Clause License

Copyright (c) 2022, Simon Goltz / synalis GmbH & Co. KG
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Version History
    11.9.2022: Initial Release

Please use the repo https://github.com/simongoltz/scripts for bug fixes and feature requests.
#>

# Azure Automation Variables
# Replace with your Workspace ID
$workspaceId = Get-AutomationVariable -Name WorkspaceId
# Replace with your Primary Key
$primaryKey = Get-AutomationVariable -Name primaryKey
# Specify the name of the table that should be filles in Log Analytics
$LogType = "Compliance_Daily_V1"

# Connect to Microsoft Graph API, fill in Variables from Automation Account
$authparams = @{
    ClientId = Get-AutomationVariable -Name ClientId
    TenantId = Get-AutomationVariable -Name TenantId
    ClientSecret = (Get-AutomationVariable -Name ClientSecret | ConvertTo-SecureString -AsPlainText -Force)
}
$auth = Get-MsalToken @authParams

$authorizationHeader = @{
    Authorization = $auth.CreateAuthorizationHeader()
}

$requestBody = @{
    Method      = 'Get'
    Headers     = $authorizationHeader
    ContentType = 'Application/Json'
}

#Get All ComplianceSettingStates filtered for windows
$resultComplianceSettingStates = Invoke-RestMethod @requestBody -uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries?`$filter=platformType eq 'windows10AndLater'"

$complianceSettingStates = $resultComplianceSettingStates.value.id
$reportStates = @()

#Go through every setting state and get assigned devices + status
foreach ($complianceSettingState in $complianceSettingStates){

    $statesUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/$complianceSettingState/deviceComplianceSettingStates"
    
    do {
    
    $states = Invoke-RestMethod @requestBody -uri $statesUri
    $reportStates += $states.value
	$statesUri = $states."@odata.nextLink"

    } while ($statesUri)

}

$reportStates = $reportStates | ConvertTo-Json

# Create the function to create the authorization signature
Function Build-Signature ($workspaceId, $primaryKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource

    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($primaryKey)

    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $workspaceId,$encodedHash
    return $authorization
}

# Create the function to create and post the request
Function Post-LogAnalyticsData($customerId, $primaryKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -workspaceId $workspaceId `
        -primaryKey $primaryKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $workspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode

}

# Submit the data to the API endpoint
Post-LogAnalyticsData -workspaceId $workspaceId -primaryKey $primaryKey -body ([System.Text.Encoding]::UTF8.GetBytes($reportStates)) -logType $logType