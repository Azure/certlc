param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData
)

# START FUNCTIONS SECTION #
function certlcworkflow {
    param (
        $WebhookData,
        $queuedMessage
    )

    $continue = $true
  
    if ($WebhookData) { # Check that Webhookdata is not null

        $body = (ConvertFrom-Json -InputObject $WebhookData[0])
        
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

        # Get certificate from key vault

        $cert = $null
        try {
            $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -name $ObjectName
            $SubjectName = $cert.Certificate.Subject
            $IssuerName = $cert.Certificate.Issuer
            $Recipient = $cert.Tags.recipient
        } catch {
            Write-Output "Error getting certificate from Key Vault"
            Write-Error "Error getting certificate from Key Vault"
            throw "Error getting certificate from Key Vault"
            $continue = $false
        }
        
        if ($cert -eq $null) {
            Write-Output "Error getting certificate from Key Vault $VaultName"           
            Write-Error "Error getting certificate from Key Vault $VaultName"
            throw "Error getting certificate from Key Vault: $VaultName"
            
        }

        if ($continue) {
            write-output "SubjectName = $SubjectName"
            write-output "IssuerName = $IssuerName"


            # GET OID of the Certificate Template
            $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.20.2"}
            if (!$temp) {
                $temp = $cert.Certificate.Extensions | ?{$_.Oid.Value -eq "1.3.6.1.4.1.311.21.7"}
            }
            $temp = $temp.Format(0)
 
            $oid=$null
            $substring = $temp -match '\((.*?)\)' | Out-Null
            if ($matches -ne $null -and $matches.Count -gt 0) {
                $oid = $matches[1]
                write-output "OID = $oid"
            } 

            if ($oid -eq $null) {
                $split = $temp -split ","
                $template = $split[0]
                $templateSplit = $template -split "="
                $oid = $templateSplit[1]
                write-output "OID = $oid"
            }        
            
            if ($oid -eq $null) {
                $pattern = 'Template=([\d.]+)'
                if ($temp -match $pattern) {
                    $oid = $matches[1]
                    write-output "OID = $oid"
                } 
            }

            # Check if exisiting CSR is present
            $result = Get-AzKeyVaultCertificateOperation -VaultName $VaultName -Name $ObjectName | where {$_.Status -eq "inProgress"}
            $CSR = $result.CertificateSigningRequest


            if ($CSR -eq $null) {
                # Generate CSR in Key Vault
                try {
                    $Policy = New-AzKeyVaultCertificatePolicy -SecretContentType "application/x-pkcs12" -SubjectName $SubjectName -IssuerName "Unknown" -ReuseKeyOnRenewal
                    $result = Add-AzKeyVaultCertificate -VaultName $VaultName -Name $ObjectName -CertificatePolicy $Policy
                    $CSR = $result.CertificateSigningRequest
                } catch {
                    Write-Output "Error generating CSR in Key Vault"
                    Write-Error "Error generating CSR in Key Vault"
                    throw "Error generating CSR in Key Vault"
                    $continue = $false
                }
            }
        }

        if ($continue) {
            ########################
            # Internal CA commands
            ########################
            Write-Output "Internal CA commands"

            $CAServer = Get-AutomationVariable -Name 'CAServer'

            # Create a temporary file
            $tempFile = [System.IO.Path]::GetTempFileName()
            # Write the CSR content to the temporary file
            Set-Content -Path $tempFile -Value $CSR

            # Issue the Certificate from the PKI
            try {
                $CA = Get-CertificationAuthority -ComputerName $CAServer
                $certificateRequest = Submit-CertificateRequest -CA $CA -Path $tempFile -Attribute "CertificateTemplate:$($oid)"
                $certificate = $certificateRequest.Certificate
            } catch {
                Write-Output "Error issuing certificate from PKI"
                Write-Error "Error issuing certificate from PKI"
                throw "Error issuing certificate from PKI"
                $continue = $false
            }
        }

        if ($continue) {
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
                Write-Output "Error importing certificate to Key Vault"
                Write-Error "Error importing certificate to Key Vault"
                throw "Error importing certificate to Key Vault"
                $continue = $false
            }
        }

        if ($continue) {
            # Delete $tempFile 
            Remove-item -Path $tempFile  -Force
            Write-Output "Removed temporary file $tempFile" 

            # Send notification email to recipient
            if ($null -ne $Recipient){
                try {
                    $tag =  @{recipient = $Recipient}
                    $newCert | Update-AzKeyVaultCertificate -Tag $tag
                    #Get Date
                    $MailDate = Get-Date -format "dd/MM/yyyy"
                    
                    #Configuration Variables for E-mail
                    $SmtpServer = Get-AutomationVariable -Name 'SMTPserver'
                    #$SmtpServer = "CA01" #TODO: Comment this row and enable the previous : ONLY FOR DEBUG   
                                    
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
                        <tr style="border-bottom-style: solid; border-bottom-width: 1px; padding-bottom: 1px; border: 1px">
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
                    Write-Output "Error sending email notification"
                    Write-Error "Error sending email notification"
                    throw  "Error importing certificate to Key Vault"
                }
            }
 
            # Remove message from queue    
            write-output "Remove the message from the queue"
            try {
                $queue.CloudQueue.DeleteMessage($queuedMessage.Result.Id,$queuedMessage.Result.popReceipt)    
            }catch {
                write-output ("Error deleting the message (" + $queuedMessage.Result.Id + ") from the queue")
                Write-Error ("Error deleting the message (" + $queuedMessage.Result.Id + ") from the queue")
                throw "Error importing certificate to Key Vault"
            }

        }
    }

}
            

