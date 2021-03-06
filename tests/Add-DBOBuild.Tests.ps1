﻿Param (
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

$workFolder = Join-PSFPath $here etc "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$scriptFolder = Get-Item (Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success")
$noRecurseFolder = Get-Item (Join-PSFPath -Normalize "$here\etc\sqlserver-tests")
$v1scripts = Get-Item (Join-Path $scriptFolder '1.sql')
$v2scripts = Get-Item (Join-Path $scriptFolder '2.sql')
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$packageNameTest = "$packageName.test.zip"
$packageNoPkgFile = Join-Path $workFolder "pkg_nopkgfile.zip"

Describe "Add-DBOBuild tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "adding version 2.0 to existing package" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath $v2scripts -Name $packageNameTest -Build 2.0
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should only contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should Not BeIn $testResults.Path
        }
        It "build 2.0 should only contain scripts from 2.0" {
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "adding new files only based on source path (Type = New)" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\* -Name $packageNameTest -Build 2.0 -Type 'New'
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should Not Be $null
            $testResults.Version | Should Be '2.0'
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Builds | Where-Object Build -eq '1.0' | Should Not Be $null
            $testResults.Builds | Where-Object Build -eq '2.0' | Should Not Be $null
            $testResults.FullName | Should Be $packageNameTest
            $testResults.Length -gt 0 | Should Be $true
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should only contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should Not BeIn $testResults.Path
        }
        It "build 2.0 should only contain scripts from 2.0" {
            Join-PSFPath -Normalize "content\2.0\2.sql" | Should BeIn $testResults.Path
            Join-PSFPath -Normalize "content\2.0\1.sql" | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "adding new files only based on hash (Type = Unique/Modified)" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
            $null = Copy-Item $v1scripts "$workFolder\Test.sql"
        }
        AfterAll {
            $null = Remove-Item $packageNameTest
            $null = Remove-Item "$workFolder\Test.sql"
        }
        It "should add new build to existing package" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\*, "$workFolder\Test.sql" -Name $packageNameTest -Build 2.0 -Type 'Unique'
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should Not Be $null
            $testResults.Version | Should Be '2.0'
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            '1.0' | Should BeIn $testResults.Builds.Build
            '2.0' | Should BeIn $testResults.Builds.Build
            $testResults.FullName | Should Be $packageNameTest
            $testResults.Length -gt 0 | Should Be $true
            Test-Path $packageNameTest | Should Be $true
        }
        It "should add new build to existing package based on changes in the file" {
            $null = Add-DBOBuild -ScriptPath "$workFolder\Test.sql" -Name $packageNameTest -Build 2.1
            "nope" | Out-File "$workFolder\Test.sql" -Append
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\*, "$workFolder\Test.sql" -Name $packageNameTest -Build 3.0 -Type 'Modified'
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            $testResults.Configuration | Should Not Be $null
            $testResults.Version | Should Be '3.0'
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            '1.0' | Should BeIn $testResults.Builds.Build
            '2.0' | Should BeIn $testResults.Builds.Build
            '2.1' | Should BeIn $testResults.Builds.Build
            '3.0' | Should BeIn $testResults.Builds.Build
            $testResults.FullName | Should Be $packageNameTest
            $testResults.Length -gt 0 | Should Be $true
            Test-Path $packageNameTest | Should Be $true
        }
        $testResults = Get-ArchiveItem $packageNameTest
        It "build 1.0 should only contain scripts from 1.0" {
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\2.sql' | Should Not BeIn $testResults.Path
        }
        It "build 2.0 should only contain scripts from 2.0" {
            Join-PSFPath -Normalize "content\2.0\2.sql" | Should BeIn $testResults.Path
            Join-PSFPath -Normalize "content\2.0\1.sql" | Should Not BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\Test.sql' | Should Not BeIn $testResults.Path
        }
        It "build 3.0 should only contain scripts from 3.0" {
            Join-PSFPath -Normalize 'content\3.0\Test.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize "content\3.0\2.sql" | Should Not BeIn $testResults.Path
            Join-PSFPath -Normalize "content\3.0\1.sql" | Should Not BeIn $testResults.Path
        }
        It "should contain module files" {
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
    }
    Context "adding files with different root folders" {
        BeforeAll {
            Push-Location -Path $here
        }
        AfterAll {
            Pop-Location
        }
        BeforeEach {
            $null = Copy-Item $packageName $packageNameTest
            #$null = Copy-Item $v1scripts "$workFolder\Test.sql"
        }
        AfterEach {
            $null = Remove-Item $packageNameTest
            #$null = Remove-Item "$workFolder\Test.sql"
        }
        It "should add new build to existing package as a relative path" {
            $testResults = Add-DBOBuild -ScriptPath $v2scripts -Name $packageNameTest -Build 2.0 -Relative
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0' ((Resolve-Path $v2scripts -Relative) -replace '^\.\\|^\.\/', '') | Should BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should Not BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0' ((Resolve-Path $v2scripts -Relative) -replace '^\.\\|^\.\/', '') | Should BeIn $items.Path
        }
        It "should add new build to existing package as an absolute path" {
            $testResults = Add-DBOBuild -ScriptPath $v2scripts -Name $packageNameTest -Build 2.0 -Absolute
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0' ($v2scripts -replace ':', '') | Should BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should Not BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0' ($v2scripts -replace ':', '') | Should BeIn $items.Path
        }
        It "should add new build without recursion" {
            $testResults = Add-DBOBuild -ScriptPath $noRecurseFolder -Name $packageNameTest -Build 2.0 -NoRecurse
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\Cleanup.sql' | Should BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\1.sql' | Should Not BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\2.sql' | Should Not BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\3.sql' | Should Not BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\Cleanup.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\1.sql' | Should Not BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\2.sql' | Should Not BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\sqlserver-tests\success\3.sql' | Should Not BeIn $items.Path
        }
        It "Should add only matched files" {
            $testResults = Add-DBOBuild -ScriptPath $scriptFolder\* -Name $packageNameTest -Build 2.0 -Match '2\.sql'
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should Not BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\3.sql' | Should Not BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\1.sql' | Should Not BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\2.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\3.sql' | Should Not BeIn $items.Path
        }
        It "Should add only matched files from a recursive folder" {
            $testResults = Add-DBOBuild -ScriptPath $noRecurseFolder\* -Name $packageNameTest -Build 2.0 -Match '2\.sql'
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageNameTest -Leaf)
            Test-Path $packageNameTest | Should Be $true
            $scripts = $testResults.GetBuild('2.0').Scripts
            $scripts | Should -Not -BeNullOrEmpty
            Join-PSFPath -Normalize 'content\2.0\success\1.sql' | Should Not BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should BeIn $scripts.GetPackagePath()
            Join-PSFPath -Normalize 'content\2.0\success\3.sql' | Should Not BeIn $scripts.GetPackagePath()
            $items = Get-ArchiveItem $packageNameTest
            Join-PSFPath -Normalize 'content\1.0\1.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\1.sql' | Should Not BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should BeIn $items.Path
            Join-PSFPath -Normalize 'content\2.0\success\3.sql' | Should Not BeIn $items.Path
        }
    }
    Context "negative tests" {
        BeforeAll {
            $null = Copy-Item $packageName $packageNameTest
            $null = New-DBOPackage -Name $packageNoPkgFile -Build 1.0 -ScriptPath $scriptFolder
            $null = Remove-ArchiveItem -Path $packageNoPkgFile -Item 'dbops.package.json'
        }
        AfterAll {
            Remove-Item $packageNameTest
            Remove-Item $packageNoPkgFile
        }
        It "should show warning when there are no new files" {
            $null = Add-DBOBuild -Name $packageNameTest -ScriptPath $v1scripts -Type 'Unique' -WarningVariable warningResult 3>$null
            $warningResult.Message -join ';' | Should BeLike '*No scripts have been selected, the original file is unchanged.*'
        }
        It "should throw error when package data file does not exist" {
            try {
                $null = Add-DBOBuild -Name $packageNoPkgFile -ScriptPath $v2scripts
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*Incorrect package format*'
        }
        It "should throw error when package zip does not exist" {
            { Add-DBOBuild -Name ".\nonexistingpackage.zip" -ScriptPath $v1scripts -ErrorAction Stop } | Should Throw
        }
        It "should throw error when path cannot be resolved" {
            try {
                $null = Add-DBOBuild -Name $packageNameTest -ScriptPath ".\nonexistingsourcefiles.sql"
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
        }
        It "should throw error when scripts with the same relative path is being added" {
            try {
                $null = Add-DBOBuild -Name $packageNameTest -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike 'File * already exists*'
        }
    }
}
