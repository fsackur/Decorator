function bar {Write-Host "I'm in the bar!"}
function foo
{
    param
    (
        $ec = $ExecutionContext
    )

    # $Global:CMDLETCounter = 0
    $ExecutionContext.InvokeCommand.PreCommandLookupAction = {
        param ($CommandName, $EventArgs)
        Write-Host $CommandName -ForegroundColor Yellow
        if ($CommandName -eq 'foo') # -and $Global:CMDLETCounter -eq 0)
        {
            <#
                TypeName: System.Management.Automation.CommandLookupEventArgs

            Name               MemberType Definition
            ----               ---------- ----------
            Equals             Method     bool Equals(System.Object obj)
            GetHashCode        Method     int GetHashCode()
            GetType            Method     type GetType()
            ToString           Method     string ToString()
            Command            Property   System.Management.Automation.CommandInfo Command {get;set;}
            CommandName        Property   string CommandName {get;}
            CommandOrigin      Property   System.Management.Automation.CommandOrigin CommandOrigin {get;}
            CommandScriptBlock Property   scriptblock CommandScriptBlock {get;set;}
            StopSearch         Property   bool StopSearch {get;set;}
            #>
            $EventArgs | fl * | Out-String | Write-Host #ConvertTo-Json -Depth 10 >> C:/gitroot/Decr8r/foo.json
            # $EventArgs.Command = gcm bar
            $EventArgs.CommandScriptBlock = {bar}
            $EventArgs.StopSearch = $true

            # $Global:CMDLETCounter++
            # $EventArgs.CommandScriptBlock = {
            #     if ($Global:CMDLETCounter -eq 1)
            #     {
            #         if (-not ($args -match ($newArg = '-lock=')))
            #         {
            #             $args += "${newArg}true"
            #         }
            #     }
            #     & "terraform" @args
            #     $Global:CMDLETCounter--
            # }
        }
    }
}
