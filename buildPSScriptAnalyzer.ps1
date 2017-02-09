#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
Build PSScriptAnalyzer project (https://github.com/PowerShell/PSScriptAnalyzer) on a Windows 10 computer and PowerShell 5 (no Visual Studio or .Net Core).

Of course, without the build tools from Visual Studio or .Net Core, this means that the built module may not work on other computers, but it will work in your computer, and this build script will allow you to build your changes to PSScriptAnalyzer with tools that come with Windows 10.

The minimum requirements to build PSScriptAnalyzer for PowerShell 5 (as of 2017-02-09) are:
    csc.exe (Roslyn compiler)
    resgen.exe
    Microsoft.CSharp.dll
    mscorlib.dll
    System.dll
    System.Core.dll
    System.ComponentModel.Composition.dll
    System.Data.Entity.Design.dll
    System.Management.Automation.dll
    Newtonsoft.Json.dll
    platyPS PowerShell module (for generating help files from markdown)
    pester PowerShell module (for testing the module)

    Note:
    resgen.exe is replaced with a PowerShell function, which requires
    microsoft.csharp.dll, system.dll, system.design.dll and system.windows.forms.dll.

    Note:
    csc.exe might require download.
    Newtonsoft.Json.dll requires download.

.Example
.\buildPSScriptAnalyzer.ps1 -RepoDir $env:HOMEPATH\Desktop\PSScriptAnalyzer
If you have the PSScriptAnalyzer repo in your Desktop, then this example will build that repo.

The path to the module psd1 file will be the output of this script.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([System.IO.FileInfo])]
param(
    #Path to the repository directory.
    [Parameter(Mandatory, Position = 0)]
    [string]
    $RepoDir,

    #Compiler option.
    #Find more information at:
    #    /optimize (C# Compiler Options)
    #    https://msdn.microsoft.com/en-us/library/t0hfscdc.aspx
    [switch]
    $Optimize,

    #Compiler option.
    #Find more information at:
    #    /platform (C# Compiler Options)
    #    https://msdn.microsoft.com/en-us/library/zekwfyz4.aspx
    [ValidateSet('anycpu', 'anycpu32bitpreferred', 'arm', 'x86', 'x64', 'Itanium')]
    [string]
    $Platform = 'anycpu',

    #Compiler option.
    #Find more information at:
    #    /warn (C# Compiler Options)
    #    https://msdn.microsoft.com/en-us/library/13b90fz7.aspx
    [ValidateSet('0', '1', '2', '3', '4')]
    [string]
    $WarnLevel = '4',

    #Path to the .NET directory.
    #
    #Note:
    #If you do not specify a path, the script will use [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory(), which will have a value similar to "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\".
    $DotNetDir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory(),

    #Path to the csc.exe file (Roslyn C# compiler).
    #
    #Note:
    #If you do not specify a path, the script will try to find "csc.exe" in $env:Path.
    #If the script cannot find "csc.exe" in $env:Path, the script will try to download "csc.exe" from the nuget.org package "Microsoft.Net.Compilers".
    #If the script cannot find "csc.exe" from the nuget.org package "Microsoft.Net.Compilers", the script will try to use "csc.exe" from the path from -DotNetDir parameter.
    [string]
    $CscExePath = (get-command -name csc.exe -erroraction silentlycontinue).path,

    #Path to the Newtonsoft.Json.dll file.
    #
    #Note:
    #If you do not specify a path, the script will try to download "Newtonsoft.Json.dll" from the nuget.org package "Newtonsoft.Json".
    [string]
    $NewtonsoftJsonDllPath = ""
)



$ErrorActionPreference = 'Stop'

$RepoDir = (get-item $RepoDir).FullName -replace '[\\/]$', ''
$DotNetDir = (get-item $DotNetDir).FullName -replace '[\\/]$', ''
$outputDir = "$RepoDir\out"
$moduleDir = "$RepoDir\out\PSScriptAnalyzer"
$engineDir = "$RepoDir\out\tmp\engine"
$rulesDir = "$RepoDir\out\tmp\rules"
$nugetDir = "$RepoDir\out\tmp\nuget"
$testDir = "$RepoDir\out\tmp\test"

