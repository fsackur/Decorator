function Decorator
{
    $InjectedValue = 2

    CmdToWrap
}

function CmdToWrap
{
    [Decorate({
        Decorator
    })]
    [CmdletBinding()]
    param ()

    return $InjectedValue
}
