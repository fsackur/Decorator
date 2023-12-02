$Dependencies = (
    @{
        Name = 'Pester'
        MinimumVersion = '5.5.0'
    },
    @{
        Name = 'PowerShellGet'
        MinimumVersion = '3.0.23'
    },
    @{
        Name = 'InvokeBuild'
        MinimumVersion = '5.10.4'
    }
)

Get-PSRepository | Out-String | Write-Host

$Dependencies |
    ForEach-Object {
        if (-not (Get-Module $_.Name -ListAvailable -ErrorAction Ignore | Where-Object Version -ge $_.MinimumVersion))
        {
            $Params = @{
                Force              = $true
                AllowClobber       = $true
                Repository         = 'PSGallery'
                SkipPublisherCheck = $true
                AllowPrerelease    = $_.Name -eq 'PowerShellGet'
            }
            Write-Verbose "Installing $($_.Name)..."
            Install-Module @Params @_ -PassThru
        }
    } |
    Out-String |
    Write-Host