$engineDll = "$moduleDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$engineRes = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.Strings.resources"
$rulesDll = "$moduleDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesRes = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.Strings.resources"

$unusedSourceFiles = @(
    "$RepoDir\Engine\Commands\GetScriptAnalyzerLoggerCommand.cs"
)



write-verbose 'Create output directory structure.' -verbose

if ($PSCmdlet.ShouldProcess($outputDir, 'Create directory structure')) {
    $moduleDir, $engineDir, $rulesDir, $testDir |
        where-object {test-path $_} |
        foreach-object {remove-item $_ -recurse -force -confirm:$false}

    $moduleDir, $engineDir, $rulesDir, $testdir, $nugetDir |
        foreach-object {new-item -itemtype directory $_ -force -confirm:$false | out-null}
}



write-verbose 'Find external dependencies.' -verbose

function GetNugetResource {
    [cmdletbinding(SupportsShouldProcess)]
    param([string]$NugetDir, [string]$PackageName, [string]$PackageVersion, [string]$RelativePath)

    $NugetDir = $NugetDir -replace '[\\/]$', ''
    $packageUrl = "https://www.nuget.org/api/v2/package/$PackageName/$PackageVersion"
    $packageDir = join-path $NugetDir "$PackageName$(if ($PackageVersion) {".$PackageVersion"} else {''})"
    $packageZip = "$packageDir.zip"
    $resourcePath = join-path $packageDir $RelativePath

    if ((-not (test-path $resourcePath)) -and $PSCmdlet.ShouldProcess($packageUrl, 'Download nuget package')) {
        invoke-webrequest $packageUrl -outfile $packageZip -verbose
        if (test-path $packageZip) {
            expand-archive $packageZip -destinationpath $packageDir -force
            remove-item $packageZip -confirm:$false
        }
    }

    if (-not (test-path $resourcePath)) {
        throw "Could not find nuget resource: $resourcePath"
    }

    $resourcePath
}

if ([string]::IsNullOrWhiteSpace($NewtonsoftJsonDllPath)) {
    if ($PSCmdlet.ShouldProcess('Newtonsoft.Json', 'Download nuget package.')) {
        $NewtonsoftJsonDllPath = GetNugetResource $nugetDir 'Newtonsoft.Json' '9.0.1' 'lib\net45\Newtonsoft.Json.dll' -confirm:$false
    }
    else {
        #If Newtonsoft.Json is explicitly not downloaded, do not throw here.
        #Let the compiler throw so that the error will say which file actually needs Newtonsoft.Json.dll.
        #They can then modify or remove that file if they wish.
        $NewtonsoftJsonDllPath = ""
    }
}

if ([string]::IsNullOrWhiteSpace($CscExePath)) {
    if ($PSCmdlet.ShouldProcess('Microsoft.Net.Compilers', 'Download nuget package')) {
        try {$CscExePath = GetNugetResource $nugetDir 'Microsoft.Net.Compilers' '1.3.2' 'tools\csc.exe' -confirm:$false}
        catch {$CscExePath = join-path $DotNetDir 'csc.exe'}
    }
    else {
        $CscExePath = join-path $DotNetDir 'csc.exe'
    }
}



write-verbose 'Renaming unused source files.' -verbose

foreach ($item in $unusedSourceFiles) {
    if ((test-path $item) -and $PSCmdlet.ShouldProcess($item, 'Add ".unused" extension')) {
        move-item $item "$item.unused" -confirm:$false -force
    }
}



write-verbose 'Generate resource files.' -verbose

