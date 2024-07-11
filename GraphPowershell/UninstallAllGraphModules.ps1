#Uninstall Microsoft.Graph modules except Microsoft.Graph.Authentication
$Modules = Get-Module Microsoft.Graph* -ListAvailable | 
Where-Object {$_.Name -ne "Microsoft.Graph.Authentication"} | Select-Object Name -Unique

Foreach ($Module in $Modules){
  $ModuleName = $Module.Name
  $Versions = Get-Module $ModuleName -ListAvailable
  Foreach ($Version in $Versions){
    $ModuleVersion = $Version.Version
    Write-Host "Uninstall-Module $ModuleName $ModuleVersion"
    Uninstall-Module $ModuleName -RequiredVersion $ModuleVersion -ErrorAction SilentlyContinue
  }
}

#Uninstall the modules cannot be removed from first part.
$InstalledModules = Get-InstalledModule Microsoft.Graph* | 
Where-Object {$_.Name -ne "Microsoft.Graph.Authentication"} | Select-Object Name -Unique

Foreach ($InstalledModule in $InstalledModules){
  $InstalledModuleName = $InstalledModule.Name
  $InstalledVersions = Get-Module $InstalledModuleName -ListAvailable
  Foreach ($InstalledVersion in $InstalledVersions){
    $InstalledModuleVersion = $InstalledVersion.Version
    Write-Host "Uninstall-Module $InstalledModuleName $InstalledModuleVersion"
    Uninstall-Module $InstalledModuleName -RequiredVersion $InstalledModuleVersion -ErrorAction SilentlyContinue
  }
}

#Uninstall Microsoft.Graph.Authentication
$ModuleName = "Microsoft.Graph.Authentication"
$Versions = Get-Module $ModuleName -ListAvailable

Foreach ($Version in $Versions){
  $ModuleVersion = $Version.Version
  Write-Host "Uninstall-Module $ModuleName $ModuleVersion"
  Uninstall-Module $ModuleName -RequiredVersion $ModuleVersion
}
