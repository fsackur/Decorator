#requires -Modules @{ModuleName = 'InvokeBuild'; ModuleVersion = '5.10.4'}

param
(
    [version]$NewVersion,

    [string]$PSGalleryApiKey,

    [string]$ModuleName = $MyInvocation.MyCommand.Name -replace '\.build\.ps1$',

    [string]$ManifestPath = "$ModuleName.psd1",

    [string[]]$Include = ('*.psd1', '*.psm1', '*.ps1xml', '*.psrc', 'README*', 'LICENSE*'),

    [string[]]$PSScriptFolders = ('Classes', 'Private', 'Public'),

    [string]$CsProjPath = (Join-Path src "$ModuleName.csproj"),

    [string]$BinOutputFolder = 'bin',

    [string[]]$BinInclude = ('*.dll', '*.pdb'),

    [string]$OutputFolder = 'Build'
)

$ModuleBase = $BuildRoot |
    Join-Path -ChildPath $OutputFolder |
    Join-Path -ChildPath $ModuleName
$BuiltAssembly = Join-Path $ModuleBase "$ModuleName.dll"
$BuiltManifest = Join-Path $ModuleBase "$ModuleName.psd1"

# Synopsis: Update manifest version
task UpdateVersion {
    $ManifestPath = "$ModuleName.psd1"
    $ManifestContent = Get-Content $ManifestPath -Raw
    $Manifest = Invoke-Expression "DATA {$ManifestContent}"

    if ($NewVersion -le [version]$Manifest.ModuleVersion)
    {
        throw "Can't go backwards: $NewVersion =\=> $($Manifest.ModuleVersion)"
    }

    $ModuleVersionPattern = "(?<=\n\s*ModuleVersion\s*=\s*(['`"]))(\d+\.)+\d+"

    $ManifestContent = $ManifestContent -replace $ModuleVersionPattern, $NewVersion
    $ManifestContent | Out-File $ManifestPath -Encoding utf8
}

# Synopsis: Run PSSA, excluding Tests folder and *.build.ps1
task PSSA {
    $Files = $Include, $PSScriptFolders |
        Write-Output |
        Where-Object {Test-Path $_} |
        Get-ChildItem -Recurse -Exclude PSDiagnostics.psm1
    # $Files +=  | Where-Object {Test-Path $_} | Get-Item

    $Files |
        ForEach-Object {
            Invoke-ScriptAnalyzer -Path $_.FullName -Recurse -Settings .\.vscode\PSScriptAnalyzerSettings.psd1
        } |
        Tee-Object -Variable PSSAOutput

    if ($PSSAOutput | Where-Object Severity -ge ([int][Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticSeverity]::Warning))
    {
        throw "PSSA found code violations"
    }
}

# Synopsis: Clean build folder
task Clean {
    remove $OutputFolder
}

# Synopsis: Create build folder
task CreateFolder {
    $null = New-Item $ModuleBase -ItemType Directory -Force
}

# Synopsis: Build C# project
task CSBuild @{
    Inputs  = {Get-ChildItem src -Exclude bin, obj | Get-ChildItem -File -Recurse}
    Outputs = $BuiltAssembly
    Jobs    = 'CreateFolder', {

        exec {dotnet build $CsProjPath --output $BinOutputFolder}

        $BinInclude |
            ForEach-Object {Join-Path $BinOutputFolder $_} |
            Where-Object {Test-Path $_} |
            Get-Item |
            Copy-Item -Destination $ModuleBase -Recurse
    }
}

# Synopsis: Build PS module at manifest version
task PSBuild @{
    Inputs  = {($Include | Get-Item), ($PSScriptFolders | Get-ChildItem -Recurse) | Write-Output}
    Outputs = $BuiltManifest
    Jobs    = 'CreateFolder', {

        $RootModulePath = Join-Path $ModuleBase "$ModuleName.psm1"

        $Include |
            Where-Object {Test-Path $_} |
            Get-Item |
            Copy-Item -Destination $ModuleBase -Recurse

        $PSScriptFolders |
            Where-Object {Test-Path $_} |
            ForEach-Object {
                "",
                "#region $_",
                ($_ | Get-ChildItem | Get-Content),
                "#endregion $_",
                ""
            } |
            Write-Output |
            Out-File $RootModulePath -Append -Encoding utf8NoBOM

        $BuiltManifest | Get-Item | ForEach-Object {$_.LastWriteTime = [datetime]::Now}
    }
}

task Build CSBuild, PSBuild

$TestRunner = {
    Import-Module $ModuleBase -Force -Global -ErrorAction Stop -DisableNameChecking
    Invoke-Pester -Configuration @{Run = @{Throw = $true}}
}

# Synopsis: Run Pester in current process
task TestInProcess Build, $TestRunner

# Synopsis: Run Pester in new pwsh process
task Test Build, {
    exec {pwsh -NoProfile -Command ($TestRunner -replace '\$ModuleBase\b', "'$ModuleBase'")}
}

# Synopsis: Run Pester in new (windows) powershell process
task TestWindowsPowershell Build, {
    exec {powershell -NoProfile -Command ($TestRunner -replace '$ModuleBase\b', "'$ModuleBase'")}
}

# Synopsis: Publish to PSGallery
task Publish CSBuild, PSBuild, Test, TestWindowsPowershell, {
    Publish-PSResource -Verbose -Path $ModuleBase -DestinationPath Build -Repository PSGallery -ApiKey $PSGalleryApiKey
}
