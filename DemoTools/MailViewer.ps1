Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Define the ConvertFrom-EmlToHtml function
function ConvertFrom-EmlToHtml {
    [CmdletBinding()]

    Param
    (
        [Parameter(ParameterSetName="Path", Position=0, Mandatory=$True)]
        [String]$Path,

        [Parameter(ParameterSetName="LiteralPath", Mandatory=$True)]
        [String]$LiteralPath,

        [Parameter(ParameterSetName="FileInfo", Mandatory=$True, ValueFromPipeline=$True)]
        [System.IO.FileInfo]$Item
    )

    Process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            "Path"        { $files = Get-ChildItem -Path $Path }
            "LiteralPath" { $files = Get-ChildItem -LiteralPath $LiteralPath }
            "FileInfo"    { $files = $Item }
        }

        $files | % {
            # Work out file names
            $emlFn  = $_.FullName

            # Skip non-.msg files
            if ($emlFn -notlike "*.eml") {
                Write-Verbose "Skipping $_ (not an .eml file)..."
                return
            }

            # Read EML
            Write-Verbose "Reading $_..."
            $adoDbStream = New-Object -ComObject ADODB.Stream
            $adoDbStream.Open()
            $adoDbStream.LoadFromFile($emlFn)
            $cdoMessage = New-Object -ComObject CDO.Message
            $cdoMessage.DataSource.OpenObject($adoDbStream, "_Stream")

            # Generate HTML
            Write-Verbose "Generating HTML..."
            $html = "<!DOCTYPE html>`r`n"
            $html += "<html>`r`n"
            $html += "<head>`r`n"
            $html += "<meta charset=`"utf-8`">`r`n"
            $html += "<title>" + $cdoMessage.Subject + "</title>`r`n"
            $html += "</head>`r`n"
            $html += "<body style=`"font-family: sans-serif; font-size: 11pt`">`r`n"
            $html += "<div style=`"margin-bottom: 1em;`">`r`n"
            $html += "<strong>From: </strong>" + $cdoMessage.From + "<br>`r`n"
            $html += "<strong>Sent: </strong>" + $($cdoMessage.SentOn).ToString("dd/MM/yyyy HH:mm:ss") + "<br>`r`n"
            $html += "<strong>To: </strong>" + $cdoMessage.To + "<br>`r`n"
            if ($cdoMessage.CC -ne "") {
                $html += "<strong>Cc: </strong>" + $cdoMessage.CC + "<br>`r`n"
            }
            if ($cdoMessage.BCC -ne "") {
                $html += "<strong>Bcc: </strong>" + $cdoMessage.BCC + "<br>`r`n"
            }
            $html += "<strong>Subject: </strong>" + $cdoMessage.Subject + "<br>`r`n"
            $html += "</div>`r`n"
            if ($cdoMessage.HTMLBody -ne "") {
                $html += "<div>`r`n"
                $html += $cdoMessage.HTMLBody + "`r`n"
                $html += "</div>`r`n"
            } else {
                $html += "<div><pre>"
                $html += $cdoMessage.TextBody
                $html += "</pre></div>`r`n"
            }
            $html += "</body>`r`n"
            $html += "</html>`r`n"

            return $html
        }
    }

    End
    {
        Write-Verbose "Done."
    }
}

# Create form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Mail Viewer"
$form.Size = New-Object System.Drawing.Size(800, 400)
$form.FormBorderStyle = "FixedDialog"
$form.StartPosition = "CenterScreen"

# Create web browser control
$webBrowser = New-Object System.Windows.Forms.WebBrowser
$webBrowser.Location = New-Object System.Drawing.Point(10, 50)
$webBrowser.Size = New-Object System.Drawing.Size(760, 300)
$form.Controls.Add($webBrowser)

# Create button for file selection
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point(10, 10)
$button.Size = New-Object System.Drawing.Size(100, 30)
$button.Text = "Open EML"
$button.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "EML files (*.eml)|*.eml"
    $openFileDialog.Title = "Select an EML File"
    $openFileDialog.InitialDirectory = "C:\inetpub\mailroot\drop"

    $dialogResult = $openFileDialog.ShowDialog()
    if ($dialogResult -eq "OK") {
        $emlFilePath = $openFileDialog.FileName

        # Convert EML to HTML
        $html = ConvertFrom-EmlToHtml -Path $emlFilePath

        # Display HTML in the web browser
        $webbrowser.DocumentText = $html
    }
})
$form.Controls.Add($button)

# Show form
$form.ShowDialog() | Out-Null
