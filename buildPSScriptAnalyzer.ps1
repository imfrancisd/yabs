#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
Build PSScriptAnalyzer project (https://github.com/PowerShell/PSScriptAnalyzer) on a Windows 10 computer and PowerShell 5 (no Visual Studio or .Net Core).

Of course, without the build tools from Visual Studio or .Net Core, this means that the built module may not work on other computers, but it will work in your computer, and this build script will allow you to build your changes to PSScriptAnalyzer with tools that come with Windows 10.

The minimum requirements to build PSScriptAnalyzer for PowerShell 5 (as of 2016-12-16) are:
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

    Note:
    The functionality needed by resgen.exe is replaced with a PowerShell function.

    Note:
    Newtonsoft.Json.dll requires download, but only one PSScriptAnalyzer rule needs it:
    UseCompatibleCmdlets rule.

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

$helpDir = "$moduleDir\en-US"

$engineDll = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$engineRes = "$engineDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.Strings.resources"
$rulesDll = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesRes = "$rulesDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.Strings.resources"
$nJsonDll = "$nugetDir\Newtonsoft.Json\lib\net45\Newtonsoft.Json.dll"

rmdir $helpDir, $moduleDir, $engineDir, $rulesDir -recurse -force -erroraction silentlycontinue
mkdir $helpDir, $moduleDir, $engineDir, $rulesDir, $nugetDir -force | out-null



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
        del "$nugetDir\Newtonsoft.Json.zip"
    }
    write-verbose "Newtonsoft.Json.dll: $nJsonDll" -verbose
}



write-verbose 'Copy source files.' -verbose

copy $RepoDir\Engine\*.cs $engineDir
copy $RepoDir\Engine\*\*.cs $engineDir
copy $RepoDir\Rules\*.cs $rulesDir

copy $RepoDir\Engine\Strings.resx $engineDir
copy $RepoDir\Rules\Strings.resx $rulesDir



write-verbose 'Remove unused source files.' -verbose

"$engineDir\GetScriptAnalyzerLoggerCommand.cs", "$engineDir\Strings.Designer.cs", "$rulesDir\Strings.Designer.cs" |
    where {test-path $_} |
    foreach {del $_}

if ($NoDownload) {
    write-warning "Excluding files that need Newtonsoft.Json.dll" -warningaction continue
    select-string $engineDir\*.cs, $rulesDir\*.cs -pattern 'using Newtonsoft\.Json\..+;' |
        select-object -expandproperty path |
        sort -unique |
        foreach {write-warning "Excluding $_"; del $_;}
}



write-verbose 'Generate resource files.' -verbose

function ResGenStr([string]$Path, [string]$Destination)
{
    #System.Resources.ResXResourceReader is in System.Windows.Forms.dll
    add-type -assemblyname system.windows.forms

    write-verbose "Convert $Path to $Destination" -verbose
    $reader = new-object System.Resources.ResXResourceReader (get-item $Path).fullname
    try {
        $resOut = (new-item -itemtype file -path $Destination).fullname
        $writer = new-object System.Resources.ResourceWriter $resOut
        try     {$reader.GetEnumerator() | foreach {$writer.AddResource($_.Key, $_.Value)}}
        finally {$writer.Close()}
    }
    finally {$reader.Close()}
}

pushd "$RepoDir"
try {
    .\New-StronglyTypedCsFileForResx.ps1 -project engine
    .\New-StronglyTypedCsFileForResx.ps1 -project rules

    move .\Engine\Strings.cs $engineDir -force
    move .\Rules\Strings.cs $rulesDir -force
}
finally {popd}

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

copy $engineDll,$rulesDll $moduleDir
copy "$RepoDir\Engine\PSScriptAnalyzer.ps[dm]1" $moduleDir
copy "$RepoDir\Engine\ScriptAnalyzer.*.ps1xml" $moduleDir
copy "$RepoDir\Engine\Settings" -recurse $moduleDir

if (-not $NoDownload) {
    copy $nJsonDll $moduleDir
}



write-verbose 'Generate help files' -verbose

copy "$RepoDir\docs\about*.txt" $helpDir
write-warning "TODO: build module help file with platyps" -warningaction continue



get-item $moduleDir\*.psd1
