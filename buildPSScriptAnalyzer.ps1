#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
==================
Updated 2019-04-16
==================

Build PSScriptAnalyzer project (https://github.com/PowerShell/PSScriptAnalyzer) on a Windows 10 computer and PowerShell 5 (no Visual Studio or .Net Core).

Of course, without the build tools from Visual Studio or .Net Core, this means that the built module may not work on other computers, but it will work in your computer, and this build script will allow you to build your changes to PSScriptAnalyzer with tools that come with Windows 10.

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

    #Path to the csc.exe C# compiler.
    [string]
    $CscExe,

    #Path to the .NET 4.0 reference assemblies directory.
    [string]
    $DotNet4Dir,

    #Path to the .NET 4.5 reference assemblies directory.
    [string]
    $DotNet45Dir,

    #Compiler option.
    #Find more information at:
    #-optimize (C# Compiler Options)
    #https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/optimize-compiler-option
    [switch]
    $Optimize,

    #Compiler option.
    #Find more information at:
    #-platform (C# Compiler Options)
    #https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/platform-compiler-option
    [ValidateSet('anycpu', 'anycpu32bitpreferred', 'arm', 'x86', 'x64', 'Itanium')]
    [string]
    $Platform = 'anycpu',

    #PowerShell versions to target the build.
    [ValidateSet('3', '4', '5', 'Core')]
    [string[]]
    $PSVersion = $(if (($null -ne $PSVersionTable.PSEdition) -and ('Desktop' -ne $PSVersionTable.PSEdition)) {'Core'} else {'5'}),

    #Compiler option.
    #Find more information at:
    #-warn (C# Compiler Options)
    #https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/compiler-options/warn-compiler-option
    [ValidateSet('0', '1', '2', '3', '4')]
    [string]
    $WarnLevel = '4'
)



$ErrorActionPreference = 'Stop'
$isPSCoreProcess = ($null -ne $PSVersionTable.PSEdition) -and ('Desktop' -ne $PSVersionTable.PSEdition)

$RepoDir = (Get-Item $RepoDir).FullName -replace '[\\/]$', ''
$outputDir = [System.IO.Path]::Combine("$RepoDir", "out")
$moduleBaseDir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer")
$modulePSv5Dir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer")
$modulePSv4Dir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer", "PSv4")
$modulePSv3Dir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer", "PSv3")
$moduleCoreDir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer", "coreclr")
$helpDir = [System.IO.Path]::Combine("$RepoDir", "out", "PSScriptAnalyzer", "en-US")
$testDir = [System.IO.Path]::Combine("$RepoDir", "tmp", "test")
$testRunner = [System.IO.Path]::Combine("$testDir", "testRunner.ps1")
$testResult = [System.IO.Path]::Combine("$testDir", "testResult.xml")
$nugetDir = [System.IO.Path]::Combine("$RepoDir", "tmp", ".nuget")

$enginePSv5Dll = [System.IO.Path]::Combine("$modulePSv5Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.dll")
$enginePSv4Dll = [System.IO.Path]::Combine("$modulePSv4Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.dll")
$enginePSv3Dll = [System.IO.Path]::Combine("$modulePSv3Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.dll")
$engineCoreDll = [System.IO.Path]::Combine("$moduleCoreDir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.dll")
$compatPSv5Dll = [System.IO.Path]::Combine("$modulePSv5Dir", "Microsoft.PowerShell.CrossCompatibility.dll")
$compatPSv4Dll = [System.IO.Path]::Combine("$modulePSv4Dir", "Microsoft.PowerShell.CrossCompatibility.dll")
$compatPSv3Dll = [System.IO.Path]::Combine("$modulePSv3Dir", "Microsoft.PowerShell.CrossCompatibility.dll")
$compatCoreDll = [System.IO.Path]::Combine("$moduleCoreDir", "Microsoft.PowerShell.CrossCompatibility.dll")
$rulesPSv5Dll = [System.IO.Path]::Combine("$modulePSv5Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll")
$rulesPSv4Dll = [System.IO.Path]::Combine("$modulePSv4Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll")
$rulesPSv3Dll = [System.IO.Path]::Combine("$modulePSv3Dir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll")
$rulesCoreDll = [System.IO.Path]::Combine("$moduleCoreDir", "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll")



