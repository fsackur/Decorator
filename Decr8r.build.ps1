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
    $Files = Get-ChildItem -File -Recurse -Filter *.ps*1 | Where-Object FullName -notmatch '\bTests\b|\.build\.ps1$|install-build-dependencies\.ps1'
    $Files | ForEach-Object {
        Invoke-ScriptAnalyzer -Path $_.FullName -Recurse -Settings .\.vscode\PSScriptAnalyzerSettings.psd1
    }
}

# Synopsis: Clean build folder
task Clean {
    remove $OutputFolder
}

# Synopsis: Build PS module at manifest version
task PSBuild {
    $ManifestContent = Get-Content $ManifestPath -Raw
    $Manifest = Invoke-Expression "DATA {$ManifestContent}"
    $Version = $Manifest.ModuleVersion
    $BuildFolder = New-Item "$OutputFolder/$ModuleName/$Version" -ItemType Directory -Force

    $RootModule = $Manifest.RootModule -replace '^$', "$ModuleName.psm1"
    $BuiltRootModulePath = Join-Path $BuildFolder $RootModule

    $Include |
        Where-Object {Test-Path $_} |
        Get-Item |
        Copy-Item -Destination $BuildFolder

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
        Out-File $BuiltRootModulePath -Append -Encoding utf8NoBOM
}

# Synopsis: Build C# project
task CSBuild {
    $ManifestContent = Get-Content $ManifestPath -Raw
    $Manifest = Invoke-Expression "DATA {$ManifestContent}"
    $Version = $Manifest.ModuleVersion
    $BuildFolder = New-Item "$OutputFolder/$ModuleName/$Version" -ItemType Directory -Force

    dotnet build $CsProjPath --output $BinOutputFolder

    $BinInclude |
        ForEach-Object {Join-Path $BinOutputFolder $_} |
        Where-Object {Test-Path $_} |
        Get-Item |
        Copy-Item -Destination $BuildFolder
}

# Synopsis: Run Pester in current process
task TestInProcess {
    Import-Module "$BuildRoot/$OutputFolder/$ModuleName" -Force -Global -ErrorAction Stop
    Invoke-Pester
}

# Synopsis: Run Pester in new pwsh process
task Test {
    pwsh -NoProfile -Command {
        Import-Module "$BuildRoot/$OutputFolder/$ModuleName" -Force -Global -ErrorAction Stop
        Invoke-Pester
    }
}

# Synopsis: Run Pester in new (windows) powershell process
task TestWindowsPowershell {
    powershell -NoProfile -Command {
        Import-Module "$BuildRoot/$OutputFolder/$ModuleName" -Force -Global -ErrorAction Stop
        Invoke-Pester
    }
}

# Synopsis: Publish to PSGallery
task Publish Clean, PSBuild, CSBuild, {
    $UnversionedBase = "$OutputFolder/$ModuleName"
    $VersionedBase = Get-Module $UnversionedBase -ListAvailable | ForEach-Object ModuleBase
    Get-ChildItem $VersionedBase | Copy-Item -Destination $UnversionedBase
    remove $VersionedBase
    Publish-PSResource -Verbose -Path $UnversionedBase -DestinationPath Build -Repository PSGallery -ApiKey $PSGalleryApiKey
}
