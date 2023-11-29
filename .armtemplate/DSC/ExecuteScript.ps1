configuration ExecuteScript
{

    Param 
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory=$true)]
        [String]$DCvmName,

        [Parameter(Mandatory=$true)]
        [String]$CAvmName,
        
        [Parameter(Mandatory=$true)]
        [String]$CAName,
    
        [Parameter(Mandatory=$true)]
        [String]$CDPURL,
    
        [Parameter(Mandatory=$true)]
        [String]$WebenrollURL,

        [Parameter(Mandatory=$true)]
        [String]$demoCertDNSName,

        [Parameter(Mandatory=$true)]
        [String]$keyVaultName,

        [Parameter(Mandatory=$true)]
        [String]$Recipient

    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration, PackageManagement
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node localhost
    {
  
        PackageManagementSource PSGallery
        {
            Ensure              = "Present"
            Name                = "PSGallery"
            ProviderName        = "PowerShellGet"
            SourceLocation      = "https://www.powershellgallery.com/api/v2"
            InstallationPolicy  = "Trusted"
        }

        PackageManagement PSModuleAzAccounts
        {
            Ensure               = "Present"
            Name                 = "Az.Accounts"
            MaximumVersion       = "2.12.1"
            MinimumVersion       = "2.12.1"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }
    
        PackageManagement PSModuleAzResources
        {
            Ensure               = "Present"
            Name                 = "Az.Resources"
            MaximumVersion       = "6.6.0"
            MinimumVersion       = "6.6.0"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }

        PackageManagement PSModuleAzCompute
        {
            Ensure               = "Present"
            Name                 = "Az.Compute"
            MaximumVersion        = "5.7.0"
            MinimumVersion        = "5.7.0"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }

        PackageManagement PSModuleAzKeyVault
        {
            Ensure               = "Present"
            Name                 = "Az.KeyVault"
            MaximumVersion       = "4.9.2"
            MinimumVersion       = "4.9.2"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }

        PackageManagement PSModuleADCSTemplate
        {
            Ensure               = "Present"
            Name                 = "ADCSTemplate"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }

        PackageManagement PSModulePSPKI
        {
            Ensure               = "Present"
            Name                 = "PSPKI"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }

        WindowsFeature ADPS
        {
            Name        = "RSAT-AD-PowerShell"
            Ensure      = "Present"
        }

        script 'ExecuteScript'
        {
            PsDscRunAsCredential = $DomainCreds
            GetScript       = { return @{result = 'result'} }
            TestScript      = { return $false }
            SetScript       = {

                # create a local folder named c:\temp\script and copy the "https://raw.githubusercontent.com/azure/certlc/main/.scripts/InstallEntRootCA.ps1" file into it
                $ScriptFolder="c:\temp\script"
                New-Item -Path $ScriptFolder -ItemType Directory -Force |Out-Null
                $ScriptName="InstallEntRootCA.ps1"
                $ScriptPath="$ScriptFolder\$ScriptName"
                $ScriptURL="https://raw.githubusercontent.com/Azure/certlc/main/.scripts/InstallEntRootCA.ps1"
                Invoke-WebRequest -uri $ScriptURL -OutFile $ScriptPath

                #Copy the utility to view the .eml file
                Invoke-WebRequest -uri "https://raw.githubusercontent.com/Azure/certlc/main/DemoTools/MailViewer.ps1" -OutFile "$ScriptFolder\Mailviewer.ps1"

                #add link to default desktop
                $desktopPath = 'C:\Users\Public\Desktop'
                $shortcutPath = Join-Path $desktopPath 'MailViewer.lnk'
                
                $WshShell = New-Object -comObject WScript.Shell
                $Shortcut = $WshShell.CreateShortcut($shortcutPath)
                $Shortcut.TargetPath = "powershell.exe"
                $Shortcut.Arguments = " -WindowStyle Hidden -ExecutionPolicy Bypass -File $ScriptFolder\Mailviewer.ps1"
                $iconPath = "$env:SystemRoot\explorer.exe,13"  # 13 is the index of the mail icon
                $Shortcut.IconLocation = $iconPath
                $Shortcut.Save()

                # then run the following command to execute the script
                Invoke-Expression "$ScriptPath -DCvmName $($using:DCvmName) -CAvmName $($using:CAvmName) -CAName $($using:CAName) -CDPURL $($using:CDPURL) -WebenrollURL $($using:WebenrollURL) -demoCertDNSName $($using:demoCertDNSName) -keyVaultName $($using:keyVaultName) -Recipient $($using:Recipient)"

            }            
        }
    
    } 
    
}