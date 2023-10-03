$TypeAccelerators = [PSObject].Assembly.GetType("System.Management.Automation.TypeAccelerators")

<#
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


#region Reflection
$PrivateFlags = [Reflection.BindingFlags]'Nonpublic, Instance'

# Private method to update function scriptblock - this is used internally to save regenerating everything
$UpdateMethod = [Management.Automation.FunctionInfo].GetMethod('Update', $PrivateFlags, [type[]]([scriptblock], [bool], [Management.Automation.ScopedItemOptions], [string]))

$InternalSessionStateProperty = [Management.Automation.SessionState].GetProperty('Internal', $PrivateFlags)

$GetFunctionTableMethod = $InternalSessionStateProperty.PropertyType.GetMethod('GetFunctionTableAtScope', $PrivateFlags)

$ContextProperty = [Management.Automation.CommandInfo].GetProperty('Context', $PrivateFlags)

$ScriptInfoCtor = [Management.Automation.ScriptInfo].GetConstructor($PrivateFlags, [type[]]([string], [scriptblock], $ContextProperty.PropertyType))
#endregion Reflection


class DecoratedCommand
{
    hidden [Management.Automation.CommandInfo] $_decorated
    hidden [Management.Automation.SteppablePipeline] $_pipeline

    DecoratedCommand ([scriptblock]$ScriptBlock)
    {
        $Caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        $Context = $Script:ContextProperty.GetValue($Caller.InvocationInfo.MyCommand)
        $ScriptInfo = $Script:ScriptInfoCtor.Invoke(([guid]::NewGuid().ToString(), $ScriptBlock, $Context))
        $this._decorated = $ScriptInfo
        $this | Add-Member -MemberType ScriptProperty -Name Parameters -Value {$this.GetParameters()}
    }

    DecoratedCommand ([Management.Automation.CommandInfo]$DecoratedCommand)
    {
        if ($null -eq $DecoratedCommand)
        {
            throw [ArgumentException]::new("Decorated command cannot be null", 'DecoratedCommand')
        }
        $this._decorated = $DecoratedCommand
        $this | Add-Member -MemberType ScriptProperty -Name Parameters -Value {$this.GetParameters()}
    }

    hidden [Management.Automation.RuntimeDefinedParameterDictionary] GetParameters()
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

    hidden [Management.Automation.RuntimeDefinedParameterDictionary] GetMergedParameters([Management.Automation.CommandInfo]$Decorator)
    {
        $DynParams = $this.GetParameters()

        $NewParams = $Decorator.Parameters.Values | Where-Object {
            $_.ParameterType -ne $this.GetType() -and
            -not $CommonParameters.Contains($_.Name)
        }
        $NewParams | ForEach-Object {
            $DynParam = [Management.Automation.RuntimeDefinedParameter]::new(
                $_.Name,
                $_.ParameterType,
                $_.Attributes
            )
            $DynParams[$_.Name] = $DynParam
        }

        return $DynParams
    }

    [void] Begin()
    {
        $Caller = Get-PSCallStack | Select-Object -Skip 1 -First 1
        $Vars = $Caller.GetFrameVariables()
        $PSBP = [hashtable]$Vars.PSBoundParameters.Value
        $DecParam = $Caller.InvocationInfo.MyCommand.Parameters.Values | Where-Object ParameterType -eq $this.GetType()
        $PSBP.Remove($DecParam.Name)
        $Wrapper = {& $this._decorated @PSBP}
        $this._pipeline = $Wrapper.GetSteppablePipeline($Caller.InvocationInfo.CommandOrigin)
        $this._pipeline.Begin($Vars.PSCmdlet.Value)
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

$TypeAccelerators::Add("DecorateWith", [DecorateWithAttribute])


function Initialize-Decorator
{
    param
    (
        [Parameter(Mandatory)]
        [Management.Automation.SessionState]$SessionState,

        [Parameter()]
        [ValidateSet('Local', 'Global', 'Script', 'Private', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9')]
        [string]$Scope = 'Local'
    )

    Write-Host "In Initialize-Decorator" -ForegroundColor DarkGray

    # if we call from the .psm1, the functions haven't been exported yet and this returns $null
    # So, use reflection to get the internal table
    $InternalSessionState = $InternalSessionStateProperty.GetValue($SessionState)
    $FunctionTable = $GetFunctionTableMethod.Invoke($InternalSessionState, $Scope)

    $ModuleFunctions = $FunctionTable.Values.Where({$_.Module -eq $SessionState.Module})

    # Attributes are lazy-instantiated, so not in .ScriptBlock.Attributes yet. We have to go to the AST.
    $DecoratedFunctions = $ModuleFunctions.Where({
        $_.ScriptBlock.Ast.Body.ParamBlock.Attributes.TypeName.FullName -like "DecorateWith*"
    })


    $DecoratedFunctions | ForEach-Object {
        $Decorated = $ModuleFunction = $_
        Write-Host "Updating function: $Decorated" -ForegroundColor DarkGray

        $DecoratorAttribute = $Decorated.ScriptBlock.Ast.Body.ParamBlock.Attributes.Where({
            $_.TypeName.FullName -eq [DecorateWithAttribute].FullName
        })
        $DecoratorName = $DecoratorAttribute.PositionalArguments.Value
        $Decorator = $FunctionTable[$DecoratorName]

        # Clone the decorated command. The clone has the original code, and is called
        # "original" - the original will be modified in place and left in the FunctionTable.
        $Ctor = $Decorated.GetType().GetConstructor($PrivateFlags, $Decorated.GetType())
        $Decorated = $Ctor.Invoke($Decorated)

        $Wrapper = & {
            # Create new scope and bring in vars from parent scope - this reduces the size of the closure
            $OriginalCommand = $OriginalCommand
            $Decorated = [DecoratedCommand]::new($Decorated)
            $DynParams = $Decorated.GetMergedParameters($Decorator)
            $Decorator = $Decorator
            $DecParam = $Decorator.Parameters.Values | Where-Object {$_.ParameterType.Name -eq "DecoratedCommand"}
            # $DecParam = $Decorator.Parameters.Values | Where-Object ParameterType -eq [DecoratedCommand]
            $Injector = @{$DecParam.Name = $Decorated}

            return {
                [CmdletBinding()]
                param ()

                dynamicparam
                {
                    $DynParams
                }

                begin
                {
                    $outBuffer = $null
                    if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer))
                    {
                        $PSBoundParameters['OutBuffer'] = 1
                    }

                    $Pipeline = {& $Decorator @Injector @PSBoundParameters}.GetSteppablePipeline()
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
            $ModuleFunction,
            (
                $Wrapper,
                $Force,
                $ModuleFunction.Options,
                ([string]$ModuleFunction.HelpFile)
            )
        )
    }
}
#>
