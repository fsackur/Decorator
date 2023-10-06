function Resolve-Parameter
{
    param
    (
        [switch]$Resolve,

        [string[]]$DesiredParameter
    )

    [bool]$Resolve = $true

    function Decorate-Command
    {
        param
        (
            $Command,
            $Msg
        )
    }

    $sb = {Decorate-Command -Comm $c -Msg 44}
    $CommandAst = $sb.Ast.EndBlock.Statements[-1].PipelineElements[-1]
    $BindingResult = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand($CommandAst, $Resolve, $DesiredParameter)

    $BindingResult
}

Resolve-Parameter
