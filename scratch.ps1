using namespace System.Management.Automation

# https://huddledmasses.org/2020/03/empowering-your-pwsh-with-attributes/
# https://powershell.one/powershell-internals/attributes/custom-attributes

class DecoratorException : Exception
{
    DecoratorException([string]$Message) : base($Message) {}
    DecoratorException([string]$Message, [Exception]$InnerException) : base($Message, $InnerException) {}
}

class DecorateAttribute : Attribute
{
    DecorateAttribute ([scriptblock]$Decorator)
    {
        # Could potentially validate the decorator here
        # Pipe the decorated command in, presumably
        # Then, this scriptblock replaces the decorated command somehow..?
        $this.Decorator = $Decorator
    }

    [scriptblock]$Decorator
}


function Dec
{
    param
    (
        [CommandInfo]$DecoratedCommand,

        $ExtraParam
    )

    & $DecoratedCommand
}


function SUT
{
    [Decorate({Dec -ExtraParam 42})]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )
}



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


gcm SUT | Get-Decorator -Debug
