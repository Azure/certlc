Param 
(

    [Parameter(Mandatory=$true)]
    [String]$DCvmName,

    [Parameter(Mandatory=$true)]
    [String]$CAName,

    [Parameter(Mandatory=$true)]
    [String]$CAvmName,
 
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

#region modules
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Import-Module ActiveDirectory -Force
Import-Module ADCSTemplate -Force
#end region modules



#region normalize URL to FQDN
if ($CDPURL -like "http://*" -or $CDPURL -like "https://*")
{
    $CDPURL = $CDPURL.Split('/')[2]
 
}
 
if ($WebenrollURL -like "http://*" -or $WebenrollURL -like "https://*")
{
    $WebenrollURL = $WebenrollURL.Split('/')[2]
 
}
#endregion normalize URL to FQDN 
 
#region checks
if (!([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Verbose 'Script can only run elevated' -Verbose
    break
}
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent() 
$WindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($CurrentUser)
if (!($WindowsPrincipal.IsInRole('Enterprise Admins')))
{
    Write-Verbose 'Script can only run with Enterprise Administrator privileges' -Verbose
    break
}
#endregion checks
 
#region install required roles and features
Install-WindowsFeature -Name ADCS-Cert-Authority,ADCS-Enroll-Web-Pol,ADCS-Enroll-Web-Svc,SMTP-Server,Web-Mgmt-Console,WEB-WMI -IncludeManagementTools
#endregion install required roles and features
 
#region Install Enterprise Root CA
try
{
    Install-AdcsCertificationAuthority -WhatIf
}
catch
{
    Write-Verbose 'A CA is already installed on this server, cleanup server and AD before running this script again' -Verbose
    break
}

 
New-Item C:\Windows\capolicy.inf -ItemType file -Force | Out-Null
@"
[Version]
Signature="`$Windows NT$"
 
[PolicyStatementExtension]
Policies=InternalUseOnly
[InternalUseOnly]
OID=2.5.29.32.0
Notice="This CA is used for the Cert Life Cycle DEMO environment"
 
[Certsrv_Server]
LoadDefaultTemplates=0
AlternateSignatureAlgorithm=1
 
[Extensions]
2.5.29.15 = AwIBBg==
Critical = 2.5.29.15
"@ | Out-File C:\Windows\capolicy.inf -Force
 
Install-AdcsCertificationAuthority -CACommonName $CAName `
                                   -CAType EnterpriseRootCA `
                                   -CADistinguishedNameSuffix 'O=DEMO,C=IT' `
                                   -HashAlgorithmName sha256 `
                                   -ValidityPeriod Years `
                                   -ValidityPeriodUnits 10 `
                                   -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' `
                                   -KeyLength 4096 `
                                   -Force
                                   

certutil -setreg CA\AuditFilter 127
#certutil -setreg CA\ValidityPeriodUnits 4
#certutil -setreg CA\ValidityPeriod "Years"
#endregion Install Enterprise Root CA
 
#region configure CA settings and prepare AIA / CDP
New-Item c:\CDP -ItemType directory -Force
Copy-Item C:\Windows\System32\CertSrv\CertEnroll\*.crt C:\CDP\$CAName.crt -Force
Get-CAAuthorityInformationAccess | Remove-CAAuthorityInformationAccess -Force
Get-CACrlDistributionPoint | Remove-CACrlDistributionPoint -Force
Add-CAAuthorityInformationAccess -Uri http://$CDPURL/$CAName.crt -AddToCertificateAia -Force
Add-CACrlDistributionPoint -Uri C:\CDP\<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl -PublishToServer -PublishDeltaToServer -Force
Add-CACrlDistributionPoint -Uri http://$CDPURL/<CAName><CRLNameSuffix><DeltaCRLAllowed>.crl -AddToCertificateCdp -AddToFreshestCrl -Force
#endregion configure CA settings and prepare AIA / CDP
 
#region create CDP / AIA web site
Import-Module 'C:\Windows\system32\WindowsPowerShell\v1.0\Modules\WebAdministration\WebAdministration.psd1'
New-Website -Name CDP -HostHeader $CDPURL -Port 80 -IPAddress * -Force
Set-ItemProperty 'IIS:\Sites\CDP' -Name physicalpath -Value C:\CDP
Set-WebConfigurationProperty -PSPath 'IIS:\Sites\CDP' -Filter /system.webServer/directoryBrowse  -Name enabled -Value true
Set-WebConfigurationProperty -PSPath 'IIS:\Sites\CDP' -Filter /system.webServer/security/requestfiltering  -Name allowDoubleEscaping -Value true
attrib +h C:\CDP\web.config
#endregion create CDP / AIA web site
 
#region restart CA service and publish CRL
Restart-Service -Name CertSvc
Start-Sleep -Seconds 5
certutil -CRL
#endregion restart CA service and publish CRL
 
#region add webserver template
Invoke-Command -ComputerName $DCvmName -ScriptBlock {
    $DN = (Get-ADDomain).DistinguishedName
    $WebTemplate = "CN=WebServer,CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,$DN"
    DSACLS $WebTemplate /G "Authenticated Users:CA;Enroll"
 
}
 
certutil -setcatemplates +WebServer
#endregion add webserver template
 
#region request web server certificate
$cert = Get-Certificate -Template webserver -DnsName $webenrollURL -SubjectName "CN=$webenrollURL" -CertStoreLocation cert:\LocalMachine\My
#endregion request web server certificate
 
#region Install enrollment web services
Install-AdcsEnrollmentPolicyWebService -AuthenticationType UserName -SSLCertThumbprint $cert.Certificate.Thumbprint -Force
Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST/Default Web Site/ADPolicyProvider_CEP_UsernamePassword'  -filter "appSettings/add[@key='FriendlyName']" -name "value" -value "DSC CA" -Force
Install-AdcsEnrollmentWebService -AuthenticationType UserName -SSLCertThumbprint $cert.Certificate.Thumbprint -Force
#endregion Install enrollment web services
 
#region modify Enrollment Server URL in AD
Invoke-Command -ComputerName $DCvmName -ScriptBlock {
    param
    (
        $CAName,
        $webenrollURL
    )
    $DN = (Get-ADDomain).DistinguishedName
    $CAEnrollmentServiceDN = "CN=$CAName,CN=Enrollment Services,CN=Public Key Services,CN=Services,CN=Configuration,$DN"
    Set-ADObject $CAEnrollmentServiceDN -Replace @{'msPKI-Enrollment-Servers'="1`n4`n0`nhttps://$webenrollURL/$CAName`_CES_UsernamePassword/service.svc/CES`n0"} 
} -ArgumentList $CAName, $webenrollURL
#endregion modify Enrollment Server URL in AD

#region create and publish WebServerShort certificate template

$TemplateJSON = '{
    "name":  "TemporaryTemplate",
    "displayName":  "TemporaryTemplate",
    "objectClass":  "pKICertificateTemplate",
    "flags":  131649,
    "revision":  100,
    "msPKI-Cert-Template-OID":  "1.3.6.1.4.1.311.21.8.11207383.5682649.4736405.11314699.16668964.185.929592.5001862",
    "msPKI-Certificate-Application-Policy":  [
                                                 "1.3.6.1.5.5.7.3.1"
                                             ],
    "msPKI-Certificate-Name-Flag":  1,
    "msPKI-Enrollment-Flag":  0,
    "msPKI-Minimal-Key-Size":  2048,
    "msPKI-Private-Key-Flag":  16842768,
    "msPKI-RA-Signature":  0,
    "msPKI-Template-Minor-Revision":  3,
    "msPKI-Template-Schema-Version":  2,
    "pKICriticalExtensions":  [
                                  "2.5.29.15"
                              ],
    "pKIDefaultCSPs":  [
                           "2,Microsoft DH SChannel Cryptographic Provider",
                           "1,Microsoft RSA SChannel Cryptographic Provider"
                       ],
    "pKIDefaultKeySpec":  1,
    "pKIExpirationPeriod":  [
                                0,
                                64,
                                239,
                                43,
                                18,
                                252,
                                255,
                                255
                            ],
    "pKIExtendedKeyUsage":  [
                                "1.3.6.1.5.5.7.3.1"
                            ],
    "pKIKeyUsage":  [
                        160,
                        0
                    ],
    "pKIMaxIssuingDepth":  0,
    "pKIOverlapPeriod":  [
                             0,
                             128,
                             44,
                             171,
                             109,
                             254,
                             255,
                             255
                         ]
}'


$WebServerShort = New-ADCSTemplate -DisplayName "Web Server Short" -JSON $TemplateJSON -Publish

#endregion create and publish WebServerShort certificate template

#region request Web Server Short certificate
$cert = Get-Certificate -Template webservershort -DnsName $demoCertDNSName -SubjectName "CN=democert" -CertStoreLocation cert:\LocalMachine\My
#endregion request Web Server Short certificate

#region export the PFX certificate to the keyvault

$pfxFilePath = "C:\Temp\Script\democert.pfx"
$certificateName = "democert"
$pfxPassword = ConvertTo-SecureString -String "PFXPasswordDEMO" -Force -AsPlainText

# Export certificate to PFX
Get-ChildItem -Path  "cert:\localMachine\my\$($cert.Certificate.Thumbprint)" | Export-PfxCertificate -FilePath $pfxFilePath -Password $pfxPassword

Connect-AzAccount -Identity

# Import the certificate into Azure KeyVault
$newCert = Import-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -FilePath $pfxFilePath -Password $pfxPassword

#Set the recipient tag
$tag =  @{"recipient" = $Recipient}
$newCert | Update-AzKeyVaultCertificate -Tag $tag

#endregion export the PFX certificate to the keyvault

# configure SMTP server "alias domain" named demo.com in smtp server 
    $incomingEMailDomainName = $recipient.Split("@")[1] # Set SMTP Domain Alias from Recipient specified in Arm deployment
    # $incomingEMailDomainName = "demo.com"
    # Write-Host -Foregroundcolor White " -> Creating incoming SMTP domain..."
       # First create a new smtp domain. The path 'SmtpSvc/1' is the first virtual SMTP server. If you need to modify another virtual SMTP server
       # change the path accordingly.
       try
       {
             $smtpDomains = [wmiclass]'root\MicrosoftIISv2:IIsSmtpDomain'
             $newSMTPDomain = $smtpDomains.CreateInstance()
             $newSMTPDomain.Name = "SmtpSvc/1/Domain/$incomingEMailDomainName"
             $newSMTPDomain.Put()  | Out-Null
             #Write-Host -Foregroundcolor Green " [OK] Successfully created incoming email domain."
       }
       catch
       {
             #Write-Host -Foregroundcolor Red " [Error] Unable to create incoming email domain."
             Exit
       }
       #Write-Host -Foregroundcolor White " -> Configuring incoming SMTP domain..."
       try
       {
             # Configure the new smtp domain as alias domain
             $smtpDomainSettings = [wmiclass]'root\MicrosoftIISv2:IIsSmtpDomainSetting'
             $newSMTPDomainSetting = $smtpDomainSettings.CreateInstance()
             # Set the type of the domain to "Alias"
             $newSMTPDomainSetting.RouteAction = 16
             # Map the settings to the domain we created in the first step
             $newSMTPDomainSetting.Name = "SmtpSvc/1/Domain/$incomingEMailDomainName"
             $newSMTPDomainSetting.Put() | Out-Null
             #Write-Host -Foregroundcolor Green " [OK] Successfully configured incoming email domain."
       }
       catch
       {
             #Write-Host -Foregroundcolor Red " [Error] Unable to configure incoming e-mail domain."
             Exit
       }
#endregion configure SMTP server

