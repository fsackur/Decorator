function test-p
{
    param
    (
        [Parameter(ValueFromPipelineByPropertyName)]$Name,
        [Parameter(ValueFromPipelineByPropertyName)]$Length,
        [Parameter(ValueFromPipelineByPropertyName)]$Mode,
        $Msg
    )

    begin
    {
        # [pscustomobject][hashtable]$PSBoundParameters
        $PSBoundParameters.GetEnumerator() | % {"$($_.Key): $($_.Value)"}
        [string[]]$Static = $PSBoundParameters.Keys
        $PSBoundParameters.Clear()
    }

    process
    {
        [pscustomobject][hashtable]$PSBoundParameters #.GetEnumerator() | where {$_.Key -notin $Static}
    }
}

# gci | test-p
