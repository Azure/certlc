# NOTE
# Remeber to assign to the system managed identity of the ARC Server the "Key Vault Secret User" role on the Key Vault 

# Customizable variables
$vmName = "VM01"                # Name of the VM where the extension will be deployed
$VMresourceGroupName = "certlc" # Resource group where the VM is located
$location = "westeurope"        # Location of the VM
$keyVaultName = "KV01"          # Name of the Key Vault holding the certificate
$certifcateName = "democert"    # Name of the certificate in the Key Vault
$pollingInterval = "43200"      # Polling interval in seconds (e.g. 43200 = 12 hours)


# Build settings on ARC Linux Server
$Settings = @{
    secretsManagementSettings = @{
        observedCertificates = @(
            "https://$keyVaultName.vault.azure.net:443/secrets/$certifcateName"
            # Add more here, don't forget a comma on the preceding line
        )
        # The cert store location is optional, the default path is shown below
        # certificateStoreLocation = "/var/lib/waagent/Microsoft.Azure.KeyVault.Store/"
        pollingIntervalInS   = $pollingInterval 
    }
    authenticationSettings    = @{
        msiEndpoint = "http://localhost:40342/metadata/identity"
    }
}

$extName = "KeyVaultForLinux"
$extPublisher = "Microsoft.Azure.KeyVault"
$extType = "KeyVaultForLinux"

# Start the deployment on Linux ARC Server
New-AzConnectedMachineExtension -ResourceGroupName $VMresourceGroupName -MachineName $vmName -Name $extName -Location $location -Publisher $extPublisher -ExtensionType $extType -Setting $Settings

