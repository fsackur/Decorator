
function SUT
{
    [Decorate({
        Decorator
    })]
    [CmdletBinding()]
    param
    (
        [Parameter(Position = 0)]
        $foo
    )

    if ($ExtraParam)
    {
        return $foo, $ExtraParam -join ':'
    }
    return $foo
}
