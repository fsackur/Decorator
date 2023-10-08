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
    # [DecorateWith("Add-Logging")]
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

function Has-DynamicParams
{
    [DecorateWith("Add-Logging")]
    [CmdletBinding()]
    param
    (
        $StaticParam
    )

    dynamicparam
    {
        $DynParams = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
            "foo",
            [object],
            [Management.Automation.ParameterAttribute]::new()
        )
        $DynParams.Add($DynParam.Name, $DynParam)
        $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
            "bar",
            [object],
            [Management.Automation.ParameterAttribute]::new()
        )
        $DynParams.Add($DynParam.Name, $DynParam)
        $DynParams

        Get-Variable -Scope Local | ft | os | write-host
    }

    end {$PSBoundParameters.foo}
}


# Initialize-Decorator -SessionState $ExecutionContext.SessionState
