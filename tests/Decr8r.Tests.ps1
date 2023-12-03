BeforeAll {
    $PSScriptRoot |
        Join-Path -ChildPath assets |
        Get-ChildItem -Filter *.ps1 -File |
        ForEach-Object {. $_.FullName}
}

Describe 'Decr8r' {
    BeforeEach {. $WriteHostSetup}

    It 'Decorates a simple function' {
        . $DecoratorDeclaration
        . $SimpleFunctionDeclaration

        & SUT

        ShouldWrite (
            "Decorator begin",
            "Decorator process",
            "Decorated end",
            "Decorator end"
        )
    }
}
