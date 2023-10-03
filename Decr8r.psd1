@{
    ModuleVersion        = '0.0.1'

    GUID                 = 'b5cdf400-80fd-4e8b-9a05-553171c5d537'
    Author               = 'Freddie Sackur'
    CompanyName          = 'DustyFox'
    Copyright            = '(c) 2021 Freddie Sackur. All rights reserved.'

    Description          = 'Function decorators, like Python!'
    HelpInfoURI          = 'https://github.com/fsackur/Decr8r'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    RootModule           = 'Decr8r.psm1'

    RequiredModules      = @()

    NestedModules        = @(
        'src/bin/Debug/net7.0/Decr8r.dll'
    )

    FunctionsToExport    = @(
        '*'
    )

    PrivateData          = @{
        PSData = @{
            Tags       = @(
                'MetaProgramming',
                'CodeGeneration',
                'Decorator',
                'Decorators',
                'Wrap',
                'Wrapper',
                'Wrappers',
                'Attribute',
                'Attributes'
            )
            LicenseUri = 'https://raw.githubusercontent.com/fsackur/Decr8r/main/LICENSE'
            ProjectUri = 'https://github.com/fsackur/Decr8r'
        }
    }
}