function ResGenStr {
    [cmdletbinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Destination, [string]$Namespace, [string]$ClassName)

    add-type -assemblyname system.design
    add-type -assemblyname system.windows.forms

    $resxIn = [System.IO.Path]::GetFullPath($Path)
    $resourcesOut = [System.IO.Path]::GetFullPath($Destination)
    $csharpSrcOut = [System.IO.Path]::ChangeExtension($resxIn, 'Designer.cs')
    if (-not $PSBoundParameters.ContainsKey('ClassName')) {
        $ClassName = [System.IO.Path]::GetFileNameWithoutExtension($resourcesOut).Split('.')[-1]
    }
    if (-not $PSBoundParameters.ContainsKey('Namespace')) {
        $Namespace = [System.IO.Path]::GetFileNameWithoutExtension($resourcesOut) -replace "\.*$classname`$", ''
    }

    if ($PSCmdlet.ShouldProcess($resourcesOut, 'Create File')) {
        $reader = [System.Resources.ResXResourceReader]::new($resxIn)
        try {
            $writer = [System.Resources.ResourceWriter]::new($resourcesOut)
            try {$reader.GetEnumerator() | foreach-object {$writer.AddResource($_.Key, $_.Value)}}
            finally {$writer.Close()}
        }
        finally {$reader.Close()}
    }
    if ($PSCmdlet.ShouldProcess($csharpSrcOut, 'Create File')) {
        $csProvider = [Microsoft.CSharp.CSharpCodeProvider]::new()
        try {
            $resxErrors = $null
            $compileUnit = [System.Resources.Tools.StronglyTypedResourceBuilder]::Create($resxIn, $ClassName, $Namespace, $csprovider, $true, [ref]$resxErrors)
            $writer = [System.IO.StreamWriter]::new($csharpSrcOut)
            try {$csProvider.GenerateCodeFromCompileUnit($compileUnit, $writer, [System.CodeDom.Compiler.CodeGeneratorOptions]::new())}
            finally {$writer.Close()}
        }
        finally {$csProvider.Dispose()}
    }
}

if ($PSCmdlet.ShouldProcess("$engineRes and its .cs file", 'Create resource files')) {
    ResGenStr "$RepoDir\Engine\Strings.resx" $engineRes -confirm:$false
}

if ($PSCmdlet.ShouldProcess("$rulesRes and its .cs file", 'Create resource files')) {
    ResGenStr "$RepoDir\Rules\Strings.resx" $rulesRes -confirm:$false
}



write-verbose 'Build script analyzer engine.' -verbose

if ($PSCmdlet.ShouldProcess($engineDll, 'Create File')) {
    write-verbose "csc.exe: $CscExePath" -verbose
    & $CscExePath `
        /nologo /nostdlib /noconfig `
        /out:"$engineDll" `
        /target:library `
        /platform:$Platform `
        /warn:$WarnLevel `
        /optimize"$(if ($Optimize) {'+'} else {'-'})" `
        /r:"$DotNetDir\Microsoft.CSharp.dll" `
        /r:"$DotNetDir\mscorlib.dll" `
        /r:"$DotNetDir\System.dll" `
        /r:"$DotNetDir\System.Core.dll" `
        /r:"$DotNetDir\System.ComponentModel.Composition.dll" `
        /r:"$([powershell].assembly.location)" `
        /res:"$engineRes" `
        /recurse:"$RepoDir\Engine\*.cs"

    if (-not (test-path $engineDll)) {
        throw "Could not create file: $engineDll"
    }
}



write-verbose 'Build script analyzer rules.' -verbose

