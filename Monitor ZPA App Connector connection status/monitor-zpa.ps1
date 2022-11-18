<#
.SYNOPSIS
  This script calls the ZPA API and returns the connections status of your specified connector. Please adapt to your needs
.NOTES
  Version:        1.0
  Author:         Simon Goltz
  Creation Date:  02-12-2022
  Purpose/Change: Initial script development
#>
 
Add-Type -AssemblyName System.Web

# Add your Parameters
$client_id = "YourSuperLongClientID"
$client_secret = `yourPassword`
$customerId = ""
$connectorId = "" 

#Authentication
$authBody = @{
    client_id = $client_id
    client_secret = $client_secret
}

$authUri = "https://config.private.zscaler.com/signin"
$authRequest = Invoke-RestMethod -Uri $authUri -Method Post -Body $authBody
$token = $authRequest.access_token

#Query API for Connector Status
$requestHeader = @{Authorization = "Bearer $token"}
$getConnector = "https://config.private.zscaler.com/mgmtconfig/v1/admin/customers/" + $customerId + "/connector/" + $connectorId
$connector = Invoke-RestMethod -Uri $getConnector -Headers $requestHeader


