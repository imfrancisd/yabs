# yabs
Yet another build script (minimal tools and no magic) for github repos I want to try.

## Why?
Because sometimes I just want to build.

## Will the build artifacts run on all computers?
Probably not.

Minimal tools means, if possible, only the tools on your computer, which means the build artifacts may not work on other computers.

This is meant for trying out changes on projects without having to worry about .sln, project.json, .yml, .csproj, msbuild, .NET core, to nuget restore or not to nuget restore, and so on.

## Which projects will these scripts build?
For now, only PSScriptAnalyzer.

## Will these script always be updated.
Probably not.

But the scripts will have explicit explanations of what the project depends on, so if you can read PowerShell, you should be able to modify the script if you want.
