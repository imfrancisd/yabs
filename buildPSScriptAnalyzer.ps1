#requires -version 5

<#
.Synopsis
Yet another build script for PSScriptAnalyzer (https://github.com/PowerShell/PSScriptAnalyzer) without Visual Studio or .Net Core.
.Description
==================
Updated 2018-02-20
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
    #/optimize (C# Compiler Options)
    #https://msdn.microsoft.com/en-us/library/t0hfscdc.aspx
    [switch]
    $Optimize,

    #Compiler option.
    #Find more information at:
    #/platform (C# Compiler Options)
    #https://msdn.microsoft.com/en-us/library/zekwfyz4.aspx
    [ValidateSet('anycpu', 'anycpu32bitpreferred', 'arm', 'x86', 'x64', 'Itanium')]
    [string]
    $Platform = 'anycpu',

    #PowerShell versions to target the build.
    [ValidateSet('3', '4', '5', 'Core')]
    [string[]]
    $PSVersion = $(if (($null -ne $PSVersionTable.PSEdition) -and ('Desktop' -ne $PSVersionTable.PSEdition)) {'Core'} else {'5'}),

    #Compiler option.
    #Find more information at:
    #/warn (C# Compiler Options)
    #https://msdn.microsoft.com/en-us/library/13b90fz7.aspx
    [ValidateSet('0', '1', '2', '3', '4')]
    [string]
    $WarnLevel = '4'
)



$ErrorActionPreference = 'Stop'
$isPSCoreProcess = ($null -ne $PSVersionTable.PSEdition) -and ('Desktop' -ne $PSVersionTable.PSEdition)

if (($PSVersion -contains '3') -and ($PSVersion -contains '4')) {
    $PSVersion = @($PSVersion | where-object {$_ -ne '3'})
}

$RepoDir = (get-item $RepoDir).FullName -replace '[\\/]$', ''
$outputDir = "$RepoDir\out"
$moduleBaseDir = "$RepoDir\out\PSScriptAnalyzer"
$modulePSv5Dir = "$RepoDir\out\PSScriptAnalyzer"
$modulePSv4Dir = "$RepoDir\out\PSScriptAnalyzer\PSv3"
$modulePSv3Dir = "$RepoDir\out\PSScriptAnalyzer\PSv3"
$moduleCoreDir = "$RepoDir\out\PSScriptAnalyzer\coreclr"
$helpDir = "$RepoDir\out\PSScriptAnalyzer\en-US"
$testDir = "$RepoDir\tmp\test"
$nugetDir = "$RepoDir\tmp\.nuget"

$enginePSv5Dll = "$modulePSv5Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$enginePSv4Dll = "$modulePSv4Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$enginePSv3Dll = "$modulePSv3Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$engineCoreDll = "$moduleCoreDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.dll"
$rulesPSv5Dll = "$modulePSv5Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesPSv4Dll = "$modulePSv4Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesPSv3Dll = "$modulePSv3Dir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"
$rulesCoreDll = "$moduleCoreDir\Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll"



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

    if ((-not (test-path $resourcePath)) -and $PSCmdlet.ShouldProcess($packageUrl, 'Download nuget package')) {
        mkdir $packageDir -force -confirm:$false | out-null
        invoke-webrequest $packageUrl -outfile $packageZip -verbose
        if (test-path $packageZip) {
            expand-archive $packageZip -destinationpath $packageDir -force
            remove-item $packageZip -confirm:$false
        }
    }

    if ((-not $WhatIfPreference) -and (-not (test-path $resourcePath))) {
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
                $xmlData = [xml](get-content $entry.Value)
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

            foreach ($cultureData in @($resourceContents.GetEnumerator() | sort-object {$_.Key})) {
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
        } | out-file $Destination -encoding utf8 -force
    }

    if ((-not $WhatIfPreference) -and (-not (test-path $Destination))) {
        throw "Could not create file: $Destination"
    }

    $Destination
}



write-verbose 'Create output directory structure.' -verbose

