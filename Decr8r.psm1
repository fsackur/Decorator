# https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_commonparameters
[string[]]$CommonParameters = (
    'Verbose',
    'Debug',
    'ErrorAction',
    'WarningAction',
    'InformationAction',
    'ErrorVariable',
    'WarningVariable',
    'InformationVariable',
    'OutVariable',
    'OutBuffer',
    'PipelineVariable',
    'WhatIf',
    'Confirm'
)
[Collections.Generic.HashSet[string]]$CommonParameters = [Collections.Generic.HashSet[string]]::new($CommonParameters)

class DecoratedCommand
{
    hidden static [Collections.Generic.ISet[Management.Automation.CommandInfo]]$_decoratedCommands = [Collections.Generic.HashSet[Management.Automation.CommandInfo]]::new()
    hidden static [Management.Automation.CommandInfo]$_decoratedCommand = $null
    # hidden static [scriptblock]$_decoratedCommand = $null

    static [Collections.ObjectModel.Collection[psobject]] Invoke([object[]]$_input, [Collections.IDictionary]$_PSBoundParameters, [object[]]$_args)
    {
        # $Decorator = (Get-PSCallStack)[1].InvocationInfo.MyCommand
        # $Decorated = $Decorator.ScriptBlock.Attributes.Where({$_.TypeId -eq [DecorateWithAttribute]})
        # & $Decorated.Decorated
        $DecoratedCommand = [DecoratedCommand]::_decoratedCommand
        [DecoratedCommand]::_decoratedCommand = $null
        return $_input | & $DecoratedCommand @_PSBoundParameters @_args
    }

    static [Management.Automation.RuntimeDefinedParameterDictionary] GetParameters()
    {
        return [DecoratedCommand]::GetParameters([DecoratedCommand]::_decoratedCommand)
    }

    hidden static [Management.Automation.RuntimeDefinedParameterDictionary] GetParameters([Management.Automation.CommandInfo]$DecoratedCommand)
    {
        $DynParams = [Management.Automation.RuntimeDefinedParameterDictionary]::new()

        if ($null -eq $DecoratedCommand)
        {
            return $DynParams
        }

        $OriginalParams = $DecoratedCommand.Parameters.Values | Where-Object {-not $CommonParameters.Contains($_.Name)}
        $OriginalParams | ForEach-Object {
            $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
                $_.Name,
                $_.ParameterType,
                $_.Attributes
            )
            $DynParams.Add($_.Name, $DynParam)
        }

        return $DynParams
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
        $this.DecoratorName = $DecoratorName
    }

    [Management.Automation.CommandInfo]$Decorator
    [string]$DecoratorName
}


$PrivateFlags = [Reflection.BindingFlags]'Nonpublic, Instance'

# Private method to update function scriptblock - this is used internally to save regenerating everything
$UpdateMethod = [Management.Automation.FunctionInfo].GetMethod(
    'Update',
    $PrivateFlags,
    [type[]]([scriptblock], [bool], [Management.Automation.ScopedItemOptions], [string])
)

# $InternalSessionStateField = [Management.Automation.SessionState].GetField(
#     '_sessionState',
#     ([Reflection.BindingFlags]'Nonpublic, Instance')
# )

$InternalSessionStateProperty = [Management.Automation.SessionState].GetProperty('Internal', $PrivateFlags)

$GetFunctionTableMethod = $InternalSessionStateProperty.PropertyType.GetMethod('GetFunctionTable', $PrivateFlags)

$SBDataField = [scriptblock].GetField('_scriptBlockData', $PrivateFlags)
$CompiledSBType = $SBDataField.FieldType
$CompiledSBCmdletBindingField = $CompiledSBType.GetField('_usesCmdletBinding', $PrivateFlags)

function Initialize-Decorator
{
    param
    (
        [Parameter(Mandatory)]
        [Management.Automation.SessionState]$SessionState
    )

    Write-Host "In Initialize-Decorator" -ForegroundColor DarkGray

    # if we call from the .psm1, the functions haven't been exported yet and this returns $null
    # So, use reflection to get the internal table
    $InternalSessionState = $InternalSessionStateProperty.GetValue($SessionState)
    $FunctionTable = $GetFunctionTableMethod.Invoke($InternalSessionState, @())

    $ModuleFunctions = $FunctionTable.Values.Where({$_.Module -eq $SessionState.Module})

    # Attributes are lazy-instantiated, so not in .ScriptBlock.Attributes yet. We have to go to the AST.
    $DecoratedFunctions = $ModuleFunctions.Where({
        $_.ScriptBlock.Ast.Body.ParamBlock.Attributes.TypeName.FullName -eq [DecorateWithAttribute].FullName
    })


    $DecoratedFunctions | % {
        $Decorated = $OriginalCommand = $_
        Write-Host "Updating function: $Decorated" -ForegroundColor DarkGray

        $DecoratorAttribute = $Decorated.ScriptBlock.Ast.Body.ParamBlock.Attributes.Where({
            $_.TypeName.FullName -eq [DecorateWithAttribute].FullName
        })
        $DecoratorName = $DecoratorAttribute.PositionalArguments.Value
        $Decorator = $FunctionTable[$DecoratorName]

        $DynParams = [DecoratedCommand]::GetParameters($Decorator)
        # [DecoratedCommand]::GetParameters($Decorator).GetEnumerator() | ForEach-Object {
        #     $DynParams[$_.Key] = $_.Value
        # }


        # Clone the decorated command. The clone has the original code, and is called
        # "original" - the original will be modified in place and left in the FunctionTable.
        $Ctor = $Decorated.GetType().GetConstructor($PrivateFlags, $Decorated.GetType())
        $OriginalCommand = $Ctor.Invoke($Decorated)


        $Wrapper = & {
            # Create new scope and bring in vars from parent scope - this reduces the size of the closure
            $OriginalCommand = $OriginalCommand
            $DynParams = $DynParams
            $Decorator = $Decorator

            return {
                # [CmdletBinding()]
                param ()

                dynamicparam
                {
                    $DynParams
                }

                begin
                {
                    [DecoratedCommand]::_decoratedCommand = $OriginalCommand
                    $Pipeline = {& $Decorator @PSBoundParameters}.GetSteppablePipeline()
                    $Pipeline.Begin($PSCmdlet)
                }

                process
                {
                    $Pipeline.Process($_)
                }

                end
                {
                    $Pipeline.End()
                }

                clean
                {
                    if ($null -ne $Pipeline) {$Pipeline.Clean()}
                }
            }.GetNewClosure()
        }

        # if (-not ($Decorated.CmdletBinding -or $Decorator.CmdletBinding))
        # {
        #     $CompiledWrapper = $SBDataField.GetValue($Wrapper)
        #     $CompiledSBCmdletBindingField.SetValue($CompiledWrapper, $false)
        # }

        # $Ctor = $Decorated.GetType().GetConstructor($PrivateFlags, $Decorated.GetType())
        # $OriginalCommand = $Ctor.Invoke($Decorated)
        # internal FunctionInfo(string name, ScriptBlock function, ScopedItemOptions options, ExecutionContext context, string helpFile)

        $UpdateMethod.Invoke(
            $Decorated,
            (
                $Wrapper,
                $Force,
                $Decorated.Options,
                ([string]$Decorated.HelpFile)
            )
        )
    }
}
