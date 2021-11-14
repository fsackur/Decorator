$TestDataPath   = $PSScriptRoot | Join-Path -ChildPath TestData
$TestModuleBase = $TestDataPath | Join-Path -ChildPath TestModule
$TestModule     = $TestModuleBase | Import-Module -PassThru -ErrorAction Stop

@{
    Name      = 'Module function'
    CmdToWrap = & $TestModule {Get-Command CmdToWrap}
}