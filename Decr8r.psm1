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
    hidden [Management.Automation.CommandInfo] $_decorated
    hidden [Management.Automation.SteppablePipeline] $_pipeline

    DecoratedCommand ([Management.Automation.CommandInfo]$DecoratedCommand)
    {
        if ($null -eq $DecoratedCommand)
        {
            throw [ArgumentException]::new("Decorated command cannot be null", 'DecoratedCommand')
        }
        $this._decorated = $DecoratedCommand
    }

    [Management.Automation.RuntimeDefinedParameterDictionary] GetParameters()
    {
        $DynParams = [Management.Automation.RuntimeDefinedParameterDictionary]::new()

        Write-Host "in GetParameters"
        $OriginalParams = $this._decorated.Parameters.Values | Where-Object {
            -not $CommonParameters.Contains($_.Name)
        }
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

    [void] Begin()
    {
        $Caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        $Vars = $Caller.GetFrameVariables()
        $PSBP = [hashtable]$Vars.PSBoundParameters.Value
        $PSBP.Remove('Decorated')
        $Wrapper = {& $this._decorated @PSBP}
        $this._pipeline = $Wrapper.GetSteppablePipeline()
        $this._pipeline.Begin($Vars.PSCmdlet)
    }

    [array] Process([object]$InputObject)
    {
        return $this._pipeline.Process($InputObject)
    }

    [array] End()
    {
        return $this._pipeline.End()
    }
}

class DecorateWithAttribute : Attribute
{
    DecorateWithAttribute ([string]$DecoratorName)
    {
        Write-Host "In DecorateWithAttribute" -ForegroundColor DarkGray
        $this.DecoratorName = $DecoratorName
    }

    [Management.Automation.CommandInfo]$Decorator
    [string]$DecoratorName
}


#region Reflection
$PrivateFlags = [Reflection.BindingFlags]'Nonpublic, Instance'

# Private method to update function scriptblock - this is used internally to save regenerating everything
$UpdateMethod = [Management.Automation.FunctionInfo].GetMethod('Update', $PrivateFlags, [type[]]([scriptblock], [bool], [Management.Automation.ScopedItemOptions], [string]))

$InternalSessionStateProperty = [Management.Automation.SessionState].GetProperty('Internal', $PrivateFlags)

$GetFunctionTableMethod = $InternalSessionStateProperty.PropertyType.GetMethod('GetFunctionTable', $PrivateFlags)
#endregion Reflection

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


    $DecoratedFunctions | ForEach-Object {
        $Decorated = $OriginalCommand = $_
        Write-Host "Updating function: $Decorated" -ForegroundColor DarkGray

        $DecoratorAttribute = $Decorated.ScriptBlock.Ast.Body.ParamBlock.Attributes.Where({
            $_.TypeName.FullName -eq [DecorateWithAttribute].FullName
        })
        $DecoratorName = $DecoratorAttribute.PositionalArguments.Value
        $Decorator = $FunctionTable[$DecoratorName]

        # Clone the decorated command. The clone has the original code, and is called
        # "original" - the original will be modified in place and left in the FunctionTable.
        $Ctor = $Decorated.GetType().GetConstructor($PrivateFlags, $Decorated.GetType())
        $OriginalCommand = $Ctor.Invoke($Decorated)

        $Wrapper = & {
            # Create new scope and bring in vars from parent scope - this reduces the size of the closure
            $OriginalCommand = $OriginalCommand
            $Decorated = [DecoratedCommand]::new($OriginalCommand)
            $DynParams = $Decorated.GetParameters()
            $Decorator = $Decorator

            return {
                [CmdletBinding()]
                param ()

                dynamicparam
                {
                    $DynParams
                }

                begin
                {
                    $Pipeline = {& $Decorator -Decorated $Decorated @PSBoundParameters}.GetSteppablePipeline()
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
