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
    [CmdletBinding()]
    param
    (
        [CommandInfo]$DecoratedCommand,
        $ExtraParam
    )

    & $DecoratedCommand
}


function SUT
{
    [Decorate({
        Dec -ExtraParam 42
    })]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )

    if ($ExtraParam)
    {
        return $foo, $ExtraParam -join ':'
    }
    return $foo
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
            $Command = $Command
            $PSDefaultParameterValues = $PSDefaultParameterValues.Clone()
            # Will need to parse AST to get the decorator and param names
            $PSDefaultParameterValues['Dec:DecoratedCommand'] = $Command
            $Decorator.GetNewClosure()
        }

        # Doesn't work. This Update method is an in-place update - so, infinite recursion
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


$SUT = gcm SUT
$Dec = $SUT | Get-Decorator -Debug

SUT 12

Update-Function $SUT

SUT 12
