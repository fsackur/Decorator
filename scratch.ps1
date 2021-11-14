using namespace System.Management.Automation

# https://huddledmasses.org/2020/03/empowering-your-pwsh-with-attributes/
# https://powershell.one/powershell-internals/attributes/custom-attributes


class DecoratedCmdletBindingAttribute : CmdletBindingAttribute
{
    [scriptblock]$InjectParams
}


function SUT
{
    [DecoratedCmdletBinding(InjectParams = {
        param
        (
            [Parameter(Position = 0)]
            $bar
        )
    })]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )
}





function Add-DecoratedParameters
{
    [OutputType([FunctionInfo])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('InputObject')]
        [FunctionInfo]$Command
    )

    process
    {
        $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecoratedCmdletBindingAttribute]})
        if (-not $Attr)
        {
            Write-Debug "Command '$Command' is not decorated with DecoratedCmdletBinding."
            return $Command
        }

        if (-not $Attr.InjectParams)
        {
            Write-Debug "Command '$Command' has no injection parameters specified in DecoratedCmdletBinding."
            return $Command
        }

        Write-Debug "Command '$Command' is decorated with DecoratedCmdletBinding."

        $InjectBlock = $Attr.InjectParams
        $NewParams = $InjectBlock.Ast.ParamBlock.Parameters

        if (-not $NewParams)
        {
            Write-Debug "Command '$Command' has no injection parameters specified in DecoratedCmdletBinding."
            return $Command
        }

        $SubjectParams = $Command.ScriptBlock.Ast.Body.ParamBlock.Parameters

        Write-Debug "Starting parameters:"
        $SubjectParams | Out-String | Write-Debug

        Write-Debug "Injecting parameters:"
        $NewParams | Out-String | Write-Debug

        return $Command
    }
}