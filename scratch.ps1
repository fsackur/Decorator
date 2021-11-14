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
    # no parameterisation
    DecorateAttribute ([string]$DecoratorName)
    {
        try
        {
            # hard to predict what will happen at runtime; no syntax help
            $Dec = Get-Command $DecoratorName -ErrorAction Stop
        }
        catch [CommandNotFoundException]
        {
            # This is silently swallowed at parse time
            throw [DecoratorException]::new("Could not find decorator command '$DecoratorName'.", $_.Exception)
        }
        if ($Dec.Count -gt 1)
        {
            throw [DecoratorException]::new("Multiple commands found matching decorator name '$DecoratorName'.")
        }

        $this.Decorator = $Dec
    }

    [CommandInfo]$Decorator
}


function Dec
{}


function SUT
{
    [Decorate('Dec')]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )
}



function Get-Decorator
{
    [OutputType([CommandInfo])]
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
