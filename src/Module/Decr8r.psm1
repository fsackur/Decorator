
(
    'DecoratorException.ps1',
    'DecorateAttribute.ps1',
    'Get-Decorator.ps1',
    'Update-Function.ps1'
) |
    ForEach-Object {. (Join-Path $PSScriptRoot $_)}
