
function Add-Logging
{
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        [Management.Automation.CommandInfo]$Decorated
    )

    dynamicparam
    {
        $DynParams
    }

    begin
    {
        Write-Host "I am logging: $bar" -ForegroundColor Green
        [void]$PSBoundParameters.Remove('Decorated')
        $scriptCmd = {& $Decorated @PSBoundParameters}
        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($PSCmdlet)
    }

    process
    {
        $steppablePipeline.Process($_)
    }

    end
    {
        $steppablePipeline.End()
        Write-Host "I am not logging any more!" -ForegroundColor Green
    }
}

function SUT
{
    # [DecorateWithAttribute("Add-Logging")]
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

$Decorator = gcm Add-Logging
$Decorated = gcm SUT
$DynParams = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
$OriginalParams = $Decorated.Parameters.Values | Where-Object {-not $CommonParameters.Contains($_.Name)}
$OriginalParams | ForEach-Object {
    $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
        $_.Name,
        $_.ParameterType,
        $_.Attributes
    )
    $DynParams.Add($_.Name, $DynParam)
}


# $Wrapper = {
function Wrapper {
    [CmdletBinding()]
    param ()

    dynamicparam
    {
        $DynParams
    }

    begin
    {
        $Pipeline = {& $Decorator -Decorated $Decorated @PSBoundParameters}.GetSteppablePipeline()
        $Pipeline.Begin($PSCmdlet)
    }

    process
    {
        $Pipeline.Process($_)
    }

    end
    {
        $Pipeline.End()
    }

    clean
    {
        if ($null -ne $Pipeline) {$Pipeline.Clean()}
    }
}
