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
        Write-Host "Decorator begin"
        Write-Host $bar
        [void]$PSBoundParameters.Remove('bar')  # TODO - remove
        $Decorated.Begin()
    }

    process
    {
        Write-Host "Decorator process"
        $Decorated.Process($_)
    }

    end
    {
        $Decorated.End()
        Write-Host "Decorator end"
    }
}

function SUT
{
    [DecorateWith("Add-Logging")]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )

    # Write-Host $PSCmdlet.SessionState.GetHashCode()
    Write-Host "Decorated end"
    Write-Host $foo
}

function SUT2
{
    [DecorateWith("Add-Logging")]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0, ValueFromPipeline)]
        $foo
    )

    begin
    {
        Write-Host "Decorated begin"
    }

    process
    {
        Write-Host "Decorated process"
        Write-Host $foo
    }

    end
    {
        Write-Host "Decorated end"
    }
}


# $ExecutionContext.SessionState.GetHashCode()
# $PrivateFlags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance
