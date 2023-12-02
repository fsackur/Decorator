BeforeAll {
    $AssetsFolder = Join-Path $PSScriptRoot assets
    $AssetsFolder |
        Get-ChildItem -Filter *.ps1 -File |
        ForEach-Object {. $_.FullName}
    $BuildFolder = $PSScriptRoot |
        Split-Path |
        Join-Path -ChildPath Build |
        Join-Path -ChildPath Decr8r

    Get-Module Decr8r |
        Remove-Module
    Get-Module $BuildFolder -ListAvailable |
        Sort-Object Version |
        Select-Object -Last 1 |
        Import-Module -Force
}

Describe 'Decr8r' {
    BeforeEach {
        $HostWrites = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host {$HostWrites.Add([string]$Object)}
    }

    It 'Decorates a simple function' {
        . $DecoratorDeclaration
        . $SimpleFunctionDeclaration
        & SUT

        $HostWrites | Should -Be (
            "Decorator begin",
            "Decorator process",
            "Decorated end",
            "Decorator end"
        )
    }
}
