
class DecoratedCommand
{
    hidden static [Collections.Generic.ISet[Management.Automation.CommandInfo]]$_decoratedCommands = [Collections.Generic.HashSet[Management.Automation.CommandInfo]]::new()
    hidden static [Management.Automation.CommandInfo]$_decoratedCommand = $null

    [Diagnostics.CodeAnalysis.SuppressMessage("PSAvoidAssignmentToAutomaticVariable", "")]
    static [Collections.ObjectModel.Collection[psobject]] Invoke([object[]] $_args)
    {
        # $Decorator = (Get-PSCallStack)[1].InvocationInfo.MyCommand
        # $Decorated = $Decorator.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})
        # & $Decorated.Decorated
        $DecoratedCommand = [DecoratedCommand]::_decoratedCommand
        [DecoratedCommand]::_decoratedCommand = $null
        return & $DecoratedCommand @_args
    }
}

class DecorateWithAttribute : Attribute
{
    DecorateWithAttribute ([string]$DecoratorName)
    {
        Write-Host "In DecorateWithAttribute" -ForegroundColor DarkGray
        # Get-PSCallStack | ft | os | write-host -ForegroundColor DarkGray
        # $this.Decorator = Get-Command $DecoratorName
        # $this.Decorator | ft | os | write-host -ForegroundColor DarkGray
        # [DecoratedCommand]::_decoratedCommand = $this.Decorator
        $this.$DecoratorName = $DecoratorName
    }

    [Management.Automation.CommandInfo]$Decorator
    [string]$DecoratorName
}


function Initialize-Decorator
{
    param
    (
        [Parameter(Mandatory)]
        [Management.Automation.SessionState]$SessionState
        # [Management.Automation.EngineIntrinsics]$Context
    )
    # Write-Host $ExecutionContext.SessionState.Module  # Decr8r
    # Get-PSCallStack | fl * | Out-String | Write-Host
    # (Get-PSCallStack)[1].InvocationInfo.MyCommand | fl * | Out-String | Write-Host
    # $SessionState | fl * | Out-String | Write-Host

    # $SessionState.InvokeCommand.PreCommandLookupAction = {
    #     param ($CommandName, $LookupEventArgs)

    #     if ($CommandName -eq "foo")
    #     {
    #         Write-Host "Intercepted $CommandName" -ForegroundColor Green
    #     }
    # }
    # $SessionState.InvokeCommand.GetCommands('*', 'All', $true) | select -First 10 | ft | os | write-host
    # Get-Command -Module
    # $SessionState.Module | select -First 10 | ft | os | write-host
    # $SessionState.InvokeCommand.PostCommandLookupAction = {
    #     param ($CommandName, $LookupEventArgs)

    #     $Command = $LookupEventArgs.Command
    #     # if ([DecoratedCommand]::_decoratedCommands.Contains($Command))
    #     $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})
    #     if ($Attr)
    #     {
    #         Write-Host "In PostCommandLookupAction" -ForegroundColor DarkGray
    #         [DecoratedCommand]::_decoratedCommand = $Command
    #         # $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})[0]
    #         $LookupEventArgs.Command = $Attr.Decorator
    #     }
    # }
    Write-Host "In Initialize-Decorator" -ForegroundColor DarkGray
    Get-Command -Module $SessionState.Module | ft | os | write-host     # if we call from the .psm1, the functions haven't been exported yet and this returns $null

    # So, use reflection to get the internal table
    $iss = [Management.Automation.SessionState].GetField('_sessionState', ([Reflection.BindingFlags]'Nonpublic, Instance')).GetValue($SessionState)
    $FunctionTable = $iss.GetType().GetMethod('GetFunctionTable', ([Reflection.BindingFlags]'Nonpublic, Instance')).Invoke($iss, @())

    $ModuleFunctions = $FunctionTable.Values.Where({$_.Module -eq $SessionState.Module})
    $DecoratedFunctions = $ModuleFunctions.Where({$_.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})})

    $DecoratedFunctions | ft | os | write-host
    $DecoratedFunctions | Update-Function
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
        [Management.Automation.FunctionInfo]$DecoratedFunction
    )

    begin
    {
        $UpdateMethod = [Management.Automation.FunctionInfo].GetMethod(
            'Update',
            ([Reflection.BindingFlags]'Nonpublic, Instance'),
            [type[]]([scriptblock], [bool], [Management.Automation.ScopedItemOptions], [string])
        )
    }

    process
    {
        $DecoratorAttribute = $DecoratedFunction.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})
        $Decorator = $DecoratorAttribute.Decorator
        $Wrapper = {
            [DecoratedCommand]::_decoratedCommand = $DecoratedFunction
            & $Decorator @args
        }.GetNewClosure()
        $UpdateMethod.Invoke(
            $DecoratedFunction,
            (
                $Wrapper,
                $Force,
                $DecoratedFunction.Options,
                ([string]$DecoratedFunction.HelpFile)
            )
        )
    }
}
