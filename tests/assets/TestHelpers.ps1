
$Script:WriteHostSetup = {
    $HostWrites = [System.Collections.Generic.List[string]]::new()
    Mock Write-Host {$HostWrites.Add([string]$Object)}
}

function ShouldWrite
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Expected
    )

    Set-Variable SENTINEL -Option Constant 'khlkjsdhglshdglkjshdlgkhsldghslkdhglssdlkhg'

    $e = $HostWrites.GetEnumerator()
    $PreviousLine = $SENTINEL
    foreach ($ExpectedLine in $Expected)
    {
        $e.Where({$_ -like $ExpectedLine}, 'Until'), $e.Current |
            Write-Output |
            Should -Contain $ExpectedLine -Because "'$ExpectedLine' should appear $(
                if ($PreviousLine -ne $SENTINEL) {"after '$PreviousLine' "}
            )in $(
                if ($HostWrites) {"@('$($HostWrites -join "', '")')"} else {"@()"}
            )"

        $PreviousLine = $ExpectedLine
    }
}
