# NOTE
# Remeber to assign to the system managed identity of the VM the "Key Vault Secret User" role on the Key Vault 

# Customizable variables
$vmName = "win01"                # Name of the VM where the extension will be deployed
$VMresourceGroupName = "certlc" # Resource group where the VM is located
$location = "westeurope"        # Location of the VM
$keyVaultName = "DEMO-KV-fab01"          # Name of the Key Vault holding the certificate
$certifcateName = "democert"    # Name of the certificate in the Key Vault
$pollingInterval = "43200"      # Polling interval in seconds (e.g. 43200 = 12 hours)


# Build settings on Windows VM
$Settings = @'
{
   "secretsManagementSettings": {
        "pollingIntervalInS": "POLLINGPLACEHOLDER",
        "linkOnRenewal": false,
        "observedCertificates":
        [
            {
                "url": "https://KVPLACEHOLDER.vault.azure.net:443/secrets/CERTPLACEHOLDER",
                "certificateStoreName": "MY",
                "certificateStoreLocation": "LocalMachine",
                "keyExportable": true,
                "accounts": [
                    "Network Service",
                    "Local Service"
                ]
            }
        ]
    }
}
'@ 

$Settings = $Settings.Replace("POLLINGPLACEHOLDER",$pollingInterval)
$Settings = $Settings.Replace("KVPLACEHOLDER",$keyVaultName)
$Settings = $Settings.Replace("CERTPLACEHOLDER",$certifcateName)

$extName = "KeyVaultForWindows"
$extPublisher = "Microsoft.Azure.KeyVault"
$extType = "KeyVaultForWindows"

# Start the deployment on Windows VM
Set-AzVmExtension -TypeHandlerVersion "3.0" -ResourceGroupName $VMresourceGroupName -Location $location -VMName $vmName -Name $extName -Publisher $extPublisher -Type $extType -SettingString $settings