if ($PSCmdlet.ShouldProcess($outputDir, 'Create directory structure')) {
    $moduleBaseDir, $modulePSv5Dir, $modulePSv4Dir, $modulePSv3Dir, $moduleCoreDir, $helpDir, $testDir |
        where-object {test-path $_} |
        foreach-object {remove-item $_ -recurse -force -confirm:$false}

    $moduleBaseDir, $modulePSv5Dir, $modulePSv4Dir, $modulePSv3Dir, $moduleCoreDir, $helpDir, $testdir, $nugetDir |
        foreach-object {new-item -itemtype directory $_ -force -confirm:$false | out-null}

    copy-item "$RepoDir\Engine\PSScriptAnalyzer.ps[dm]1" $moduleBaseDir -confirm:$false
    copy-item "$RepoDir\Engine\ScriptAnalyzer.*.ps1xml" $moduleBaseDir -confirm:$false
    copy-item "$RepoDir\Engine\Settings" -recurse $moduleBaseDir -confirm:$false
    copy-item "$RepoDir\docs\about*.txt" $helpDir -confirm:$false
}



write-verbose 'Get C# compiler.' -verbose

if (-not [string]::IsNullOrWhiteSpace($CscExe) -and (test-path $CscExe)) {
    $compiler = $CscExe
}
elseif ($isPSCoreProcess) {
    throw "Must specify -CscExe with the file path to the C# compiler."
}
else {
    $compiler = GetNugetResource 'Microsoft.Net.Compilers' '1.3.2' 'tools\csc.exe' -nugetDir $nugetDir
}

write-verbose "$compiler" -verbose



if ($PSVersion -contains '5') {

    write-verbose 'Build PSv5 script analyzer engine.' -verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet45Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.5 reference assemblies."
        }
        else {
            write-warning '*** Using unknown .NET framework in place of .NET 4.5. Specify -DotNet45Dir. ***'
            $DotNet45Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet45Dir = (get-item $DotNet45Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$enginePSv5Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$DotNet45Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet45Dir\mscorlib.dll`""
        "/r:`"$DotNet45Dir\System.dll`""
        "/r:`"$DotNet45Dir\System.Core.dll`""
        "/r:`"$DotNet45Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.5.ReferenceAssemblies' '1.1.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        dir "$RepoDir\Engine" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Engine\Commands\GetScriptAnalyzerLoggerCommand.cs"} |
            where-object {$_ -ne "$RepoDir\Engine\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Engine\Strings.resx" "$RepoDir\Engine\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer" "Strings")
    }

    if ($PSCmdlet.ShouldProcess($enginePSv5Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $enginePSv5Dll)) {
            throw "Could not create file: $enginePSv5Dll"
        }
    }

    write-verbose 'Build PSv5 script analyzer rules.' -verbose

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$rulesPSv5Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$enginePSv5Dll`""
        "/r:`"$DotNet45Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet45Dir\mscorlib.dll`""
        "/r:`"$DotNet45Dir\System.dll`""
        "/r:`"$DotNet45Dir\System.Core.dll`""
        "/r:`"$DotNet45Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$DotNet45Dir\System.Data.Entity.Design.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.5.ReferenceAssemblies' '1.1.0' 'lib\net4\Microsoft.Management.Infrastructure.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.5.ReferenceAssemblies' '1.1.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net45\Newtonsoft.Json.dll' -nugetDir $nugetDir)`""
        dir "$RepoDir\Rules" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Rules\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Rules\Strings.resx" "$RepoDir\Rules\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules" "Strings")
    }

    if ($pscmdlet.ShouldProcess($rulesPSv5Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $rulesPSv5Dll)) {
            throw "Could not create file: $rulesPSv5Dll"
        }

        copy-item $(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net45\Newtonsoft.Json.dll' -nugetDir $nugetDir) $modulePSv5Dir -confirm:$false
    }

}



