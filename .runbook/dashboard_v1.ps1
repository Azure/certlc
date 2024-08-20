## global variable declaration
$global:currentTime
$global:bearerToken
$global:VaultName = Get-AutomationVariable -Name 'VaultName'
$global:dcrImmutableId = Get-AutomationVariable -Name 'dcrImmutableId'
$global:dcrEndpointUri = Get-AutomationVariable -Name 'dcrEndpointUri'
$global:streamName = Get-AutomationVariable -Name 'streamName'

## Functions sections

function sendData ($CertName,$CertIssuer,$CertThumbprint,$CertSubject, $CertExpiration, $CertRecipient) {

$staticData = @"
[
{
    "Time": "$currentTime",
    "KeyVault": "$VaultName",
    "CertName": "$CertName",
    "CertIssuer":  "$CertIssuer",
    "CertThumbprint": "$CertThumbprint",
    "CertSubject": "$CertSubject",
    "CertExpiration": "$CertExpiration",
    "CertRecipient": "$CertRecipient"
}
]
"@;

    ### Send the data to the Log Analytics workspace.

    $body = $staticData;
    $headers = @{"Authorization"="Bearer $bearerToken";"Content-Type"="application/json"};
    $uri = "$dcrEndpointUri/dataCollectionRules/$dcrImmutableId/streams/$($streamName)?api-version=2023-01-01"

    $uploadResponse = Invoke-RestMethod -Uri $uri -Method "Post" -Body $body -Headers $headers

}

## END functions section


$authResult = Connect-AzAccount -Identity
Write-Output "Connessione AD: " $authResult

Add-Type -AssemblyName System.Web

## Step 0: Set variables required for the rest of the script.

### information needed to authenticate to AAD and obtain a bearer token
$tenantId = (Get-AzContext).Tenant.Id   #Tenant ID the data collection endpoint resides in

## Step 1: Obtain a bearer token used later to authenticate against the DCR.

$resource = "https://monitor.azure.com"

$authResult = Get-AzAccessToken -ResourceUrl $resource
$bearerToken = $authResult.Token


### Debugging: Print token and other info
Write-Output "Access Token: $bearerToken"
Write-Output "Endpoint URI: $dcrEndpointUri"
Write-Output "DCR Immutable ID: $dcrImmutableId"
Write-Output "Stream Name: $streamName"
Write-Output "VaultName : $VaultName"
                           
### Get certificate from key vault

$cert = $null
try {
    $certificates = Get-AzKeyVaultCertificate -VaultName $VaultName 
    $currentTime = Get-Date ([datetime]::UtcNow) -Format O

    foreach ($certificate in $certificates) {
        $cert= Get-AzKeyVaultCertificate -VaultName $VaultName -Name $certificate.Name
        $SubjectName = $cert.Name
        $IssuerName = $cert.Certificate.Issuer
        $Recipient = $cert.Tags.recipient
        $Expiration = $cert.Expires
        $Thumbprint = $cert.Certificate.Thumbprint
        Write-Output $SubjectName
        Write-Output $IssuerName
        Write-Output $Recipient 
        Write-Output $Expiration
        Write-Output $Thumbprint

        sendData $certificate.Name $IssuerName $Thumbprint $SubjectName $Expiration $Recipient


      }
    } catch {
        Write-Output "Error getting certificates from Key Vault or sending data to Log Analytics"
        Write-Error "Error getting certificates from Key Vault or sending data to Log Analytics"
        throw "Error getting certificates from Key Vault or sending data to Log Analytics"
        $continue = $false
    }
        
    if ($cert -eq $null) {
        Write-Output "Error getting certificates from Key Vault $VaultName"           
        Write-Error "Error getting certificatse from Key Vault $VaultName"
        throw "Error getting certificates from Key Vault: $VaultName"
            
    }




############## FAKE ENTRIES ##############

#EXPIRED
sendData "EXPIRED-01" "CN=FAKECA, O=FAKE, C=COM" "B05C15BCA7CE82B06BDA23A789D83CB004EDFD90" "expired.fake.com" (Get-Date ([datetime]::UtcNow)).AddDays(-2) "jdoe@fake.com"

#EXPIRING
sendData "EXPIRING-01" "CN=FAKECA, O=FAKE, C=COM" "C05C15BCA7CE82B06BDA23A789D83CB004EDFD90" "expiring.fake.com" (Get-Date ([datetime]::UtcNow)).AddDays(2) "jdoe@fake.com"


#NOT EXPIRED
sendData "GOOD-01" "CN=FAKECA, O=FAKE, C=COM" "D05C15BCA7CE82B06BDA23A789D83CB004EDFD90" "good.fake.com" (Get-Date ([datetime]::UtcNow)).AddYears(5) "jdoe@fake.com"
   