function GetNugetResource {
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $PackageName,
        
        [parameter(Mandatory = $true, Position = 1)]
        [System.String]
        $PackageVersion,
        
        [parameter(Mandatory = $true, Position = 2)]
        [System.String]
        $RelativePath,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $NugetDir,
        
        [parameter(Mandatory = $false)]
        [System.String]
        $NugetUrl = 'https://www.nuget.org/api/v2'
    )

    $NugetDir = $NugetDir -replace '[\\/]$', ''
    $NugetUrl = $NugetUrl -replace '[/]$', ''

    $packageUrl = "$NugetUrl/package/$PackageName/$PackageVersion"
    $packageDir = [System.IO.Path]::Combine($NugetDir, 'packages', $PackageName, $PackageVersion)
    $packageZip = [System.IO.Path]::Combine($NugetDir, 'packages', $PackageName, "$PackageVersion.zip")
    $resourcePath = [System.IO.Path]::Combine($packageDir, $RelativePath)

    if ((-not (Test-Path $resourcePath)) -and $PSCmdlet.ShouldProcess($packageUrl, 'Download nuget package')) {
        New-Item $packageDir -ItemType Directory -Force -Confirm:$false | Out-Null
        Invoke-WebRequest $packageUrl -OutFile $packageZip -Verbose
        if (Test-Path $packageZip) {
            Expand-Archive $packageZip -DestinationPath $packageDir -Force
            Remove-Item $packageZip -Confirm:$false
        }
    }

    if ((-not $WhatIfPreference) -and (-not (Test-Path $resourcePath))) {
        throw "Could not find nuget resource: $resourcePath"
    }

    $resourcePath
}

