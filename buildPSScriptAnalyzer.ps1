#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
Build PSScriptAnalyzer project (https://github.com/PowerShell/PSScriptAnalyzer) on a Windows 10 computer and PowerShell 5 (no Visual Studio or .Net Core).

Of course, without the build tools from Visual Studio or .Net Core, this means that the built module may not work on other computers, but it will work in your computer, and this build script will allow you to build your changes to PSScriptAnalyzer with tools that come with Windows 10.

The minimum requirements to build PSScriptAnalyzer for PowerShell 5 (as of 2016-12-31) are:
    csc.exe
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
    Newtonsoft.Json.dll requires download.

    Use the -NoDownload switch if you do not want to download Newtonsoft.Json.dll.

.Example
.\buildPSScriptAnalyzer.ps1 -RepoDir $env:HOMEPATH\Desktop\PSScriptAnalyzer
If you have the PSScriptAnalyzer repo in your Desktop, then this example will build that repo.

The path to the module psd1 file will be the output of this script.
.Example
.\buildPSScriptAnalyzer.ps1 -RepoDir $env:HOMEPATH\Desktop\PSScriptAnalyzer -NoDownload
Same as the previous example, except that Newtonsoft.Json.dll will not be downloaded from nuget.org.

Without this dll, some rules may be excluded from the build.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([System.IO.FileInfo])]
param(
    #Path to the repository directory.
    [Parameter(Mandatory, Position=0)]
    [string]
    $RepoDir,

    #Do not download anything.
    #PSScriptAnalyzer rules that requires Newtonsoft.Json.dll will not be built.
    [switch]
    $NoDownload,

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
    $WarnLevel = '3',

    #Path to the csc.exe file (C# compiler).
    #
    #Note:
    #If you do not specify a path here, the script will try to find it in $env:Path, and if the script cannot find it in $env:Path, it will use the csc.exe in [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory(), which is typically 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' or something similar.
    [string]
    $CscExePath = (get-command -name csc.exe -erroraction silentlycontinue).path
)



$ErrorActionPreference = 'Stop'

$RepoDir = (get-item $RepoDir).FullName
$outputDir = "$RepoDir\out"
$moduleDir = "$RepoDir\out\PSScriptAnalyzer"
$engineDir = "$RepoDir\out\tmp\engine"
$rulesDir = "$RepoDir\out\tmp\rules"
$nugetDir = "$RepoDir\out\tmp\nuget"
$testDir = "$RepoDir\out\tmp\test"

$engineDll = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$engineRes = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.Strings.resources"
$rulesDll = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesRes = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.Strings.resources"
$nJsonDll = "$nugetDir\Newtonsoft.Json\lib\net45\Newtonsoft.Json.dll"



write-verbose 'Create output directory structure.' -verbose

if ($PSCmdlet.ShouldProcess($outputDir, 'Create directory structure')) {
    $moduleDir, $engineDir, $rulesDir, $testDir |
        where-object {test-path $_} |
        foreach-object {remove-item $_ -recurse -force -confirm:$false}

    $moduleDir, $engineDir, $rulesDir, $testdir, $nugetDir |
        foreach-object {new-item -itemtype directory $_ -force -confirm:$false | out-null}
}



write-verbose 'Find external dependencies.' -verbose

#May need to download Roslyn (Microsoft.Net.Compilers) from nuget.org if project uses new CSharp language features.
if (($CscExePath -eq '') -or (-not (test-path $CscExePath))) {
    $CscExePath = join-path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
}

if ((-not $NoDownload) -and (-not (test-path $nJsonDll)) -and $PSCmdlet.ShouldProcess('https://www.nuget.org/api/v2/package/Newtonsoft.Json/9.0.1', 'Download nuget package')) {
    invoke-webRequest 'https://www.nuget.org/api/v2/package/Newtonsoft.Json/9.0.1' -outfile "$nugetDir\Newtonsoft.Json.zip" -verbose
    if (test-path "$nugetDir\Newtonsoft.Json.zip") {
        expand-archive "$nugetDir\Newtonsoft.Json.zip" -destinationpath "$nugetDir\Newtonsoft.Json" -force
        remove-item "$nugetDir\Newtonsoft.Json.zip" -confirm:$false
    }
}



write-verbose 'Copy source files.' -verbose

if ($PSCmdlet.ShouldProcess("$RepoDir\Engine", 'Copy source files')) {
    get-childitem "$RepoDir\Engine" -recurse |
        where-object {$_.extension -match '^\.(cs|resx)$'} |
        where-object {$_.name -ne 'GetScriptAnalyzerLoggerCommand.cs'} |
        where-object {$_.name -ne 'Strings.Designer.cs'} |
        foreach-object {copy-item $_.fullname $engineDir -confirm:$false}
}

if ($PSCmdlet.ShouldProcess("$RepoDir\Rules", 'Copy source files')) {
    get-childitem "$RepoDir\Rules" -recurse |
        where-object {$_.extension -match '^\.(cs|resx)$'} |
        where-object {$_.name -ne 'Strings.Designer.cs'} |
        foreach-object {copy-item $_.fullname $rulesDir -confirm:$false}
}



