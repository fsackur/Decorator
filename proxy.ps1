[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [System.Object]
    ${InputObject},

    [Parameter(ParameterSetName='Default')]
    [switch]
    ${Singleline},

    [Parameter(ParameterSetName='Default')]
    [switch]
    ${DoubleQuote},

    [Parameter(ParameterSetName='Explicit')]
    [ValidatePattern('(?s)^([''"]).*\1$')]
    [string]
    ${Join})

begin
{
    try {
        $outBuffer = $null
        if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
        {
            $PSBoundParameters['OutBuffer'] = 1
        }

        $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('ConvertTo-ListExpression', [System.Management.Automation.CommandTypes]::Function)
        $scriptCmd = {& $wrappedCmd @PSBoundParameters }

        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($PSCmdlet)
    } catch {
        throw
    }
}

process
{
    try {
        $steppablePipeline.Process($_)
    } catch {
        throw
    }
}

end
{
    try {
        $steppablePipeline.End()
    } catch {
        throw
    }
}

clean
{
    if ($null -ne $steppablePipeline) {
        $steppablePipeline.Clean()
    }
}
<#

.ForwardHelpTargetName ConvertTo-ListExpression
.ForwardHelpCategory Function

#>

