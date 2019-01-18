Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$packageName = Join-PSFPath -Normalize "$here\etc\$commandName.zip"

$script1 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$script2 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$script3 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\3.sql"
$outConfig = Join-PSFPath -Normalize "$here\etc\out_full_config.json"
$fullConfig = Join-PSFPath -Normalize "$here\etc\tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$securePassword = $testPassword | ConvertTo-SecureString -Force -AsPlainText
$encryptedString = $securePassword | ConvertTo-EncryptedString 3>$null

Describe "DBOpsConfig class tests" -Tag $commandName, UnitTests, DBOpsConfig {
    BeforeAll {
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
        if (Test-Path $outConfig) { Remove-Item $outConfig }
    }
    Context "tests DBOpsConfig constructors" {
        It "Should return an empty config by default" {
            $testResult = [DBOpsConfig]::new()
            foreach ($prop in $testResult.psobject.properties.name) {
                $testResult.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
            }
        }
        It "Should return empty configuration from empty config file" {
            $testResult = [DBOpsConfig]::new((Get-Content "$here\etc\empty_config.json" -Raw))
            $testResult.ApplicationName | Should Be $null
            $testResult.SqlInstance | Should Be $null
            $testResult.Database | Should Be $null
            $testResult.DeploymentMethod | Should Be $null
            $testResult.ConnectionTimeout | Should Be $null
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential | Should Be $null
            $testResult.Username | Should Be $null
            $testResult.Password | Should Be $null
            $testResult.SchemaVersionTable | Should Be $null
            $testResult.Silent | Should Be $null
            $testResult.Variables | Should Be $null
            $testResult.Schema | Should BeNullOrEmpty
        }
        It "Should return all configurations from the config file" {
            $testResult = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            $testResult.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables.foo | Should -Be 'bar'
            $testResult.Variables.boo | Should -Be 'far'
            $testResult.Schema | Should Be "testschema"
        }
    }
    Context "tests other methods of DBOpsConfig" {
        It "should test AsHashtable method" {
            $testResult = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).AsHashtable()
            $testResult.GetType().Name | Should Be 'hashtable'
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            $testResult.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables.foo | Should -Be 'bar'
            $testResult.Variables.boo | Should -Be 'far'
            $testResult.Schema | Should Be "testschema"
        }
        It "should test SetValue method" {
            $config = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            #String property
            $config.SetValue('ApplicationName', 'MyApp2')
            $config.ApplicationName | Should Be 'MyApp2'
            $config.SetValue('ApplicationName', $null)
            $config.ApplicationName | Should Be $null
            $config.SetValue('ApplicationName', 123)
            $config.ApplicationName | Should Be '123'
            #Int property
            $config.SetValue('ConnectionTimeout', 11)
            $config.ConnectionTimeout | Should Be 11
            $config.SetValue('ConnectionTimeout', $null)
            $config.ConnectionTimeout | Should Be $null
            $config.SetValue('ConnectionTimeout', '123')
            $config.ConnectionTimeout | Should Be 123
            { $config.SetValue('ConnectionTimeout', 'string') } | Should Throw
            #Bool property
            $config.SetValue('Silent', $false)
            $config.Silent | Should Be $false
            $config.SetValue('Silent', $null)
            $config.Silent | Should Be $null
            $config.SetValue('Silent', 2)
            $config.Silent | Should Be $true
            $config.SetValue('Silent', 0)
            $config.Silent | Should Be $false
            $config.SetValue('Silent', 'string')
            $config.Silent | Should Be $true
            #SecureString property
            $config.SetValue('Password', $encryptedString)
            [PSCredential]::new('test', $config.Password).GetNetworkCredential().Password | Should Be $testPassword
            $config.SetValue('Password', $null)
            $config.Password | Should Be $null
            #PSCredential property
            $config.SetValue('Credential', ([pscredential]::new('CredentialUser', $securePassword)))
            $config.Credential.UserName | Should Be 'CredentialUser'
            $config.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $config.SetValue('Credential', $null)
            $config.Credential | Should Be $null
            #hashtable
            $config.SetValue('ConnectionAttribute', @{ 'Connection Timeout' = 10 })
            $config.ConnectionAttribute.'Connection Timeout' | Should -Be 10
            #Negatives
            { $config.SetValue('AppplicationName', 'MyApp3') } | Should Throw
        }
        It "should test ExportToJson method" {
            $testResult = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).ExportToJson() | ConvertFrom-Json -ErrorAction Stop
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            [PSCredential]::new('test', ($testResult.Credential.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', ($testResult.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables.foo | Should -Be 'bar'
            $testResult.Variables.boo | Should -Be 'far'
            $testResult.Schema | Should Be "testschema"
        }
        It "should test Merge method into full config" {
            $config = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            $hashtable = @{
                ApplicationName   = 'MyTestApp2'
                ConnectionTimeout = 0
                SqlInstance       = $null
                Silent            = $false
                ExecutionTimeout  = 20
                Schema            = "test3"
                Password          = $null
                Credential        = $null
                Variables         = @{
                    foo = "bar2"
                    goo = "yarr"
                }
            }
            $config.Merge($hashtable)
            $config.ApplicationName | Should Be "MyTestApp2"
            $config.SqlInstance | Should Be $null
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 0
            $config.ExecutionTimeout | Should Be 20
            $config.Encrypt | Should Be $null
            $config.Credential | Should Be $null
            $config.Username | Should Be "TestUser"
            $config.Password | Should Be $null
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $false
            $config.Variables.foo | Should Be "bar2"
            $config.Variables.boo | Should Be "far"
            $config.Variables.goo | Should Be "yarr"
            $config.Schema | Should Be "test3"
            #negative
            { $config.Merge(@{foo = 'bar'}) } | Should Throw
            { $config.Merge($null) } | Should Throw
        }
        It "should test Merge method into empty config" {
            $config = [DBOpsConfig]::new()
            $hashtable = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).AsHashtable()
            $config.Merge($hashtable)
            $config.ApplicationName | Should Be "MyTestApp"
            $config.SqlInstance | Should Be "TestServer"
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 40
            $config.ExecutionTimeout | Should Be 0
            $config.Encrypt | Should Be $null
            $config.Credential.UserName | Should Be 'CredentialUser'
            $config.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $config.Username | Should Be "TestUser"
            [PSCredential]::new('test', $config.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $true
            $config.Variables.foo | Should -Be 'bar'
            $config.Variables.boo | Should -Be 'far'
            $config.Schema | Should Be "testschema"
            #negative
            { $config.Merge(@{foo = 'bar'}) } | Should Throw
            { $config.Merge($null) } | Should Throw
        }
    }
    Context "tests Save/Alter methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "should test Save method" {
            #Generate new package file
            $pkg = [DBOpsPackage]::new()
            $pkg.Configuration.ApplicationName = 'TestApp2'
            $pkg.SaveToFile($packageName)

            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            $stream = [FileStream]::new($packageName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
                try {
                    #Initiate saving
                    $pkg.Configuration.Save($zip)
                }
                catch {
                    throw $_
                }
                finally {
                    #Close archive
                    $zip.Dispose()
                }
            }
            catch {
                throw $_
            }
            finally {
                #Close archive
                $stream.Dispose()
            }
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should BeIn $testResults.Path
            }
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
            'Deploy.ps1' | Should BeIn $testResults.Path
        }
        It "Should load package successfully after saving it" {
            $pkg = [DBOpsPackage]::new($packageName)
            $pkg.Configuration.ApplicationName | Should Be 'TestApp2'
        }
        It "should test Alter method" {
            $pkg = [DBOpsPackage]::new($packageName)
            $pkg.Configuration.ApplicationName = 'TestApp3'
            $pkg.Configuration.Alter()
            $testResults = Get-ArchiveItem "$packageName"
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should BeIn $testResults.Path
            }
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
            'Deploy.ps1' | Should BeIn $testResults.Path
        }
        It "Should load package successfully after saving it" {
            $p = [DBOpsPackage]::new($packageName)
            $p.Configuration.ApplicationName | Should Be 'TestApp3'
        }
        It "should test SaveToFile method" {
            [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).SaveToFile($outConfig)
            $testResult = Get-Content $outConfig -Raw | ConvertFrom-Json -ErrorAction Stop
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            [PSCredential]::new('test', ($testResult.Credential.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', ($testResult.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables | Should -Not -BeNullOrEmpty
            $testResult.Schema | Should Be "testschema"
        }
    }
    Context "tests static methods of DBOpsConfig" {
        It "should test static GetDeployFile method" {
            $f = [DBOpsConfig]::GetDeployFile()
            $f.Type | Should Be 'Misc'
            $f.Path | Should BeLike (Join-PSFPath -Normalize '*\Deploy.ps1')
            $f.Name | Should Be 'Deploy.ps1'
        }
        It "should test static FromFile method" {
            $testResult = [DBOpsConfig]::FromFile($fullConfig)
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            $testResult.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables | Should -Not -BeNullOrEmpty
            $testResult.Schema | Should Be "testschema"
            #negatives
            { [DBOpsConfig]::FromFile((Join-PSFPath -Normalize "$here\etc\notajsonfile.json")) } | Should Throw
            { [DBOpsConfig]::FromFile((Join-PSFPath -Normalize "nonexisting\file")) } | Should Throw
            { [DBOpsConfig]::FromFile($null) } | Should Throw
        }
        It "should test static FromJsonString method" {
            $testResult = [DBOpsConfig]::FromJsonString((Get-Content $fullConfig -Raw))
            $testResult.ApplicationName | Should Be "MyTestApp"
            $testResult.SqlInstance | Should Be "TestServer"
            $testResult.Database | Should Be "MyTestDB"
            $testResult.DeploymentMethod | Should Be "SingleTransaction"
            $testResult.ConnectionTimeout | Should Be 40
            $testResult.ExecutionTimeout | Should Be 0
            $testResult.Encrypt | Should Be $null
            $testResult.Credential.UserName | Should Be 'CredentialUser'
            $testResult.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $testResult.Username | Should Be "TestUser"
            [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResult.SchemaVersionTable | Should Be "test.Table"
            $testResult.Silent | Should Be $true
            $testResult.Variables | Should -Not -BeNullOrEmpty
            $testResult.Schema | Should Be "testschema"
            #negatives
            { [DBOpsConfig]::FromJsonString((Get-Content "$here\etc\notajsonfile.json" -Raw)) } | Should Throw
            { [DBOpsConfig]::FromJsonString($null) } | Should Throw
            { [DBOpsConfig]::FromJsonString('') } | Should Throw
        }
    }
}