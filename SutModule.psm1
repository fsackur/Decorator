using module .\Decr8r.psm1

function Add-Logging
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, ValueFromPipeline)]
        $foo
    )

    Write-Host "I am logging!" -ForegroundColor Green

    [DecoratedCommand]::Invoke($input, $args)

    Write-Host "I am not logging any more!" -ForegroundColor Green
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

# Initialize-Decorator -Context $ExecutionContext
Initialize-Decorator -SessionState $ExecutionContext.SessionState
# Get-PSCallStack | fl * | Out-String | Write-Host
# Write-Host $ExecutionContext.SessionState.Module
# Write-Host $ExecutionContext.InvokeCommand.PreCommandLookupAction
