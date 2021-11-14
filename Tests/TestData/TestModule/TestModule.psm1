function Decorator
{
    $InjectedValue = 2

    CmdToWrap
}

function CmdToWrap
{
    [CmdletBinding()]
    param ()

    return $InjectedValue
}