if ($PSCmdlet.ShouldProcess($rulesDll, 'Create File')) {
    write-verbose "csc.exe: $CscExePath" -verbose
    & $CscExePath `
        /nologo /nostdlib /noconfig `
        /out:"$rulesDll" `
        /target:library `
        /platform:$Platform `
        /warn:$WarnLevel `
        /optimize"$(if ($Optimize) {'+'} else {'-'})" `
        /r:"$DotNetDir\Microsoft.CSharp.dll" `
        /r:"$DotNetDir\mscorlib.dll" `
        /r:"$DotNetDir\System.dll" `
        /r:"$DotNetDir\System.Core.dll" `
        /r:"$DotNetDir\System.ComponentModel.Composition.dll" `
        /r:"$DotNetDir\System.Data.Entity.Design.dll" `
        /r:"$([powershell].assembly.location)" `
        /r:"$engineDll" `
        $(if ($NewtonsoftJsonDllPath) {"/r:`"$NewtonsoftJsonDllPath`""}) `
        /res:"$rulesRes" `
        /recurse:"$RepoDir\Rules\*.cs"

    if (-not (test-path $rulesDll)) {
        throw "Could not create file: $rulesDll"
    }
}



write-verbose 'Create PSScriptAnalyzer Module.' -verbose

if (-not [string]::IsNullOrWhiteSpace($NewtonsoftJsonDllPath) -and $PSCmdlet.ShouldProcess($NewtonsoftJsonDllPath, 'Copy dll')) {
    copy-item $NewtonsoftJsonDllPath $moduleDir -confirm:$false
}

if ($PSCmdlet.ShouldProcess("$RepoDir\Engine", 'Copy psd1, psm1, ps1xml, and settings files')) {
    copy-item "$RepoDir\Engine\PSScriptAnalyzer.ps[dm]1" $moduleDir -confirm:$false
    copy-item "$RepoDir\Engine\ScriptAnalyzer.*.ps1xml" $moduleDir -confirm:$false
    copy-item "$RepoDir\Engine\Settings" -recurse $moduleDir -confirm:$false
}



write-verbose 'Generate PSScriptAnalyzer Module help files.' -verbose

$helpDir = "$moduleDir\en-US"
if ($PSCmdlet.ShouldProcess($helpDir, 'Create PSScriptAnalyzer Module Help Directory')) {
    new-item -itemtype directory $helpDir -confirm:$false | out-null
    copy-item "$RepoDir\docs\about*.txt" $helpDir -confirm:$false
    if ((get-module platyps) -or (get-module platyps -list)) {
        platyps\New-ExternalHelp -path $RepoDir\docs\markdown -outputpath $helpDir -force | out-null
    }
    else {
        write-warning "TODO: build module help file with platyps" -warningaction continue
    }
}



write-verbose 'Run tests.' -verbose

$testFile = "$testDir\testRunner.ps1"
if ($PSCmdlet.ShouldProcess($testFile, 'Create script that runs tests')) {
    @"
    #Run this test script with another powershell
    #so that you do not import the built module's dll to your powershell,
    #which will cause problems the next time you build the module.
    #
    #Some tests import the PSScriptAnalyzer module from `$env:PSModulePath.
    #We can either install PSScriptAnalyzer in `$env:PSModulePath, or
    #we can temporarily change `$env:PSModulePath.

    import-module '$moduleDir'
    `$env:PSModulePath = "$outputDir;`$(`$env:PSModulePath)"

    set-location '$RepoDir\Tests\Engine'
    `$engineResults = pester\invoke-pester -passthru

    set-location '$RepoDir\Tests\Rules'
    `$rulesResults = pester\invoke-pester -passthru

    write-verbose "Test Results (Engine) | Passed: `$(`$engineResults.PassedCount), Failed: `$(`$engineResults.FailedCount), Skipped: `$(`$engineResults.SkippedCount)" -verbose
    write-verbose "Test Results (Rules)  | Passed: `$(`$rulesResults.PassedCount), Failed: `$(`$rulesResults.FailedCount), Skipped: `$(`$rulesResults.SkippedCount)" -verbose
"@ |
        out-file $testFile -encoding utf8 -force -confirm:$false
}

if ($PSCmdlet.ShouldProcess($testFile, 'Run script that runs tests')) {
    if (get-module pester -list) {
        powershell.exe -noprofile -executionpolicy remotesigned -noninteractive -file "$testFile"
    }
    else {
        write-warning "TODO: test module with pester" -warningaction continue
    }
}



if ((-not $WhatIfPreference) -and (test-path "$moduleDir\*.psd1")) {
    get-item "$moduleDir\*.psd1"
}
