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
        $this.Decorator = $Decorator
    }

    [scriptblock]$Decorator
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
        [Alias('Command')]
        [FunctionInfo]$SUT
    )

    begin
    {
        $UpdateMethod = [FunctionInfo].GetMethod(
            'Update',
            ([Reflection.BindingFlags]'Nonpublic, Instance'),
            [type[]]([scriptblock], [bool], [ScopedItemOptions], [string])
        )

        # Following references in the source code shows that this is called by the FunctionProvider. So:
        # function foo {23}; $f1 = gcm foo; $Field.SetValue($f1, {42}); $f2 = gcm foo; $f1 -eq $f2
        # True
        # but also:
        # function foo {23}; $f1 = gcm foo; Set-Item Function:\foo {42}; $f2 = gcm foo; $f1 -eq $f2
        # True
    }

    process
    {
        $Force = $true

        $Decorator = $SUT | Get-Decorator

        $UpdateMethod
        # $UpdateMethod.Invoke(
        #     $Command,
        #     (
        #         $Decorator,
        #         $Force,
        #         $Command.Options,
        #         ([string]$Command.HelpFile)
        #     )
        # )
    }
}


function Has-DynamicParams
{
    [DecorateWithAttribute("Add-Logging")]
    [CmdletBinding()]
    param ()

    dynamicparam
    {
        $DynParams = [Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
            "foo",
            [object],
            [Management.Automation.ParameterAttribute]::new()
        )
        $DynParams.Add($DynParam.Name, $DynParam)
        $DynParams
    }

    end {$PSBoundParameters.foo}
}


Join-Path $PSScriptRoot DecModule.psm1 | ipmo -Force
Join-Path $PSScriptRoot SutModule.psm1 | ipmo -Force

$SUT = gcm SUT
$Decorator = $SUT | Get-Decorator
Update-Function $SUT
