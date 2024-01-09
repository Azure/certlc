param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData
)

write-output "start"
write-output $WebhookData.RequestBody
#write-output $WebhookData
try {
    if ($WebhookData.RequestBody) {
        $body = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
        
        # VARIABLE FROM WEBHOOK QUERY
        $VaultName = $body.data.VaultName
        $ObjectName = $body.data.ObjectName

        write-output "VaultName =  $VaultName"
        write-output "ObjectName =  $ObjectName"

        # Import PSPKI module
        write-output  "Import PSPKI module"
        Import-Module PSPKI

        ########################
        # Keyvault commands
        ########################

        # Connect to Azure
        try {
            Connect-AzAccount -Identity
        } catch {
            Write-Error "Error connecting to Azure: $_"
            throw
        }

        # Get certificate from key vault
        try {
            $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -name $ObjectName
            $SubjectName = $cert.Certificate.Subject
            $IssuerName = $cert.Certificate.Issuer
            $Recipient = $cert.Tags.recipient
        } catch {
            Write-Error "Error getting certificate from Key Vault: $_"
            throw
        }

        write-output "SubjectName = $SubjectName"
        write-output "IssuerName = $IssuerName"

        # GET OID of the Certificate Template

        $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.20.2"}
        if (!$temp) {
            $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.21.7"}
        }
        $temp = $temp.Format(0)
        write-output "temp = $temp"      
        $oid=$null
        $substring = $temp -match '\((.*?)\)' | Out-Null
        if ($matches -ne $null -and $matches.Count -gt 0) {
            $oid = $matches[1]
            write-output "OID1 = $oid"
        } 

        if ($oid -eq $null) {
            $split = $temp -split ","
            $template = $split[0]
            $templateSplit = $template -split "="
            $oid = $templateSplit[1]
            write-output "OID2 = $oid"
        }        
        
        if ($oid -eq $null) {
            $pattern = 'Template=([\d.]+)'
            if ($temp -match $pattern) {
                $oid = $matches[1]
                write-output "OID3 = $oid"
            } 
        }

        # Generate CSR in Key Vault
        try {
            $Policy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName $SubjectName -IssuerName "Unknown" -ReuseKeyOnRenewal
            $result = Add-AzKeyVaultCertificate -VaultName $VaultName -Name $ObjectName -CertificatePolicy $Policy
            $CSR = $result.CertificateSigningRequest
        } catch {
            Write-Error "Error generating CSR in Key Vault: $_"
            throw
        }

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
        $CAServer = Get-AutomationVariable -Name 'CAserver'
        try {
            $certificateRequest = Submit-CertificateRequest -CA $CAServer -Path $tempFile -Attribute "CertificateTemplate:$($oid)"
            $certificate = $certificateRequest.Certificate
        } catch {
            Write-Error "Error issuing certificate from PKI: $_"
            throw
        }

        Write-Output "Submit-CertificateRequest -CA $CAServer -Path $tempFile -Attribute ""CertificateTemplate:$($oid)"""
        Write-Output $certificateRequest
        Write-Output $certificate

        # Export certificate in a temporary file
        Export-Certificate -Cert $certificate -FilePath $tempFile

        ########################
        # Keyvault commands
        ########################

        Write-Output "Recipient: $Recipient"
        # Import the new certificate in the Key Vault
        try {
           
            $newCert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $ObjectName -FilePath $tempFile 
        } catch {
            Write-Error "Error importing certificate to Key Vault: $_"
            throw
        }
        
        # Delete $tempFile 
        Remove-item -Path $tempFile  -Force
        Write-Output "Removed temporary file $tempFile" 

        if ($null -ne $Recipient) {
            $tag =  @{recipient = $Recipient}
            $newCert | Update-AzKeyVaultCertificate -Tag $tag
        }

        $SmtpServer = Get-AutomationVariable -Name 'SMTPserver'
        # Send notification email to recipient
        if ($null -ne $Recipient -and $SmtpServer -ne ""){
            try {
                
                #Get Date
                $MailDate = Get-Date -format "dd/MM/yyyy"
                
                #Configuration Variables for E-mail
                $EmailFrom = "Certificate LifeCycle Automation <clc@demo.com>"
                $Recipient = $Recipient.Replace(";",",")
                $Recipient = $Recipient.split(",") #convert to array of comma separated recipients
                $EmailTo = $Recipient 
                $EmailSubject = "Certificate $ObjectName renewed"
                #HTML Template
                $EmailBody = @"
                <table style="width: 90%" style="border-collapse: collapse; border: 1px solid #008080;">
                    <tr>
                        <td colspan="2" bgcolor="#008080" style="color: #FFFFFF; font-size: large; font-family: Calibri; height: 35px;">
                            Certificate LifeCycle Automation - Certificate Update Notification Maildate
                        </td>
                    </tr>
                    <tr style="border-bottom-style: solid; border-bottom-width: 1px; padding-bottom: 1px">
                        <td style="border: 1px; width: 500px; height: 35px;font-family: Calibri;"> Updated Certificate</td>
                        <td style="border: 1px; text-align: center; height: 35px; width: 200px;font-family: Calibri;">
                        <b>CertName</b></td>
                    </tr>
                    <tr style="height: 39px; border: 1px solid #008080">
                        <td style="border: 1px; width: 500px; height: 35px;font-family: Calibri;">  New Expiration Time</td>
                        <td style="border: 1px; text-align: center; height: 35px; width: 200px; font-family: Calibri;">
                        <b>NewExpTime</b></td>
                    </tr>
                </table>
"@

                $EmailBody= $EmailBody.Replace("CertName",$ObjectName)
                $EmailBody= $EmailBody.Replace("Maildate",$Maildate)
                $EmailBody= $EmailBody.Replace("NewExpTime",$($newCert.certificate.NotAfter).ToString("dd/MM/yyyy HH:mm:ss"))
                
                #Send E-mail from PowerShell script
                Send-MailMessage -To $EmailTo -From $EmailFrom -Subject $EmailSubject -Body $EmailBody -BodyAsHtml -SmtpServer $SmtpServer

            } catch {
                Write-Error "Error sending email notification: $_"
                throw
            }
        }

        # Check if any of the specified variables are null and exit if true
        if ($VaultName -eq $null -or $ObjectName -eq $null -or $oid -eq $null -or $SubjectName -eq $null -or $IssuerName -eq $null -or $CSR -eq $null -or $certificateRequest -eq $null) {
            Write-Error "One or more required variables are null. Exiting..."
            return
        }
    }
} catch {
    Write-Error "An error occurred: $_"
}

write-output "end"