# END FUNCTIONS SECTION #

$environmentVariable = Get-ChildItem env:
$HybridWorker = ($environmentVariable | Where-Object { $_.name -like 'Fabric_*' } ).count -eq 0

$ErrorActionPreference = "Continue"  # Display any error message and attempt to continue execution of subsequence commands.

#Check Wether the script is running on Azure or on Hybrid Worker
if ($HybridWorker ) {   
    Write-Output "Running on Hybrid Worker"

    $continue = $true

    # Connect to Azure
    write-output "Connect to Azure"
    try {
        Connect-AzAccount -Identity
    } catch {
        write-output "Error connecting to Azure"
        Write-Error "Error connecting to Azure"
        throw "Error connecting to Azure"
        $continue = $false
    }

    if ($continue) {
        #Get Storage Account Queue Context
        $storageAccountName = Get-AutomationVariable -Name 'StorageAccount'
        $resourceGroup= Get-AutomationVariable -Name 'resourceGroup'

        #$storageAccountName = "famascicertclcsa" #TODO: Comment this row and enable the previous : ONLY FOR DEBUG 
        #$resourceGroup= "CERTLC" #TODO: Comment this row and enable the previous : ONLY FOR DEBUG 

        $queueName = "certlc"

        try {
            $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
        } catch {
            write-output "Error getting storage account"
            Write-Error "Error getting storage account"
            throw "Error getting storage account"
            $continue = $false
        }
    }
    if ($continue) {
        # wait before checking the queue
        Start-Sleep -Seconds 5

        # Retrieve the queue
        try {
            $queue = Get-AzStorageQueue -Name $queueName -Context $ctx
        } catch {
            write-output "Error getting the queue"
            Write-Error "Error getting the queue"
            throw "Error getting the queue"
            $continue = $false
        }
    }
    if ($continue) {
        $invisibleTimeout = [System.TimeSpan]::FromSeconds(1)
        write-output ("Queued messages " + $queue.ApproximateMessageCount)

        for ($i = 1; $i -le $queue.ApproximateMessageCount; $i++ ) {
            $queuedMessage = $queue.CloudQueue.GetMessageAsync($invisibleTimeout,$null,$null)
            write-output $queuedMessage 
            $WebhookData = $queuedMessage.Result.AsString

            write-output ("WebhookData " + $WebhookData)

            certlcworkflow -WebhookData $WebhookData, -queuedMessage $queuedMessage
        }
    }


    write-output "end"
}
else {

    Write-Output "ERROR: This script must be run from an Azure Automation Hybrid Worker"        
    Write-Output "To install a Hybrid Worker please read:"
    Write-Output "https://docs.microsoft.com/azure/automation/automation-hybrid-runbook-worker#install-the-hybrid-runbook-worker"
    Write-Error "This script must be run from an Azure Automation Hybrid Worker"
    throw "This script must be run from an Azure Automation Hybrid Worker"
}
