BeforeAll {
    $PSScriptRoot |
        Join-Path -ChildPath assets |
        Get-ChildItem -Filter *.ps1 -File |
        ForEach-Object {. $_.FullName}
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