if ($PSVersion -contains '4') {

    write-verbose 'Build PSv4 script analyzer engine.' -verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet45Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.5 reference assemblies."
        }
        else {
            write-warning '*** Using unknown .NET framework in place of .NET 4.5. Specify -DotNet45Dir. ***'
            $DotNet45Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet45Dir = (get-item $DotNet45Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$enginePSv4Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$DotNet45Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet45Dir\mscorlib.dll`""
        "/r:`"$DotNet45Dir\System.dll`""
        "/r:`"$DotNet45Dir\System.Core.dll`""
        "/r:`"$DotNet45Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        "/define:PSV3"
        dir "$RepoDir\Engine" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Engine\Commands\GetScriptAnalyzerLoggerCommand.cs"} |
            where-object {$_ -ne "$RepoDir\Engine\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Engine\Strings.resx" "$RepoDir\Engine\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer" "Strings")
    }

    if ($PSCmdlet.ShouldProcess($enginePSv4Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $enginePSv4Dll)) {
            throw "Could not create file: $enginePSv4Dll"
        }
    }

    write-verbose 'Build PSv4 script analyzer rules.' -verbose

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$rulesPSv4Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$enginePSv4Dll`""
        "/r:`"$DotNet45Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet45Dir\mscorlib.dll`""
        "/r:`"$DotNet45Dir\System.dll`""
        "/r:`"$DotNet45Dir\System.Core.dll`""
        "/r:`"$DotNet45Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$DotNet45Dir\System.Data.Entity.Design.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib\net4\Microsoft.Management.Infrastructure.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.4.ReferenceAssemblies' '1.0.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net45\Newtonsoft.Json.dll' -nugetDir $nugetDir)`""
        "/define:PSV3"
        dir "$RepoDir\Rules" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Rules\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Rules\Strings.resx" "$RepoDir\Rules\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules" "Strings")
    }

    if ($pscmdlet.ShouldProcess($rulesPSv4Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $rulesPSv4Dll)) {
            throw "Could not create file: $rulesPSv4Dll"
        }

        copy-item $(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net45\Newtonsoft.Json.dll' -nugetDir $nugetDir) $modulePSv4Dir -confirm:$false
    }

}



if ($PSVersion -contains '3') {

    write-verbose 'Build PSv3 script analyzer engine.' -verbose

    if (-not $PSBoundParameters.ContainsKey('DotNet4Dir')) {
        if ($isPSCoreProcess) {
            throw "Must specify .NET 4.0 reference assemblies."
        }
        else {
            write-warning '*** Using unknown .NET framework in place of .NET 4.0. Specify -DotNet4Dir. ***'
            $DotNet4Dir = [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
        }
    }
    $DotNet4Dir = (get-item $DotNet4Dir).FullName -replace '[\\/]$', ''

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$enginePSv3Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$DotNet4Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet4Dir\mscorlib.dll`""
        "/r:`"$DotNet4Dir\System.dll`""
        "/r:`"$DotNet4Dir\System.Core.dll`""
        "/r:`"$DotNet4Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        "/define:PSV3"
        dir "$RepoDir\Engine" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Engine\Commands\GetScriptAnalyzerLoggerCommand.cs"} |
            where-object {$_ -ne "$RepoDir\Engine\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Engine\Strings.resx" "$RepoDir\Engine\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer" "Strings")
    }

    if ($PSCmdlet.ShouldProcess($enginePSv3Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $enginePSv3Dll)) {
            throw "Could not create file: $enginePSv3Dll"
        }
    }

    write-verbose 'Build PSv3 script analyzer rules.' -verbose

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$rulesPSv3Dll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$enginePSv3Dll`""
        "/r:`"$DotNet4Dir\Microsoft.CSharp.dll`""
        "/r:`"$DotNet4Dir\mscorlib.dll`""
        "/r:`"$DotNet4Dir\System.dll`""
        "/r:`"$DotNet4Dir\System.Core.dll`""
        "/r:`"$DotNet4Dir\System.ComponentModel.Composition.dll`""
        "/r:`"$DotNet4Dir\System.Data.Entity.Design.dll`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib\net4\Microsoft.Management.Infrastructure.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Microsoft.PowerShell.3.ReferenceAssemblies' '1.0.0' 'lib\net4\System.Management.Automation.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net40\Newtonsoft.Json.dll' -nugetDir $nugetDir)`""
        "/define:PSV3"
        dir "$RepoDir\Rules" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Rules\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Rules\Strings.resx" "$RepoDir\Rules\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules" "Strings")
    }

    if ($pscmdlet.ShouldProcess($rulesPSv3Dll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $rulesPSv3Dll)) {
            throw "Could not create file: $rulesPSv3Dll"
        }

        copy-item $(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\net40\Newtonsoft.Json.dll' -nugetDir $nugetDir) $modulePSv3Dir -confirm:$false
    }

}



