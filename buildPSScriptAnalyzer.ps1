#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
Build PSScriptAnalyzer project (https://github.com/PowerShell/PSScriptAnalyzer) on a Windows 10 computer and PowerShell 5 (no Visual Studio or .Net Core).

Of course, without the build tools from Visual Studio or .Net Core, this means that the built module may not work on other computers, but it will work in your computer, and this build script will allow you to build your changes to PSScriptAnalyzer with tools that come with Windows 10.

The minimum requirements to build PSScriptAnalyzer for PowerShell 5 (as of 2016-12-17) are:
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



write-verbose 'Creating output directories.'

$RepoDir = (get-item $RepoDir).FullName
$outputDir = "$RepoDir\out"
$moduleDir = "$RepoDir\out\PSScriptAnalyzer"
$engineDir = "$RepoDir\out\tmp\engine"
$rulesDir = "$RepoDir\out\tmp\rules"
$nugetDir = "$RepoDir\out\tmp\nuget"
$testDir = "$RepoDir\out\tmp\test"
$helpDir = "$moduleDir\en-US"

$engineDll = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$engineRes = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.Strings.resources"
$rulesDll = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesRes = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.Strings.resources"
$nJsonDll = "$nugetDir\Newtonsoft.Json\lib\net45\Newtonsoft.Json.dll"

remove-item $testDir, $helpDir, $moduleDir, $engineDir, $rulesDir -recurse -force -erroraction silentlycontinue
new-item -itemtype directory $testDir, $helpDir, $moduleDir, $engineDir, $rulesDir, $nugetDir -force | out-null



write-verbose 'Find csc.exe' -verbose
if ($CscExePath -eq '') {
    $CscExePath = join-path ([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
}
write-verbose "csc.exe: $CscExePath" -verbose



if (-not $NoDownload) {
    write-verbose 'Find Newtonsoft.Json.dll' -verbose
    if (-not (test-path $nJsonDll)) {
        invoke-webRequest 'https://www.nuget.org/api/v2/package/Newtonsoft.Json/9.0.1' -outfile "$nugetDir\Newtonsoft.Json.zip" -verbose
        expand-archive "$nugetDir\Newtonsoft.Json.zip" -destinationpath "$nugetDir\Newtonsoft.Json" -force
        remove-item "$nugetDir\Newtonsoft.Json.zip"
    }
    write-verbose "Newtonsoft.Json.dll: $nJsonDll" -verbose
}



write-verbose 'Copy source files.' -verbose

copy-item $RepoDir\Engine\*.cs $engineDir
copy-item $RepoDir\Engine\*\*.cs $engineDir
copy-item $RepoDir\Rules\*.cs $rulesDir

copy-item $RepoDir\Engine\Strings.resx $engineDir
copy-item $RepoDir\Rules\Strings.resx $rulesDir



write-verbose 'Remove unused source files.' -verbose

"$engineDir\GetScriptAnalyzerLoggerCommand.cs", "$engineDir\Strings.Designer.cs", "$rulesDir\Strings.Designer.cs" |
    where-object {test-path $_} |
    foreach-object {remove-item $_}

if ($NoDownload) {
    write-warning "Excluding files that need Newtonsoft.Json.dll" -warningaction continue
    select-string $engineDir\*.cs, $rulesDir\*.cs -pattern 'using Newtonsoft\.Json\..+;' |
        select-object -expandproperty path |
        sort-object -unique |
        foreach-object {write-warning "Excluding $_"; remove-item $_;}
}



write-verbose 'Generate resource files.' -verbose

function ResGenStr {
    [cmdletbinding()]
    param([string]$Path, [string]$Destination)

    add-type -assemblyname system.design
    add-type -assemblyname system.windows.forms

    $classname = [System.IO.Path]::GetFileNameWithoutExtension($Destination).Split('.')[-1]
    $namespace = [System.IO.Path]::GetFileNameWithoutExtension($Destination) -replace "\.$classname`$", ''

    $reader = new-object System.Resources.ResXResourceReader (get-item $Path).fullname
    try {
        $resOut = (new-item -itemtype file -path $Destination).fullname
        $writer = new-object System.Resources.ResourceWriter $resOut
        try     {$reader.GetEnumerator() | foreach-object {$writer.AddResource($_.Key, $_.Value)}}
        finally {$writer.Close()}

        $csOut = [System.IO.StreamWriter]::new(($resOut -replace '\.resources$', '.cs'))
        try {
            $csProvider = [Microsoft.CSharp.CSharpCodeProvider]::new()
            $compileUnit = [System.Resources.Tools.StronglyTypedResourceBuilder]::Create($Path, $classname, $namespace, $csprovider, $true, [ref](new-variable dontcare -passthru))
            $csProvider.GenerateCodeFromCompileUnit($compileUnit, $csOut, [System.CodeDom.Compiler.CodeGeneratorOptions]::new())
        }
        finally {$csOut.Close()}
    }
    finally {$reader.Close()}
}

resGenStr "$engineDir\Strings.resx" $engineRes
resGenStr "$rulesDir\Strings.resx" $rulesRes



write-verbose 'Build script analyzer engine.' -verbose

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



write-verbose 'Build script analyzer rules.' -verbose

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
    $(if (-not $NoDownload) {"/r:`"$nJsonDll`""} else {""}) `
    /res:"$rulesRes" `
    /recurse:"$rulesDir\*.cs"



write-verbose 'Copy module files.' -verbose

copy-item $engineDll,$rulesDll $moduleDir
copy-item "$RepoDir\Engine\PSScriptAnalyzer.ps[dm]1" $moduleDir
copy-item "$RepoDir\Engine\ScriptAnalyzer.*.ps1xml" $moduleDir
copy-item "$RepoDir\Engine\Settings" -recurse $moduleDir

if (-not $NoDownload) {
    copy-item $nJsonDll $moduleDir
}



write-verbose 'Generate help files' -verbose

copy-item "$RepoDir\docs\about*.txt" $helpDir
if ((get-module platyps) -or (get-module platyps -list)) {
    platyps\New-ExternalHelp -path $RepoDir\docs\markdown -outputpath $helpDir -force | out-null
}
else {
    write-warning "TODO: build module help file with platyps" -warningaction continue
}



if (get-module pester -list) {
    write-verbose 'Create test script.' -verbose

@"
    #Run this test script with another powershell
    #so that you do not import the built module's dll to your powershell,
    #which will cause problems the next time you build the module.
    #
    #Some tests import the PSScriptAnalyzer module from `$env:PSModulePath.
    #We can either install PSScriptAnalyzer in `$env:PSModulePath, or
    #we can temporarily change `$env:PSModulePath.

    `$env:PSModulePath = "$outputDir;`$(`$env:PSModulePath)"
    import-module '$moduleDir'
    cd '$RepoDir\Tests\Engine'
    `$engineResults = pester\invoke-pester -passthru
    cd '$RepoDir\Tests\Rules'
    `$rulesResults = pester\invoke-pester -passthru

    write-verbose "Test Results (Engine) | Passed: `$(`$engineResults.PassedCount)``tFailed: `$(`$engineResults.FailedCount)``tSkipped: `$(`$engineResults.SkippedCount)" -verbose
    write-verbose "Test Results (Rules)  | Passed: `$(`$rulesResults.PassedCount)``tFailed: `$(`$rulesResults.FailedCount)``tSkipped: `$(`$rulesResults.SkippedCount)" -verbose
"@ | out-file "$testDir\testFile.ps1" -encoding utf8

    write-verbose "Run test script: $testDir\testFile.ps1" -verbose
    powershell.exe -noprofile -executionpolicy remotesigned -noninteractive -file "$testDir\testFile.ps1"
}
else {
    write-warning "TODO: test module with pester" -warningaction continue
}



get-item $moduleDir\*.psd1
