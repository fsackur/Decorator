using module .\Decr8r.psm1

function Add-Logging
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        [DecoratedCommand]$Decorated,

        [string]$bar
    )

    dynamicparam
    {
        $Decorated.Parameters
    }

    begin
    {
        Write-Host "I am logging: $bar" -ForegroundColor Green
        [void]$PSBoundParameters.Remove('bar')
        $Decorated.Begin()
    }

    process
    {
        $Decorated.Process($_)
    }

    end
    {
        $Decorated.End()
        Write-Host "I am not logging any more!" -ForegroundColor Green
    }
}

function SUT
{
    [DecorateWithAttribute("Add-Logging")]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, ValueFromPipeline)]
        $foo
    )

    process
    {
        Write-Host "I am doing a thing: $foo"
    }
}


Initialize-Decorator -SessionState $ExecutionContext.SessionState