if ($PSVersion -contains 'Core') {

    write-verbose 'Build PSCore script analyzer engine.' -verbose

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$engineCoreDll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/nowarn:1701;1702"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$(GetNugetResource 'Microsoft.CSharp' '4.3.0' 'ref\netstandard1.0\Microsoft.CSharp.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections' '4.3.0' 'ref\netstandard1.3\System.Collections.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections.Concurrent' '4.3.0' 'ref\netstandard1.3\System.Collections.Concurrent.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections.NonGeneric' '4.3.0' 'ref\netstandard1.3\System.Collections.NonGeneric.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Diagnostics.Debug' '4.3.0' 'ref\netstandard1.3\System.Diagnostics.Debug.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Diagnostics.Tools' '4.3.0' 'ref\netstandard1.0\System.Diagnostics.Tools.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Dynamic.Runtime' '4.3.0' 'ref\netstandard1.3\System.Dynamic.Runtime.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Globalization' '4.3.0' 'ref\netstandard1.3\System.Globalization.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO' '4.3.0' 'ref\netstandard1.5\System.IO.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO.FileSystem' '4.3.0' 'ref\netstandard1.3\System.IO.FileSystem.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO.FileSystem.Primitives' '4.3.0' 'ref\netstandard1.3\System.IO.FileSystem.Primitives.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Linq' '4.3.0' 'ref\netstandard1.6\System.Linq.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Linq.Expressions' '4.3.0' 'ref\netstandard1.6\System.Linq.Expressions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Management.Automation' '6.0.0-alpha14' 'lib\netstandard1.6\System.Management.Automation.dll' -nugetdir $nugetDir -nugeturl 'https://powershell.myget.org/F/powershell-core/api/v2')`""
        "/r:`"$(GetNugetResource 'System.Reflection' '4.3.0' 'ref\netstandard1.5\System.Reflection.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Reflection.Extensions' '4.3.0' 'ref\netstandard1.0\System.Reflection.Extensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Reflection.TypeExtensions' '4.3.0' 'ref\netstandard1.5\System.Reflection.TypeExtensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Resources.ResourceManager' '4.3.0' 'ref\netstandard1.0\System.Resources.ResourceManager.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Runtime' '4.3.0' 'ref\netstandard1.5\System.Runtime.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Runtime.Extensions' '4.3.0' 'ref\netstandard1.5\System.Runtime.Extensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Text.RegularExpressions' '4.3.0' 'ref\netstandard1.6\System.Text.RegularExpressions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Threading' '4.3.0' 'ref\netstandard1.3\System.Threading.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Threading.Tasks' '4.3.0' 'ref\netstandard1.3\System.Threading.Tasks.dll' -nugetdir $nugetDir)`""
        "/define:CORECLR"
        dir "$RepoDir\Engine" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Engine\SafeDirectoryCatalog.cs"} |
            where-object {$_ -ne "$RepoDir\Engine\Commands\GetScriptAnalyzerLoggerCommand.cs"} |
            where-object {$_ -ne "$RepoDir\Engine\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Engine\Strings.resx" "$RepoDir\Engine\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer" "Strings")
    }

    if ($PSCmdlet.ShouldProcess($engineCoreDll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $engineCoreDll)) {
            throw "Could not create file: $engineCoreDll"
        }
    }

    write-verbose 'Build PSCore script analyzer rules.' -verbose

    $compilerArgs = & {
        '/nologo'
        '/nostdlib'
        '/noconfig'
        "/out:`"$rulesCoreDll`""
        "/target:library"
        "/platform:$Platform"
        "/warn:$WarnLevel"
        "/nowarn:1701;1702"
        "/optimize$(if ($Optimize) {'+'} else {'-'})"
        "/r:`"$engineCoreDll`""
        "/r:`"$(GetNugetResource 'Microsoft.CSharp' '4.3.0' 'ref\netstandard1.0\Microsoft.CSharp.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'Microsoft.Management.Infrastructure' '1.0.0-alpha05' 'ref\netstandard1.6\Microsoft.Management.Infrastructure.dll' -nugetdir $nugetDir -nugeturl 'https://powershell.myget.org/F/powershell-core/api/v2')`""
        "/r:`"$(GetNugetResource 'Newtonsoft.Json' '10.0.3' 'lib\netstandard1.3\Newtonsoft.Json.dll' -nugetDir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections' '4.3.0' 'ref\netstandard1.3\System.Collections.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections.Concurrent' '4.3.0' 'ref\netstandard1.3\System.Collections.Concurrent.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections.NonGeneric' '4.3.0' 'ref\netstandard1.3\System.Collections.NonGeneric.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Collections.Specialized' '4.3.0' 'ref\netstandard1.3\System.Collections.Specialized.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Diagnostics.Debug' '4.3.0' 'ref\netstandard1.3\System.Diagnostics.Debug.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Diagnostics.Tools' '4.3.0' 'ref\netstandard1.0\System.Diagnostics.Tools.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Dynamic.Runtime' '4.3.0' 'ref\netstandard1.3\System.Dynamic.Runtime.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Globalization' '4.3.0' 'ref\netstandard1.3\System.Globalization.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO' '4.3.0' 'ref\netstandard1.5\System.IO.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO.FileSystem' '4.3.0' 'ref\netstandard1.3\System.IO.FileSystem.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.IO.FileSystem.Primitives' '4.3.0' 'ref\netstandard1.3\System.IO.FileSystem.Primitives.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Linq' '4.3.0' 'ref\netstandard1.6\System.Linq.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Linq.Expressions' '4.3.0' 'ref\netstandard1.6\System.Linq.Expressions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Management.Automation' '6.0.0-alpha14' 'lib\netstandard1.6\System.Management.Automation.dll' -nugetdir $nugetDir -nugeturl 'https://powershell.myget.org/F/powershell-core/api/v2')`""
        "/r:`"$(GetNugetResource 'System.Reflection' '4.3.0' 'ref\netstandard1.5\System.Reflection.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Reflection.Extensions' '4.3.0' 'ref\netstandard1.0\System.Reflection.Extensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Reflection.TypeExtensions' '4.3.0' 'ref\netstandard1.5\System.Reflection.TypeExtensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Resources.ResourceManager' '4.3.0' 'ref\netstandard1.0\System.Resources.ResourceManager.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Runtime' '4.3.0' 'ref\netstandard1.5\System.Runtime.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Runtime.Extensions' '4.3.0' 'ref\netstandard1.5\System.Runtime.Extensions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Security.SecureString' '4.3.0' 'ref\netstandard1.3\System.Security.SecureString.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Text.Encoding' '4.3.0' 'ref\netstandard1.3\System.Text.Encoding.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Text.RegularExpressions' '4.3.0' 'ref\netstandard1.6\System.Text.RegularExpressions.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Threading' '4.3.0' 'ref\netstandard1.3\System.Threading.dll' -nugetdir $nugetDir)`""
        "/r:`"$(GetNugetResource 'System.Threading.Tasks' '4.3.0' 'ref\netstandard1.3\System.Threading.Tasks.dll' -nugetdir $nugetDir)`""
        "/define:CORECLR"
        dir "$RepoDir\Rules" -filter *.cs -recurse |
            select-object -expandproperty fullname |
            where-object {$_ -ne "$RepoDir\Rules\UseSingularNouns.cs"} |
            where-object {$_ -ne "$RepoDir\Rules\Strings.Designer.cs"}
        $(ConvertResxStringsToCsharp "$RepoDir\Rules\Strings.resx" "$RepoDir\Rules\Strings.Designer.cs" "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules" "Strings")
    }

    if ($pscmdlet.ShouldProcess($rulesCoreDll, 'Create file')) {
        & $compiler $compilerArgs

        if (-not (test-path $rulesCoreDll)) {
            throw "Could not create file: $rulesCoreDll"
        }
    }

}



write-verbose 'Generate PSScriptAnalyzer Module help files.' -verbose

if ($PSCmdlet.ShouldProcess($helpDir, 'Create PSScriptAnalyzer Module Help Directory')) {
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

    import-module '$moduleBaseDir'
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
        $powershellProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().Path
        if ((split-path $powershellProcessPath -leaf) -ne 'powershell.exe') {
            $powershellProcessPath = 'powershell.exe'
        }
        try {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
            & $powershellProcessPath -noprofile -executionpolicy remotesigned -noninteractive -file "$testFile"
        }
        finally {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
        }
    }
    else {
        write-warning "TODO: test module with pester" -warningaction continue
    }
}



if ((-not $WhatIfPreference) -and (test-path "$moduleBaseDir\*.psd1")) {
    get-item "$moduleBaseDir\*.psd1"
}
