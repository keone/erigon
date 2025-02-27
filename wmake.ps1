﻿<#
   Copyright 2021 The Erigon Authors

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
#>

Param(
    [Parameter(Position=0, 
    HelpMessage="Enter the build target")]
    [Alias("target")]
    [ValidateSet(
        "clean",
        "cons",
        "db-tools",
        "devnettest",
        "downloader",
        "erigon",
        "evm",
        "hack",
        "integration",
        "observer",
        "pics",
        "rpcdaemon",
        "rpctest",
        "sentry",
        "state",
        "test",
        "test-integration",
        "txpool",
        "all"
    )]
    [string[]]$BuildTargets=@("erigon", "rpcdaemon", "sentry", "downloader", "integration")
)

# Sanity checks on $BuildTargets
if ($BuildTargets.Count -gt 1) {
    
    # "all" target must be alone
    if ($BuildTargets.Contains("all")) {
        Write-Host @"

  Error ! Target "all" must be set alone.

"@
        exit 1
    }

    # "clean" target must be alone
    if ($BuildTargets.Contains("clean")) {
        Write-Host @"

  Error ! Target "clean" must be set alone.

"@
        exit 1
    }

}

if ($BuildTargets[0] -eq "all") {
    $BuildTargets = @(
        "cons",
        "devnettest",
        "downloader",
        "erigon",
        "evm",
        "hack",
        "integration",
        "observer",
        "pics",
        "rpcdaemon",
        "rpctest",
        "sentry",
        "state",
        "txpool"
    )
}

# ====================================================================
# Messages texts
# ====================================================================

$headerText = @"

 ------------------------------------------------------------------------------
  Erigon's wmake.ps1 : Selected target(s) $($BuildTargets -join " ")
 ------------------------------------------------------------------------------
 
"@

$gitErrorText = @"

 Requirement Error.
 You need to have Git installed
 Please visit https://git-scm.com/downloads and download the appropriate
 installer.

"@

$goMinMinorVersion = 18
$goMinVersion = "1.$goMinMinorVersion"

$goErrorText = @"

 Requirement Error.
 You need to have Go Programming Language (aka golang) installed.
 Minimum required version is $goMinVersion
 Please visit https://golang.org/dl/ and download the appropriate
 installer.
 Ensure that go.exe installation
 directory is properly inserted into your PATH
 environment variable. 

"@

