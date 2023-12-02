$DecoratorDeclaration = {
    function Add-Logging
    {
        [CmdletBinding()]
        param
        (
            [Parameter(Position = 0)]
            [Decr8r.DecoratedCommand]$Decorated,

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
}

$SimpleFunctionDeclaration = {
    function SUT
    {
        [Decr8r.DecorateWith("Add-Logging")]
        [CmdletBinding()]
        param
        (
            [Parameter(Position = 0)]
            $foo
        )

        Write-Host "Decorated end"
        Write-Host $foo
    }
}

$PipelineFunctionDeclaration = {
    function SUT
    {
        [Decr8r.DecorateWith("Add-Logging")]
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
}
