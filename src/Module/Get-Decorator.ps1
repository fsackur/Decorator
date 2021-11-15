function Get-Decorator
{
    [OutputType([scriptblock])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('InputObject')]
        [FunctionInfo]$Command
    )

    process
    {
        $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateAttribute]})
        if (-not $Attr)
        {
            Write-Debug "Command '$Command' is not decorated."
            return
        }

        Write-Debug "Command '$Command' is decorated."

        $Decorator = $Attr.Decorator

        return $Decorator
    }
}
