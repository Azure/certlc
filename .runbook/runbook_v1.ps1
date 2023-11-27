param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData
)

write-output "start"
write-output $WebhookData.RequestBody

if ($WebhookData.RequestBody) { 
    $body = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

    # VARIABLE FROM WEBHOOK QUERY
    $VaultName = $body.data.VaultName
    $ObjectName = $body.data.ObjectName

    write-output "VaultName =  $vaultname"
    write-output "ObjectName =  $ObjectName"

    # Import PSPKI module
    write-output  "Import PSPKI module"
    Import-Module PSPKI

    ########################
    # Keyvault commands
    ########################

    # Connect to Azure
    Connect-AzAccount -Identity

    #get certificate from keyvault
    $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -name $ObjectName
    $SubjectName = $cert.Certificate.Subject
    $IssuerName = $cert.Certificate.Issuer

    write-output "SubjectName = $SubjectName"
    write-output "IssuerName = $IssuerName"

    # GET OID of the Certificate Template
    $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.20.2"}
    if (!$temp) {
        $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.21.7"}
    }
    $temp = $temp.Format(0)
    $substring = $temp -match '\((.*?)\)' | Out-Null
    $oid= $matches[1]
    write-output "OID1 = $oid"

    if ($oid -eq $null) {
        $split = $temp -split ","
        $template = $split[0]
        $templateSplit = $template -split "="
        $oid = $templateSplit[1]
        write-output "OID2 = $oid"
    }

   

    #Generate CSR in KeyVault
    $Policy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName $SubjectName -IssuerName "Unknown" -ReuseKeyOnRenewal
    $result = Add-AzKeyVaultCertificate -VaultName $VaultName -Name $ObjectName -CertificatePolicy $Policy
    $CSR = $result.CertificateSigningRequest

    write-output "CSR = $CSR"


    ########################
    # Internal CA commands
    ########################
    Write-Output "Internal CA commands"

    # Create a temporary file
    $tempFile = [System.IO.Path]::GetTempFileName()
    # Write the CSR content to the temporary file
    Set-Content -Path $tempFile -Value $CSR


    # Issue the Certificate from the PKI
    $certificateRequest = Submit-CertificateRequest -CA localhost -Path $tempFile -Attribute "CertificateTemplate:$($oid)"
    $certificate = $certificateRequest.Certificate

    Write-Output "Submit-CertificateRequest -CA localhost -Path $tempFile -Attribute ""CertificateTemplate:$($oid)"""
    Write-Output $certificateRequest
    Write-Output $certificate

    # Export certificate in a temporary file
    Export-Certificate -Cert $certificate -FilePath $tempFile



    ########################
    # Keyvault commands
    ########################

    #Import the new certificate in the Key Vault
    Import-AzKeyVaultCertificate -VaultName $VaultName -Name $ObjectName -FilePath $tempFile


}

write-output "end"