function Test-DynParam
{
    [CmdletBinding()]
    param ($bar)

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


$Command = Get-Command Test-DynParam
$CommandMetadata = [System.Management.Automation.CommandMetadata]::new($Command)
[System.Management.Automation.ProxyCommand]::Create($CommandMetadata, "foo", $true)
# Should output "True"

# $IdpProperty = [System.Management.Automation.CommandMetadata].GetProperty('ImplementsDynamicParameters', ([System.Reflection.BindingFlags]'NonPublic,Instance'))
# $IdpProperty.GetValue($CommandMetadata)
# Should output "True"

# $CommandMetadata.ImplementsDynamicParameters
