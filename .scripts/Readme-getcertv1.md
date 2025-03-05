# Azure Key Vault Certificate Retrieval Script (getcertv1.sh)

## Purpose

This Bash script automates the process of retrieving and managing certificates from Azure Key Vault using Managed Identity authentication. It is designed to:

- Securely authenticate with Azure using Managed Identity
- Download a certificate from Azure Key Vault
- Extract certificate and private key from a PFX file
- Install the certificate and key to specified system locations
- Prevent unnecessary updates by comparing certificate thumbprints

## Prerequisites

- Bash shell
- Python3
- OpenSSL
- jq (JSON processor)
- Azure Managed Identity (either Azure ARC or Azure VM)
- Access to an Azure Key Vault

## Dependencies

Install required dependencies:

`sudo dnf install jq openssl python3`

## Configuration (variables.txt)

The script uses a configuration file (default: /clc/variables.txt) with the following key settings:

### Work Paths

- `CERT_PATH`: Temporary directory for certificate storage
- `KEY_PATH`: Temporary directory for key storage
- `TEMP_PATH`: Temporary file storage location

### Key Vault Settings

- `KEYVAULT_NAME`: Name of the Azure Key Vault
- `CERT_NAME`: Unique identifier for the certificate
- `CERT_SECRET_NAME`: Name of the secret in Key Vault (usually same as `CERT_NAME`)

### Output Locations

- `CERT_OUTPUT_DIR`: Final location for the public certificate
- `KEY_OUTPUT_DIR`: Final location for the private key

### Optional Settings

- `PFX_PASSWORD`: Password for the PFX file (leave blank if no password)
- `CERT_PERMISSIONS`: File permissions for the certificate (default: 0644)
- `KEY_PERMISSIONS`: File permissions for the private key (default: 0600)

## Usage

Run the script with an optional path to the variables file:

`./getcertv1.sh -varpath /path/to/variables.txt`

If no path is specified, it defaults to /clc/variables.txt.

## Authentication Methods

The script supports two Managed Identity authentication methods:

1. Azure ARC (for on-premises VM)
2. Azure VM Managed Identity (for Azure native VM on IaaS)

## Key Features

- Automatic token retrieval using Managed Identity
- Thumbprint-based certificate update check
- Secure file permissions
- Flexible configuration through variables file
- Error handling and logging

## Security Considerations

- Ensure the variables file has restricted permissions
- Use Managed Identity for secure, password-less authentication
- Temporary files are cleaned up after processing

## Troubleshooting

- Verify Azure Managed Identity is correctly configured
- Check network connectivity to Azure services
- Ensure required dependencies are installed
- Validate Key Vault and secret names

## Sample variables.txt

For a quick start, use the provided sample configuration, adjusting values as needed for your environment.