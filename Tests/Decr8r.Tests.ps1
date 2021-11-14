BeforeDiscovery {
    $ModuleBase = $PSScriptRoot | Split-Path | Join-Path -ChildPath 'src' | Join-Path -ChildPath 'Module'
    $ModulePath = $ModuleBase | Join-Path -ChildPath 'Decr8r.psd1'
    Import-Module $ModulePath -ErrorAction Stop

    $TestCasePath = $PSScriptRoot | Join-Path -ChildPath 'Decr8r.Setup.ps1'
    $TestCases = & $TestCasePath
}


Describe "Decorating" {

    Context "<_.Name>" -Foreach $TestCases {

        BeforeEach {

            $Result = & $CmdToWrap -InjectedParam 42
        }

        It "Picks up InjectedParam" {

            $Result | Should -Be 42
        }
    }
}