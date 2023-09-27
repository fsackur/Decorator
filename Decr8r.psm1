
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
    DecorateWithAttribute ([Management.Automation.CommandInfo]$Decorator)
    {
        $this.Decorator = $Decorator
        [void][DecoratedCommand]::_decoratedCommands.Add($this.Decorator)
    }

    DecorateWithAttribute ([string]$DecoratorName)
    {
        $this.Decorator = Get-Command $DecoratorName
        [void][DecoratedCommand]::_decoratedCommands.Add($this.Decorator)
    }

    [Management.Automation.CommandInfo]$Decorator
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
    $SessionState.InvokeCommand.PostCommandLookupAction = {
        param ($CommandName, $LookupEventArgs)

        $Command = $LookupEventArgs.Command
        # if ([DecoratedCommand]::_decoratedCommands.Contains($Command))
        $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})
        if ($Attr)
        {
            Write-Host "In PostCommandLookupAction" -ForegroundColor DarkGray
            [DecoratedCommand]::_decoratedCommand = $Command
            # $Attr = $Command.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})[0]
            $LookupEventArgs.Command = $Attr.Decorator
        }
    }
}