write-verbose 'Generate resource files.' -verbose

function ResGenStr {
    [cmdletbinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Destination)

    add-type -assemblyname system.design
    add-type -assemblyname system.windows.forms

    $resxIn = [System.IO.Path]::GetFullPath($Path)
    $resourcesOut = [System.IO.Path]::GetFullPath($Destination)
    $csharpSrcOut = [System.IO.Path]::ChangeExtension($resourcesOut, 'cs')
    $classname = [System.IO.Path]::GetFileNameWithoutExtension($Destination).Split('.')[-1]
    $namespace = [System.IO.Path]::GetFileNameWithoutExtension($Destination) -replace "\.*$classname`$", ''

    if ($PSCmdlet.ShouldProcess($resourcesOut, 'Create File')) {
        $reader = [System.Resources.ResXResourceReader]::new($resxIn)
        try {
            $writer = [System.Resources.ResourceWriter]::new($resourcesOut)
            try     {$reader.GetEnumerator() | foreach-object {$writer.AddResource($_.Key, $_.Value)}}
            finally {$writer.Close()}
        }
        finally {$reader.Close()}
    }

    if ($PSCmdlet.ShouldProcess($csharpSrcOut, 'Create File')) {
        $csProvider = [Microsoft.CSharp.CSharpCodeProvider]::new()
        try {
            $resxErrors = $null
            $compileUnit = [System.Resources.Tools.StronglyTypedResourceBuilder]::Create($resxIn, $classname, $namespace, $csprovider, $true, [ref]$resxErrors)
            $writer = [System.IO.StreamWriter]::new($csharpSrcOut)
            try     {$csProvider.GenerateCodeFromCompileUnit($compileUnit, $writer, [System.CodeDom.Compiler.CodeGeneratorOptions]::new())}
            finally {$writer.Close()}
        }
        finally {$csProvider.Dispose()}
    }
}

if ($PSCmdlet.ShouldProcess("$engineRes and its .cs file", 'Create resource files')) {
    ResGenStr "$engineDir\Strings.resx" $engineRes -confirm:$false
}

if ($PSCmdlet.ShouldProcess("$rulesRes and its .cs file", 'Create resource files')) {
   ResGenStr "$rulesDir\Strings.resx" $rulesRes -confirm:$false
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
        /r:Microsoft.CSharp.dll `
        /r:mscorlib.dll `
        /r:System.dll `
        /r:System.Core.dll `
        /r:System.ComponentModel.Composition.dll `
        /r:"$([powershell].assembly.location)" `
        /res:"$engineRes" `
        /recurse:"$engineDir\*.cs"
}



write-verbose 'Build script analyzer rules.' -verbose

if ($PSCmdlet.ShouldProcess($rulesDll, 'Create File')) {
    $jsonMissing = -not (test-path $nJsonDll)
    if ($jsonMissing) {
        write-warning "Excluding files that need Newtonsoft.Json.dll" -warningaction continue
        select-string $rulesDir\*.cs -pattern 'using Newtonsoft\.Json\..+;' |
            select-object -expandproperty path |
            sort-object -unique |
            foreach-object {write-warning "Excluding $_"; remove-item $_ -confirm:$false;}
    }

    write-verbose "csc.exe: $CscExePath" -verbose
    & $CscExePath `
        /nologo /nostdlib /noconfig `
        /out:"$rulesDll" `
        /target:library `
        /platform:$Platform `
        /warn:$WarnLevel `
        /optimize"$(if ($Optimize) {'+'} else {'-'})" `
        /r:Microsoft.CSharp.dll `
        /r:mscorlib.dll `
        /r:System.dll `
        /r:System.Core.dll `
        /r:System.ComponentModel.Composition.dll `
        /r:System.Data.Entity.Design.dll `
        /r:"$([powershell].assembly.location)" `
        /r:"$engineDll" `
        $(if ($jsonMissing) {""} else {"/r:`"$nJsonDll`""}) `
        /res:"$rulesRes" `
        /recurse:"$rulesDir\*.cs"
}



write-verbose 'Create PSScriptAnalyzer Module.' -verbose

if ($PSCmdlet.ShouldProcess($engineDll, 'Copy dll')) {
    copy-item $engineDll $moduleDir -confirm:$false
}

if ($PSCmdlet.ShouldProcess($rulesDll, 'Copy dll')) {
    copy-item $rulesDll $moduleDir -confirm:$false
}

if ((test-path $nJsonDll) -and $PSCmdlet.ShouldProcess($nJsonDll, 'Copy dll')) {
    copy-item $nJsonDll $moduleDir -confirm:$false
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

    write-verbose "Test Results (Engine) | Passed: `$(`$engineResults.PassedCount) Failed: `$(`$engineResults.FailedCount) Skipped: `$(`$engineResults.SkippedCount)" -verbose
    write-verbose "Test Results (Rules)  | Passed: `$(`$rulesResults.PassedCount) Failed: `$(`$rulesResults.FailedCount) Skipped: `$(`$rulesResults.SkippedCount)" -verbose
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