$chocolateyErrorText = @"

 Requirement Error.
 For this script to run properly you need to install
 chocolatey [https://chocolatey.org/] with the following
 mandatory components: 

 - cmake
 - make
 - mingw

"@

$chocolateyPathErrorText = @"

 Environment PATH Error.
 Chocolatey install has been detected but the environment
 variable PATH does not include a full path to its binaries
 Please amend your setup and ensure the following
 chocolatey directory is properly inserted into your PATH
 environment variable.

"@

$privilegeErrorText = @"

 Privileges Error !
 You must run this script with Administrator privileges

"@

# ====================================================================
# Functions
# ====================================================================

# -----------------------------------------------------------------------------
# Function 		: Get-Env
# -----------------------------------------------------------------------------
# Description	: Retrieves a value from a provided named environment var
# Returns       : $null / var value (if exists)
# -----------------------------------------------------------------------------
function Get-Env {
    param ([string]$varName = $(throw "A variable name must be provided"))
    $result = Get-ChildItem env: | Where-Object {$_.Name -ieq $varName}
    if (-not $result) {
        Write-Output $null
    } else {
        Write-Output $result.Value
    }
}

# -----------------------------------------------------------------------------
# Function 		: Get-Uninstall-Item
# -----------------------------------------------------------------------------
# Description	: Try get uninstall key for given item pattern
# Returns       : object
# -----------------------------------------------------------------------------
function Get-Uninstall-Item {
    param ([string]$pattern = $(throw "A search pattern must be provided"))    
    
    # Trying to get the enumerable of all installed programs using Get-ItemProperty may cause 
    # exceptions due to possible garbage values insterted into the registry by installers.
    # Specifically an invalid cast exception throws when registry keys contain invalid DWORD data. 
    # See https://github.com/PowerShell/PowerShell/issues/9552
    # Due to this all items must be parsed one by one

    $Private:regUninstallPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\"
    $Private:result = $null
    Get-ChildItem -Path $regUninstallPath | ForEach-Object {
        if(-not $result) {
            $item = Get-ItemProperty -Path $_.pspath
            if ($item.DisplayName -imatch $pattern) {
                $result = $item
                # DO NOT use break
            }
        }
    }
    Write-Output $result
}

# -----------------------------------------------------------------------------
# Function 		: Test-GO-Installed
# -----------------------------------------------------------------------------
# Description	: Checks whether or not GO language is installed
# Returns       : $true / $false
# -----------------------------------------------------------------------------
function Test-GO-Installed {
	$versionStr = go.exe version
	if (!($?)) {
		return $false
	}

	$minorVersionStr = $versionStr.Substring(15, 2)
	$minorVersion = [int]$minorVersionStr
	return ($minorVersion -ge $goMinMinorVersion)
}

# -----------------------------------------------------------------------------
# Function 		: Test-Git-Installed
# -----------------------------------------------------------------------------
# Description	: Checks whether or not Git is installed
# Returns       : $true / $false
# -----------------------------------------------------------------------------
function Test-Git-Installed {
    $Private:item   = Get-Uninstall-Item "^Git version [0-9\.]{1,}|^Git$"
    $Private:result = $false

    if ($Private:item) {
        Write-Host " Found Git version $($Private:item.DisplayVersion)"
        $Private:result = $true
    }

    Write-Output $Private:result
}

# -----------------------------------------------------------------------------
# Function 		: Test-Choco-Installed
# -----------------------------------------------------------------------------
# Description	: Checks whether or not chocolatey is installed
# Returns       : $true / $false
# -----------------------------------------------------------------------------
function Test-Choco-Installed {
    ## Test Chocolatey Install
    $script:chocolateyPath = Get-Env "chocolateyInstall"
    if(-not $chocolateyPath) {
        Write-Host $chocolateyErrorText
        return $false
    }
    
    # Test Chocolatey bin directory is actually in %PATH%
    $script:chocolateyBinPath = (Join-Path $chocolateyPath "bin")
    $script:chocolateyBinPathInPath = $false
    $private:pathExpanded = $env:Path.Split(";")
    for($i=0; $i -lt $pathExpanded.Count; $i++){
        $pathItem = $pathExpanded[$i]
        if($pathItem -ieq $chocolateyBinPath){
            Write-Host " Found $($chocolateyBinPath) in PATH"
            $chocolateyBinPathInPath = $true
        }
    }
    if(!$chocolateyBinPathInPath) {
        Write-Host $chocolateyPathErrorText
        Write-Host $chocolateyBinPath
        return $false
    }
    
    ## Test Chocolatey Components
    $chocolateyHasCmake = $false
    $chocolateyHasMake = $false
    $chocolateyHasMingw = $false
    $chocolateyComponents = @(clist -l)

    for($i=0; $i -lt $chocolateyComponents.Count; $i++){
        $item = $chocolateyComponents[$i]
        if($item -imatch "^cmake\ [0-9]") {
            $chocolateyHasCmake = $true
            Write-Host " Found Chocolatey component $($item)"
        }
        if($item -imatch "^make\ [0-9]") {
            $chocolateyHasMake = $true
            Write-Host " Found Chocolatey component $($item)"
        }
        if($item -imatch "^mingw\ [0-9]") {
            $chocolateyHasMingw = $true
            Write-Host " Found Chocolatey component $($item)"
        }
    }

    If(!$chocolateyHasCmake -or !$chocolateyHasMake -or !$chocolateyHasMingw) {
        Write-Host $chocolateyErrorText
        return $false
    }

    Get-Command cmake.exe | Out-Null
    if (!($?)) {
        Write-Host @"
    
     Error !
     Though chocolatey cmake installation is found I could not get
     the cmake binary executable. Ensure cmake installation
     directory is properly inserted into your PATH
     environment variable.
     (Usually $(Join-Path $env:ProgramFiles "Cmake\bin"))
    
"@
        return $false
    }
    
    return $true
}

# ====================================================================
# Main
# ====================================================================

$Error.Clear()
$ErrorActionPreference = "SilentlyContinue"

Write-Host $headerText

Set-Variable -Name "MyContext" -Value ([hashtable]::Synchronized(@{})) -Scope Script
$MyContext.Name       = $MyInvocation.MyCommand.Name
$MyContext.Definition = $MyInvocation.MyCommand.Definition
$MyContext.Directory  = (Split-Path (Resolve-Path $MyInvocation.MyCommand.Definition) -Parent)
$MyContext.StartDir   = (Get-Location -PSProvider FileSystem).ProviderPath
$MyContext.WinVer     = (Get-WmiObject Win32_OperatingSystem).Version.Split(".")
$MyContext.PSVer      = [int]$PSVersionTable.PSVersion.Major

# ====================================================================
# ## Test requirements
# ====================================================================
## Test Git is installed
if(!(Test-Git-Installed)) {
    Write-Host $gitErrorText
    exit 1
}
Get-Command git.exe | Out-Null
if (!($?)) {
    Write-Host @"
    
 Error !
 Though Git installation is found I could not get
 the Git binary executable. Ensure Git installation
 directory is properly inserted into your PATH
 environment variable.

"@
    exit 1
}

## GO language is installed
if(!(Test-GO-Installed)) {
    Write-Host $goErrorText
    exit 1
}

# Build erigon binaries
Set-Variable -Name "Erigon" -Value ([hashtable]::Synchronized(@{})) -Scope Script
$Erigon.Commit     = [string]@(git.exe rev-list -1 HEAD)
$Erigon.Branch     = [string]@(git.exe rev-parse --abbrev-ref HEAD)
$Erigon.Tag        = [string]@(git.exe describe --tags)

$Erigon.BuildTags = "nosqlite,noboltdb"
$Erigon.Package = "github.com/ledgerwatch/erigon"

$Erigon.BuildFlags = "-trimpath -tags $($Erigon.BuildTags) -buildvcs=false"
$Erigon.BuildFlags += " -ldflags ""-X $($Erigon.Package)/params.GitCommit=$($Erigon.Commit) -X $($Erigon.Package)/params.GitBranch=$($Erigon.Branch) -X $($Erigon.Package)/params.GitTag=$($Erigon.Tag)"""

$Erigon.BinPath    = [string](Join-Path $MyContext.StartDir "\build\bin")
$Erigon.Submodules = $false
$env:GO111MODULE = "on"

New-Item -Path $Erigon.BinPath -ItemType Directory -Force | Out-Null
if(!$?) {
   Write-Host @" 

  Error ! You don't have write access to current folder.
  Check your permissions and retry.

"@
    exit 1
}

Write-Host @"

 Erigon Branch : $($Erigon.Branch)
 Erigon Tag    : $($Erigon.Tag)
 Erigon Commit : $($Erigon.Commit)

"@

foreach($BuildTarget in $BuildTargets) {

## Choco components for building db-tools
if ($BuildTarget -eq "db-tools") {
    if(!(Test-choco-Installed)) {
        exit 1
    }

    $Erigon.MDBXSourcePath = [string](Join-Path $MyContext.StartDir "\libmdbx")
    if (!Test-Path -Path $Erigon.MDBXSourcePath -PathType Directory) {
        Write-Host @"

        Error ! Can't locate ""libmdbx"" folder
        Are you sure you have cloned the repository properly ?
"@
        exit 1
    }

    if (!Test-Path -Path [string](Join-Path $Erigon.MDBXSourcePath "\.git") -PathType Directory) {
        git.exe submodule update --init --recursive
        if($LASTEXITCODE) {
            Write-Host "An error has occurred while updating libmdbx submodule"
            exit $LASTEXITCODE
        }
    }

    # Create build directory for mdbx and enter it
    $Erigon.MDBXBuildPath = [string](Join-Path $Erigon.BinPath "\mdbx")
    New-Item -Path $Erigon.MDBXBuildPath -ItemType Directory -Force | Out-Null
    Set-Location $Erigon.MDBXBuildPath

    Write-Host " Building db-tools ..."

    cmake -G "MinGW Makefiles" "$($Erigon.MDBXSourcePath)" `
    -D CMAKE_MAKE_PROGRAM:PATH=""$(Join-Path $chocolateyBinPath "make.exe")"" `
    -D CMAKE_C_COMPILER:PATH=""$(Join-Path $chocolateyBinPath "gcc.exe")"" `
    -D CMAKE_CXX_COMPILER:PATH=""$(Join-Path $chocolateyBinPath "g++.exe")"" `
    -D CMAKE_BUILD_TYPE:STRING="Release" `
    -D MDBX_BUILD_SHARED_LIBRARY:BOOL=OFF `
    -D MDBX_WITHOUT_MSVC_CRT:BOOOL=OFF `
    -D MDBX_BUILD_TIMESTAMP=unknown `
    -D MDBX_FORCE_ASSERTIONS:INT=0
    if($LASTEXITCODE) {
        Write-Host "An error has occurred while configuring MDBX"
        exit $LASTEXITCODE
    }    

    cmake --build .
    if($LASTEXITCODE -or !(Test-Path "mdbx_stat.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_chk.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_copy.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_dump.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_load.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_drop.exe" -PathType leaf) `
                     -or !(Test-Path "mdbx_test.exe" -PathType leaf)) {
        Write-Host "An error has occurred while building MDBX tools"
        exit $LASTEXITCODE
    }

    Set-Location $MyContext.Directory
    # Eventually move all mdbx_*.exe to ./build/bin directory
    Move-Item -Path "$($Erigon.MDBXBuildPath)/mdbx_*.exe" -Destination $Erigon.BinPath -Force
}
    
if ($BuildTarget -eq "clean") {
    Write-Host " Cleaning ..."

    # Remove ./build/bin directory
    Remove-Item -Path "./build" -Recurse -Force

    # Clear go cache
    go.exe clean -cache

} elseif ($BuildTarget -eq "test") {
    Write-Host " Running tests ..."
    $env:GODEBUG = "cgocheck=0"
    $TestCommand = "go test $($Erigon.BuildFlags) ./... -p 2 --timeout 30s"
    Invoke-Expression -Command $TestCommand | Out-Host
    if (!($?)) {
        Write-Host " ERROR : Tests failed"
        exit 1
    } else {
        Write-Host "`n Tests completed"
    }

} elseif ($BuildTarget -eq "test-integration") {
    Write-Host " Running integration tests ..."
    $env:GODEBUG = "cgocheck=0"
    $TestCommand = "go test $($Erigon.BuildFlags) ./... -p 2 --timeout 30m -tags $($Erigon.BuildTags),integration"
    Invoke-Expression -Command $TestCommand | Out-Host
    if (!($?)) {
        Write-Host " ERROR : Tests failed"
        exit 1
    } else {
        Write-Host "`n Tests completed"
    }

} else {
    if (!($Erigon.Submodules)) {
        Write-Host " Updating git submodules ..."
        Invoke-Expression -Command "git.exe submodule update --init --recursive --force" | Out-Host
        if (!($?)) {
            Write-Host " ERROR : Update submodules failed"
            exit 1
        }
        $Erigon.Submodules = $true
    }

    Write-Host "`n Building $BuildTarget"
    $outExecutable = [string](Join-Path $Erigon.BinPath "$BuildTarget.exe")
    $BuildCommand = "go build $($Erigon.BuildFlags) -o ""$($outExecutable)"" ./cmd/$BuildTarget"
    Invoke-Expression -Command $BuildCommand | Out-Host
    if (!($?)) {
        Write-Host " ERROR : Could not build $BuildTarget"
        exit 1
    } else {
        Write-Host "`n Built $($BuildTarget). Run $($outExecutable) to launch"
    }
}
}

# Return to source folder
Set-Location $MyContext.Directory
