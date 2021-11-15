function Update-Function
{
    [OutputType([void])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('InputObject')]
        [FunctionInfo]$Command
    )

    begin
    {
        $UpdateMethod = [FunctionInfo].GetMethod(
            'Update',
            ([Reflection.BindingFlags]'Nonpublic, Instance'),
            [type[]]([scriptblock], [bool], [ScopedItemOptions], [string])
        )
    }

    process
    {
        $Force = $true

        $Decorator = $Command | Get-Decorator

        $Decorator = & {
            $Decorated = $Command
            $Decorator.GetNewClosure()
        }

        $UpdateMethod.Invoke(
            $Command,
            (
                $Decorator,
                $Force,
                $Command.Options,
                ([string]$Command.HelpFile)
            )
        )
    }
}
