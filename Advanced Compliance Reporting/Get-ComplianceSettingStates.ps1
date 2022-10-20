<#.  
SCRIPTNAME: Get-ComplianceSettingStates.ps1
AUTHORS: Simon Goltz
COMPANY: synalis GmbH
WEBSITE: https://www.synalis.de
BLOG: https://simongoltz.com

Last Updated: 11/09/2022
Version 1.0
Version 1.1 - Mike van der Sluis, MyBestTools

This script retrieves compliance settings from Graph and ships it to log analytics. 
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
    11.09.2022: Initial Release
    20.10.2022: Batch processing added - Mike van der Sluis
Please use the repo https://github.com/simongoltz/scripts for bug fixes and feature requests.
#>

# Azure Automation Variables
# Replace with your Workspace ID
$workspaceId = Get-AutomationVariable -Name WorkSpaceID
# Replace with your Primary Key
$primaryKey = Get-AutomationVariable -Name PrimaryKey
# Specify the name of the table that should be filled in Log Analytics
$logType = "Compliance_Daily_V1"
$TimeStampField = ""

# Connect to Microsoft Graph API, fill in Variables from Automation Account
$authparams = @{
    TenantId = Get-AutomationVariable -Name TenantId
    ClientId = Get-AutomationVariable -Name ClientId
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

# Get All ComplianceSettingStates filtered for windows 
# !!! note the 'back-tick': remove when using graph-explorer, add when used here !!!
$resultComplianceSettingStates = Invoke-RestMethod @requestBody -uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries?`$filter=platformType eq 'windows10AndLater'"

$complianceSettingStates = $resultComplianceSettingStates.value.id
$reportStates = @()

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
Function Post-LogAnalyticsData($workspaceId, $primaryKey, $body, $logType)
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

# Function to process batches of 500 for every 
# retrieved batch of at max 1000 objects
Function Process-Batch($somereportStates)
{
	$x=0
	$reportBatch = @()
	foreach ($reportState in $somereportStates)
	{
		$x++
		$reportBatch+=$reportState
		if (($x%500) -eq 0)
		{
			Write-Output "Writing batch of 500 items to Log Analytics..."
			$reportBatch = $reportBatch | ConvertTo-Json
			Post-LogAnalyticsData -workspaceId $workspaceId -primaryKey $primaryKey -body ([System.Text.Encoding]::UTF8.GetBytes($reportBatch)) -logType $logType
			$reportBatch = @()
		}
	}

	if ($reportBatch.Count())
	{
		#post the rest if any
		Write-Output "Writing batch of $($reportBatch.Count()) items to Log Analytics..."
		Post-LogAnalyticsData -workspaceId $workspaceId -primaryKey $primaryKey -body ([System.Text.Encoding]::UTF8.GetBytes($reportBatch)) -logType $logType
	}
}

# Go through every setting state and get assigned devices + status 
# in batches of max 1000 devices
foreach ($complianceSettingState in $complianceSettingStates){

    $statesUri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicySettingStateSummaries/$complianceSettingState/deviceComplianceSettingStates"
    do { 
		$states = Invoke-RestMethod @requestBody -uri $statesUri
		$reportStates = $states.value
		$statesUri = $states."@odata.nextLink"
		Process-Batch -somereportStates $reportStates
	} while ($statesUri)
}
