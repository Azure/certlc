# NOTE
# Remeber to assign to the system managed identity of the VM the "Key Vault Secret User" role on the Key Vault 

# Customizable variables
$vmName = "lin01"               # Name of the VM where the extension will be deployed
$VMresourceGroupName = "certlc" # Resource group where the VM is located
$location = "westeurope"        # Location of the VM
$keyVaultName = "DEMO-KV-fab01" # Name of the Key Vault holding the certificate
$certifcateName = "democert"    # Name of the certificate in the Key Vault
$pollingInterval = "43200"      # Polling interval in seconds (e.g. 43200 = 12 hours)


# Build settings on Linux VM
$Settings = @'
{
   "secretsManagementSettings": {
        "pollingIntervalInS": "POLLINGPLACEHOLDER",
        "certificateStoreLocation": "/var/lib/waagent/Microsoft.Azure.KeyVault/certs",
        "observedCertificates": ["https://KVPLACEHOLDER.vault.azure.net:443/secrets/CERTPLACEHOLDER"]
    }      
}
'@ 

$Settings = $Settings.Replace("POLLINGPLACEHOLDER",$pollingInterval)
$Settings = $Settings.Replace("KVPLACEHOLDER",$keyVaultName)
$Settings = $Settings.Replace("CERTPLACEHOLDER",$certifcateName)

$extName = "KeyVaultForLinux"
$extPublisher = "Microsoft.Azure.KeyVault"
$extType = "KeyVaultForLinux"

# Start the deployment on Linux VM
Set-AzVmExtension -TypeHandlerVersion "2.0" -EnableAutomaticUpgrade $true -ResourceGroupName $VMresourceGroupName -Location $location -VMName $vmName -Name $extName -Publisher $extPublisher -Type $extType -SettingString $settings