function ConvertResxStringsToCsharp {
    [cmdletbinding(SupportsShouldProcess)]
    param(
        #String ('strings.resx') or
        #Hashtable (@{''='default.resx'; 'en'='enDefault.resx; 'en-us'='baseball.resx'; 'en-ca'='hockey.resx';})
        [parameter(Mandatory, Position = 0)]
        [object]
        $Path,

        #String ('strings.designer.cs')
        [parameter(Mandatory, Position = 1)]
        [string]
        $Destination,

        [parameter(Mandatory, Position = 2)]
        [string]
        $Namespace,

        [parameter(Mandatory, Position = 3)]
        [string]
        $ClassName,

        #The public API of the generated code will not return null, but will return string.Empty if necessary.
        [switch]
        $NoNullStrings
    )

    if ($PSCmdlet.ShouldProcess($Destination, 'Create File')) {
        if (($Path -is [System.String]) -or ($Path -is [System.IO.FileInfo])) {
            $Path = @{'' = $Path}
        }
        elseif ($Path -isnot [System.Collections.IDictionary]) {
            throw "Path must be a file path or a hashtable."
        }

        New-Item (Split-Path $Destination -Parent) -ItemType Directory -Force | Out-Null

        &{
            "using System;"
            "using System.Collections.Generic;"
            "using System.Globalization;"
            "using System.Linq;"
            ""
            "namespace $Namespace"
            "{"
            "    internal static class $ClassName"
            "    {"
            "        private static CultureInfo s_preferredCulture;"
            "        private static Lazy<string[]>[] s_preferredCultureData;"
            "        private static readonly Dictionary<CultureInfo, Lazy<string[]>> s_localizedResources;"
            ""
            "        private static string GetString(int stringIndex)"
            "        {"
            "            var culturePreferredData = s_preferredCultureData;"
            "            var culturePreferredDataLength = culturePreferredData.Length;"
            ""
            "            for (var i = 0; i < culturePreferredDataLength; i++)"
            "            {"
            "                var stringData = culturePreferredData[i].Value[stringIndex];"
            "                if (stringData != null)"
            "                {"
            "                    return stringData;"
            "                }"
            "            }"
            ""
            "            return $(if ($NoNullStrings) {'string.Empty'} else {'null'});"
            "        }"
            ""
            "        internal static CultureInfo Culture"
            "        {"
            "            get"
            "            {"
            "                return s_preferredCulture;"
            "            }"
            "            set"
            "            {"
            "                var culturePreferred = value ?? CultureInfo.InvariantCulture;"
            "                var culturePreferredData = new List<Lazy<string[]>>();"
            ""
            "                for (var culture = culturePreferred; ; culture = culture.Parent)"
            "                {"
            "                    if (s_localizedResources.ContainsKey(culture))"
            "                    {"
            "                        culturePreferredData.Add(s_localizedResources[culture]);"
            "                    }"
            "                    if (culture == CultureInfo.InvariantCulture)"
            "                    {"
            "                        break;"
            "                    }"
            "                }"
            ""
            "                s_preferredCultureData = culturePreferredData.ToArray();"
            "                s_preferredCulture = culturePreferred;"
            "            }"
            "        }"
            ""

            $resourceContents = [System.Collections.Generic.Dictionary[System.Globalization.CultureInfo, System.Collections.Hashtable]]::new()
            $resourceDataNames = [System.Collections.Generic.SortedSet[System.String]]::new()

            foreach ($entry in $Path.GetEnumerator()) {
                $culture = [System.Globalization.CultureInfo]::new("$($entry.Key)")
                $xmlData = [xml](Get-Content $entry.Value)
                $resourceContents.Add($culture, @{})

                foreach ($item in $xmlData.GetElementsByTagName('data').GetEnumerator()) {
                    $resourceContents[$culture][$item.name] = $item.value.Replace("\", "\\").Replace('"', '\"').Replace("`r", "\r").Replace("`n", "\n").Replace("`t", "\t")
                    [System.Void]$resourceDataNames.Add($item.name)
                }
            }

            for ($i, $e = 0, $resourceDataNames.GetEnumerator(); $e.MoveNext(); $i++) {
                "        internal static string $($e.Current)"
                "        {"
                "            get { return GetString($i); }"
                "        }"
                ""
            }

            "        static $($ClassName)()"
            "        {"
            "            s_localizedResources = new Dictionary<CultureInfo, Lazy<string[]>>() {"

            foreach ($cultureData in @($resourceContents.GetEnumerator() | Sort-Object {$_.Key})) {
                $culture = $cultureData.Key
                $data = $cultureData.Value
                "                {new CultureInfo(`"$($culture)`"), new Lazy<string[]>(() => new string[] {"
                foreach ($dataName in $resourceDataNames) {
                    if ($resourceContents[$culture].ContainsKey($dataName)) {
                        "                    `"$($resourceContents[$culture][$dataName])`","
                    }
                    else {
                        "                    null,"
                    }
                }
                "                })},"
            }

            "            };"
            ""
            "            if (!s_localizedResources.ContainsKey(CultureInfo.InvariantCulture) && (s_localizedResources.Count > 0))"
            "            {"
            "                s_localizedResources.Add(CultureInfo.InvariantCulture, s_localizedResources.OrderBy(entry => entry.Key.Name.Length).ThenBy(entry => entry.Key.Name).First().Value);"
            "            }"
            ""
            "            Culture = CultureInfo.CurrentUICulture;"
            "        }"
            "    }"
            "}"
        } | Out-File $Destination -Encoding utf8 -Force
    }

    if ((-not $WhatIfPreference) -and (-not (Test-Path $Destination))) {
        throw "Could not create file: $Destination"
    }

    $Destination
}



Write-Verbose 'Create output directory structure.' -Verbose

if ($PSCmdlet.ShouldProcess($outputDir, 'Create directory structure')) {
    $moduleBaseDir, $modulePSv5Dir, $modulePSv4Dir, $modulePSv3Dir, $moduleCoreDir, $helpDir, $testDir |
        Where-Object {Test-Path $_} |
        ForEach-Object {Remove-Item $_ -Recurse -Force -Confirm:$false}

    $moduleBaseDir, $modulePSv5Dir, $modulePSv4Dir, $modulePSv3Dir, $moduleCoreDir, $helpDir, $testdir, $nugetDir |
        ForEach-Object {New-Item -ItemType Directory $_ -Force -Confirm:$false | Out-Null}

    Copy-Item "$RepoDir/Engine/PSScriptAnalyzer.ps[dm]1" $moduleBaseDir -Confirm:$false
    Copy-Item "$RepoDir/Engine/ScriptAnalyzer.*.ps1xml" $moduleBaseDir -Confirm:$false
    Copy-Item "$RepoDir/Engine/Settings" -Recurse $moduleBaseDir -Confirm:$false
    Copy-Item "$RepoDir/docs/about*.txt" $helpDir -Confirm:$false
    Copy-Item "$RepoDir/PSCompatibilityAnalyzer/profiles" -Recurse "$moduleBaseDir/compatibility_profiles" -Confirm:$false
}



Write-Verbose 'Get C# compiler.' -Verbose

if (-not [string]::IsNullOrWhiteSpace($CscExe) -and (Test-Path $CscExe)) {
    $compiler = $CscExe
}
elseif ($isPSCoreProcess) {
    throw "Must specify -CscExe with the file path to the C# compiler."
}
else {
    $compiler = GetNugetResource 'Microsoft.Net.Compilers.Toolset' '3.1.0-beta1-final' 'tasks/net472/csc.exe' -NugetDir $nugetDir
}

Write-Verbose "$compiler" -Verbose



Write-Verbose 'Generate string resources.' -Verbose

Write-Verbose "$(ConvertResxStringsToCsharp "$RepoDir/Engine/Strings.resx" "$RepoDir/Engine/gen/Strings.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer" "Strings")"
Write-Verbose "$(ConvertResxStringsToCsharp "$RepoDir/Rules/Strings.resx" "$RepoDir/Rules/gen/Strings.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules" "Strings")"



if ($PSVersion -contains '5') {

    Write-Verbose 'Build PSv5 script analyzer engine.' -Verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet45Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.5 reference assemblies."
        }
        else {
            Write-Warning '*** Using unknown .NET framework in place of .NET 4.5. Specify -DotNet45Dir. ***'
            $DotNet45Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet45Dir = (Get-Item $DotNet45Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$enginePSv5Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.5.1.ReferenceAssemblies' '1.0.0' 'lib/net461/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        Get-ChildItem "$RepoDir/Engine" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Engine/Commands/GetScriptAnalyzerLoggerCommand.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Engine/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($PSCmdlet.ShouldProcess($enginePSv5Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $enginePSv5Dll)) {
            throw "Could not create file: $enginePSv5Dll"
        }
    }

    Write-Verbose 'Build PSv5 script analyzer cross compatibility.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$compatPSv5Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.Runtime.Serialization.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.5.1.ReferenceAssemblies' '1.0.0' 'lib/net461/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-recurse:`"$RepoDir/PSCompatibilityAnalyzer/Microsoft.PowerShell.CrossCompatibility/*.cs`""
    }

    if ($PSCmdlet.ShouldProcess($compatPSv5Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $compatPSv5Dll)) {
            throw "Could not create file: $compatPSv5Dll"
        }
    }

    Write-Verbose 'Build PSv5 script analyzer rules.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$rulesPSv5Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$enginePSv5Dll`""
        "-r:`"$compatPSv5Dll`""
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$DotNet45Dir/System.Data.Entity.Design.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.5.1.ReferenceAssemblies' '1.0.0' 'lib/net461/Microsoft.Management.Infrastructure.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.5.1.ReferenceAssemblies' '1.0.0' 'lib/net461/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        Get-ChildItem "$RepoDir/Rules" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Rules/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($pscmdlet.ShouldProcess($rulesPSv5Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $rulesPSv5Dll)) {
            throw "Could not create file: $rulesPSv5Dll"
        }

        Copy-Item $(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir) $modulePSv5Dir -Confirm:$false
    }

}



if ($PSVersion -contains '4') {

    Write-Verbose 'Build PSv4 script analyzer engine.' -Verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet45Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.5 reference assemblies."
        }
        else {
            Write-Warning '*** Using unknown .NET framework in place of .NET 4.5. Specify -DotNet45Dir. ***'
            $DotNet45Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet45Dir = (Get-Item $DotNet45Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$enginePSv4Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""

        #For now, needs PSV3 defined to build.
        "-define:PSV3;PSV4"

        Get-ChildItem "$RepoDir/Engine" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Engine/Commands/GetScriptAnalyzerLoggerCommand.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Engine/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($PSCmdlet.ShouldProcess($enginePSv4Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $enginePSv4Dll)) {
            throw "Could not create file: $enginePSv4Dll"
        }
    }

    Write-Verbose 'Build PSv4 script analyzer cross compatibility.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$compatPSv4Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.Runtime.Serialization.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-recurse:`"$RepoDir/PSCompatibilityAnalyzer/Microsoft.PowerShell.CrossCompatibility/*.cs`""

        #For now, needs PSV3 defined to build.
        "-define:PSV3;PSV4"
    }

    if ($PSCmdlet.ShouldProcess($compatPSv4Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $compatPSv4Dll)) {
            throw "Could not create file: $compatPSv4Dll"
        }
    }

    Write-Verbose 'Build PSv4 script analyzer rules.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$rulesPSv4Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$enginePSv4Dll`""
        "-r:`"$compatPSv4Dll`""
        "-r:`"$DotNet45Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet45Dir/mscorlib.dll`""
        "-r:`"$DotNet45Dir/System.dll`""
        "-r:`"$DotNet45Dir/System.Core.dll`""
        "-r:`"$DotNet45Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$DotNet45Dir/System.Data.Entity.Design.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib/net4/Microsoft.Management.Infrastructure.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""

        #For now, needs PSV3 defined to build.
        "-define:PSV3;PSV4"

        Get-ChildItem "$RepoDir/Rules" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Rules/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($pscmdlet.ShouldProcess($rulesPSv4Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $rulesPSv4Dll)) {
            throw "Could not create file: $rulesPSv4Dll"
        }

        Copy-Item $(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir) $modulePSv4Dir -Confirm:$false
    }

}



if ($PSVersion -contains '3') {

    Write-Verbose 'Build PSv3 script analyzer engine.' -Verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet4Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.0 reference assemblies."
        }
        else {
            Write-Warning '*** Using unknown .NET framework in place of .NET 4.0. Specify -DotNet4Dir. ***'
            $DotNet4Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet4Dir = (Get-Item $DotNet4Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$enginePSv3Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet4Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet4Dir/mscorlib.dll`""
        "-r:`"$DotNet4Dir/System.dll`""
        "-r:`"$DotNet4Dir/System.Core.dll`""
        "-r:`"$DotNet4Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-define:PSV3"
        Get-ChildItem "$RepoDir/Engine" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Engine/Commands/GetScriptAnalyzerLoggerCommand.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Engine/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($PSCmdlet.ShouldProcess($enginePSv3Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $enginePSv3Dll)) {
            throw "Could not create file: $enginePSv3Dll"
        }
    }

    Write-Verbose 'Build PSv3 script analyzer cross compatibility.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$compatPSv3Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$DotNet4Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet4Dir/mscorlib.dll`""
        "-r:`"$DotNet4Dir/System.dll`""
        "-r:`"$DotNet4Dir/System.Core.dll`""
        "-r:`"$DotNet4Dir/System.Runtime.Serialization.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-recurse:`"$RepoDir/PSCompatibilityAnalyzer/Microsoft.PowerShell.CrossCompatibility/*.cs`""
        "-define:PSV3"
    }

    if ($PSCmdlet.ShouldProcess($compatPSv3Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $compatPSv3Dll)) {
            throw "Could not create file: $compatPSv3Dll"
        }
    }

    Write-Verbose 'Build PSv3 script analyzer rules.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$rulesPSv3Dll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$enginePSv3Dll`""
        "-r:`"$compatPSv3Dll`""
        "-r:`"$DotNet4Dir/Microsoft.CSharp.dll`""
        "-r:`"$DotNet4Dir/mscorlib.dll`""
        "-r:`"$DotNet4Dir/System.dll`""
        "-r:`"$DotNet4Dir/System.Core.dll`""
        "-r:`"$DotNet4Dir/System.ComponentModel.Composition.dll`""
        "-r:`"$DotNet4Dir/System.Data.Entity.Design.dll`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib/net4/Microsoft.Management.Infrastructure.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib/net4/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-define:PSV3"
        Get-ChildItem "$RepoDir/Rules" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Rules/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($pscmdlet.ShouldProcess($rulesPSv3Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $rulesPSv3Dll)) {
            throw "Could not create file: $rulesPSv3Dll"
        }

        Copy-Item $(GetNugetResource 'Newtonsoft.Json' '11.0.2' 'lib/net45/Newtonsoft.Json.dll' -NugetDir $nugetDir) $modulePSv3Dir -Confirm:$false
    }

}



if ($PSVersion -contains 'Core') {

    Write-Verbose 'Build PSCore script analyzer engine.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$engineCoreDll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-nowarn:1701;1702"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/netstandard.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/Microsoft.CSharp.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.Concurrent.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Console.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Diagnostics.Debug.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Diagnostics.Tools.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.IO.FileSystem.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.Expressions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Resources.ResourceManager.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.Extensions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.InteropServices.RuntimeInformation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Text.RegularExpressions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Threading.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.SDK' '6.2.0' 'ref/netcoreapp2.1/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-define:CORECLR"
        Get-ChildItem "$RepoDir/Engine" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Engine/SafeDirectoryCatalog.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Engine/Commands/GetScriptAnalyzerLoggerCommand.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Engine/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($PSCmdlet.ShouldProcess($engineCoreDll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $engineCoreDll)) {
            throw "Could not create file: $engineCoreDll"
        }
    }

    Write-Verbose 'Build PSCore script analyzer cross compatibility.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$compatCoreDll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/netstandard.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/Microsoft.CSharp.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.Concurrent.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.IO.FileSystem.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.Expressions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.Extensions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.InteropServices.RuntimeInformation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.Serialization.Primitives.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Threading.Tasks.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.SDK' '6.2.0' 'ref/netcoreapp2.1/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '12.0.1' 'lib/netstandard2.0/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-recurse:`"$RepoDir/PSCompatibilityAnalyzer/Microsoft.PowerShell.CrossCompatibility/*.cs`""
        "-define:CORECLR"
    }

    if ($PSCmdlet.ShouldProcess($compatCoreDll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $compatCoreDll)) {
            throw "Could not create file: $compatCoreDll"
        }
    }

    Write-Verbose 'Build PSCore script analyzer rules.' -Verbose

    $compilerArgs = & {
        "-nologo"
        "-nostdlib"
        "-noconfig"
        "-out:`"$rulesCoreDll`""
        "-target:library"
        "-platform:$Platform"
        "-warn:$WarnLevel"
        "-nowarn:1701;1702"
        "-optimize$(if ($Optimize) {'+'} else {'-'})"
        "-r:`"$engineCoreDll`""
        "-r:`"$compatCoreDll`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/netstandard.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/Microsoft.CSharp.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Collections.Specialized.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Diagnostics.Debug.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Diagnostics.Tools.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.IO.FileSystem.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Linq.Expressions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Reflection.TypeExtensions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.Extensions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.InteropServices.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Runtime.InteropServices.RuntimeInformation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.NETCore.App' '2.1.10' 'ref/netcoreapp2.1/System.Text.RegularExpressions.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.Management.Infrastructure' '1.0.0' 'ref/netstandard1.6/Microsoft.Management.Infrastructure.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Microsoft.PowerShell.SDK' '6.2.0' 'ref/netcoreapp2.1/System.Management.Automation.dll' -NugetDir $nugetDir)`""
        "-r:`"$(GetNugetResource 'Newtonsoft.Json' '12.0.1' 'lib/netstandard2.0/Newtonsoft.Json.dll' -NugetDir $nugetDir)`""
        "-define:CORECLR"
        Get-ChildItem "$RepoDir/Rules" -Filter *.cs -Recurse |
            Select-Object -ExpandProperty FullName |
            Where-Object {$_ -ne "$RepoDir/Rules/UseSingularNouns.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)} |
            Where-Object {$_ -ne "$RepoDir/Rules/Strings.Designer.cs".Replace([System.IO.Path]::AltDirectorySeparatorChar, [System.IO.Path]::DirectorySeparatorChar)}
    }

    if ($pscmdlet.ShouldProcess($rulesCoreDll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (Test-Path $rulesCoreDll)) {
            throw "Could not create file: $rulesCoreDll"
        }
    }

}



Write-Verbose 'Generate PSScriptAnalyzer Module help files.' -Verbose

if ($PSCmdlet.ShouldProcess($helpDir, 'Create PSScriptAnalyzer Module Help Directory')) {
    if ((Get-Module platyPS) -or (Get-Module platyPS -list)) {
        platyPS\New-ExternalHelp -Path "$RepoDir/docs/markdown" -OutputPath $helpDir -Force | Out-Null
    }
    else {
        Write-Warning "TODO: build module help file with platyps" -WarningAction Continue
    }
}



Write-Verbose 'Run tests.' -Verbose

if ($PSCmdlet.ShouldProcess($testRunner, 'Create script that runs tests')) {
    @"
    #Run this test script with another powershell
    #so that you do not import the built module's dll to your powershell,
    #which will cause problems the next time you build the module.
    #
    #Some tests import the PSScriptAnalyzer module from `$env:PSModulePath.
    #We can either install PSScriptAnalyzer in `$env:PSModulePath, or
    #we can temporarily change `$env:PSModulePath.

    `$env:PSModulePath = "$outputDir$([System.IO.Path]::PathSeparator)`$(`$env:PSModulePath)"
    Import-Module 'PSScriptAnalyzer' -Verbose

    Pester\Invoke-Pester -Script @('$RepoDir/Tests/Engine', '$RepoDir/Tests/Rules', '$RepoDir/Tests/Documentation') -OutputFile '$testResult' -OutputFormat NUnitXml

    if (Test-Path '$testResult') {
        Get-Item '$testResult'
    }
"@ |
        Out-File $testRunner -Encoding utf8 -Force -Confirm:$false
}

if ($PSCmdlet.ShouldProcess($testRunner, 'Run script that runs tests')) {
    if (Get-Module Pester -list) {
        $powershellProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        $powershellProcessPath = $powershellProcess.Path
        if (@('powershell', 'pwsh') -notcontains $powershellProcess.Name) {
            $powershellProcessPath = 'powershell.exe'
        }

        try {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue

            Write-Verbose "& $powershellProcessPath -NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -File `"$testRunner`"" -Verbose
            & $powershellProcessPath -NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -File "$testRunner"
        }
        finally {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
        }
    }
    else {
        Write-Warning "TODO: test module with pester" -WarningAction Continue
    }
}



if ((-not $WhatIfPreference) -and (Test-Path "$moduleBaseDir/*.psd1")) {
    Get-Item "$moduleBaseDir"
}
