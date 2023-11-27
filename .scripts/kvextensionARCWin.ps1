# NOTE
# Remeber to assign to the Service Principal of the ARC Server the "Key Vault Secret User" role on the Key Vault 

# Customizable variables
$vmName = "win01"                # Name of the VM where the extension will be deployed
$VMresourceGroupName = "certlc" # Resource group where the VM is located
$location = "westeurope"        # Location of the VM
$keyVaultName = "DEMO-KV-fab01"          # Name of the Key Vault holding the certificate
$certifcateName = "democert"    # Name of the certificate in the Key Vault
$pollingInterval = "43200"      # Polling interval in seconds (e.g. 43200 = 12 hours)

# Build settings on ARC Windows Server

$Settings = @{
    secretsManagementSettings = @{
        pollingIntervalInS = $pollingInterval
        linkOnRenewal = $false
        observedCertificates = @(
            @{
                url = "https://$keyVaultName.vault.azure.net:443/secrets/$certifcateName"
                certificateStoreName = "MY"
                certificateStoreLocation = "LocalMachine"
                keyExportable = $true
                accounts = @("Network Service", "Local Service")
            }
            # Add more here, don't forget a comma on the preceding line
        )
        # The cert store location is optional, the default path is shown below
        # certificateStoreLocation = "/var/lib/waagent/Microsoft.Azure.KeyVault.Store/"
    }
    authenticationSettings = @{
        msiEndpoint = "http://localhost:40342/metadata/identity"
    }
}

$extName = "KeyVaultForWindows"
$extPublisher = "Microsoft.Azure.KeyVault"
$extType = "KeyVaultForWindows"
# Start the deployment on Windows ARC Server
New-AzConnectedMachineExtension -ResourceGroupName $VMresourceGroupName -MachineName $vmName -Name $extName -Location $location -Publisher $extPublisher -ExtensionType $extType -Setting $Settings

