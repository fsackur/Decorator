
function Dec
{
    [CmdletBinding()]
    param
    (
        [CommandInfo]$CmdToWrap,

        [string]$ExtraParam
    )

    & $CmdToWrap
}
