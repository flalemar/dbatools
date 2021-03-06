<#

#-------------------------#
# Warning Warning Warning #
#-------------------------#

This is the global configuration management file.

DO NOT EDIT THIS FILE!!!!!
Disobedience shall be answered by the wrath of Fred.
You've been warned.
;)

The purpose of this file is to manage the configuration system.
That means, messing with this may mess with every function using this infrastructure.
Don't, unless you know what you do.

#---------------------------------------#
# Implementing the configuration system #
#---------------------------------------#

The configuration system is designed, to keep as much hard coded configuration out of the functions.
Instead we keep it in a central location: The Configuration store (= this folder).

In Order to put something here, either find a configuration file whose topic suits you and add configuration there,
or create your own file. The configuration system is loaded last during module import process, so you have access to all
that dbatools has to offer (Keep module load times in mind though).

Examples are better than a thousand words:

a) Setting the configuration value
# Put this in a configuration file in this folder
Set-DbatoolsConfig -Name 'Path.DbatoolsLog' -Value "$($env:AppData)\PowerShell\dbatools" -Initialize -Description "Sopmething meaningful here"

b) Retrieving the configuration value in your function
# Put this in the function that uses this setting
$path = Get-DbatoolsConfigValue -Name 'Path.DbatoolsLog' -FallBack $env:temp

# Explanation #
#-------------#

In step a), which is run during module import, we assign the configuration of the name 'Path.DbatoolsLog' the value "$($env:AppData)\PowerShell\dbatools"
Unless there already IS a value set to this name (that's what the '-Default' switch is doing).
That means, that if a user had a different configuration value in his profile, that value will win. Userchoice over preset.
ALL configurations defined by the module should be 'default' values.

In step b), which will be run whenever the function is called within which it is written, we retrieve the value stored behind the name 'Path.DbatoolsLog'.
If there is nothing there (for example, if the user accidentally removed or nulled the configuration), then it will fall back to using "$($env:temp)\dbatools.log"

#>

#region Paths
$script:path_RegistryUserDefault = "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default"
$script:path_RegistryUserEnforced = "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced"
$script:path_RegistryMachineDefault = "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default"
$script:path_RegistryMachineEnforced = "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced"
$psVersionName = "WindowsPowerShell"
if ($PSVersionTable.PSVersion.Major -ge 6) { $psVersionName = "PowerShell" }

#region User Local
if ($IsLinux -or $IsMacOs)
{
    # Defaults to $Env:XDG_CONFIG_HOME on Linux or MacOS ($HOME/.config/)
    $fileUserLocal = $Env:XDG_CONFIG_HOME
    if (-not $fileUserLocal) { $fileUserLocal = Join-Path $HOME .config/ }
    
    $script:path_FileUserLocal = Join-DbaPath $fileUserLocal $psVersionName "dbatools/"
}
else
{
    # Defaults to $Env:LocalAppData on Windows
    $script:path_FileUserLocal = Join-Path $Env:LocalAppData "$psVersionName\dbatools\Config"
    if (-not $script:path_FileUserLocal) { $script:path_FileUserLocal = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "$psVersionName\dbatools\Config" }
}
#endregion User Local

#region User Shared
if ($IsLinux -or $IsMacOs)
{
    # Defaults to the first value in $Env:XDG_CONFIG_DIRS on Linux or MacOS (or $HOME/.local/share/)
    $fileUserShared = @($Env:XDG_CONFIG_DIRS -split ([IO.Path]::PathSeparator))[0]
    if (-not $fileUserShared) { $fileUserShared = Join-Path $HOME .local/share/ }
    
    $script:path_FileUserShared = Join-DbaPath $fileUserShared $psVersionName "dbatools/"
    $script:AppData = $fileUserShared
}
else
{
    # Defaults to $Env:AppData on Windows
    $script:path_FileUserShared = Join-DbaPath $Env:AppData $psVersionName "dbatools" "Config"
    $script:AppData = $Env:APPDATA
    if (-not $Env:AppData)
    {
        $script:path_FileUserShared = Join-DbaPath ([Environment]::GetFolderPath("ApplicationData")) $psVersionName "dbatools" "Config"
        $script:AppData = [Environment]::GetFolderPath("ApplicationData")
    }
}
#endregion User Shared

#region System
if ($IsLinux -or $IsMacOs)
{
    # Defaults to /etc/xdg elsewhere
    $XdgConfigDirs = $Env:XDG_CONFIG_DIRS -split ([IO.Path]::PathSeparator) | Where-Object { $_ -and (Test-Path $_) }
    if ($XdgConfigDirs.Count -gt 1) { $basePath = $XdgConfigDirs[1] }
    else { $basePath = "/etc/xdg/" }
    $script:path_FileSystem = Join-DbaPath $basePath $psVersionName "dbatools/"
}
else
{
    # Defaults to $Env:ProgramData on Windows
    $script:path_FileSystem = Join-DbaPath $Env:ProgramData $psVersionName "dbatools" "Config"
    if (-not $script:path_FileSystem) { $script:path_FileSystem = Join-DbaPath ([Environment]::GetFolderPath("CommonApplicationData")) $psVersionName "dbatools" "Config" }
}
#endregion System

#region Special Paths
# $script:AppData is already OS localized
$script:path_Logging = Join-DbaPath $script:AppData $psVersionName "dbatools" "Logs"
$script:path_typedata = Join-DbaPath $script:AppData $psVersionName "dbatools" "TypeData"
#endregion Special Paths
#endregion Paths

# Determine Registry Availability
$script:NoRegistry = $false
if (($PSVersionTable.PSVersion.Major -ge 6) -and ($PSVersionTable.OS -notlike "*Windows*"))
{
    $script:NoRegistry = $true
}

$configpath = Resolve-Path "$script:PSModuleRoot\internal\configurations"

# Import configuration validation
foreach ($file in (Get-ChildItem -Path (Resolve-Path "$configpath\validation")))
{
    if ($script:doDotSource) { . $file.FullName }
    else { . ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))) }
}

# Import other configuration files
foreach ($file in (Get-ChildItem -Path (Resolve-Path "$configpath\settings")))
{
    if ($script:doDotSource) { . $file.FullName }
    else { . ([scriptblock]::Create([io.file]::ReadAllText($file.FullName))) }
}

if (-not [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ImportFromRegistryDone)
{
    # Read config from all settings
    $config_hash = Read-DbatoolsConfigPersisted -Scope 127
    
    foreach ($value in $config_hash.Values)
    {
        try
        {
            if (-not $value.KeepPersisted) { Set-DbatoolsConfig -FullName $value.FullName -Value $value.Value -EnableException }
            else { Set-DbatoolsConfig -FullName $value.FullName -PersistedValue $value.Value -PersistedType $value.Type -EnableException }
            [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLower()].PolicySet = $value.Policy
            [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$value.FullName.ToLower()].PolicyEnforced = $value.Enforced
        }
        catch { }
    }
    
    if ($null -ne $global:dbatools_config)
    {
        if ($global:dbatools_config.GetType().FullName -eq "System.Management.Automation.ScriptBlock")
        {
            [System.Management.Automation.ScriptBlock]::Create($global:dbatools_config.ToString()).Invoke()
        }
    }
    
    [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::ImportFromRegistryDone = $true
}
