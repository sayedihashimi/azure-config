param(
    [string]
    $sourceEnvFile,

    [string]
    $destEnvFile,

    $project = (Get-Project),

    [string]
    $envName = 'local',

    [string]
    $azurePowershellModulePath="C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1",

    [switch]
    $CreateNonExistingObjects
)
function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}
# import the Azure cmd lets
Import-Module $azurePowershellModulePath

# TODO: Remove this its just for debugging
if((Get-Module azure-helpers)){
    Remove-Module azure-helpers
}
$VerbosePreference = "Continue"
# import the helper functions we've created
Import-Module (Join-Path -Path (Get-ScriptDirectory) -ChildPath 'azure-helpers.psm1') -PassThru

# set this after importing the module
$VerbosePreference = "Continue"

# TODO: There must be a better way to do this
if($CreateNonExistingObjects){
    UpdateAzureProjectInfo -project $project -envName $envName -sourceEnvFile $sourceEnvFile -destEnvFile $destEnvFile -CreateNonExistingObjects
}
else{
    UpdateAzureProjectInfo -project $project -envName $envName -sourceEnvFile $sourceEnvFile -destEnvFile $destEnvFile 
}

# TODO: Remove this later
$VerbosePreference = "SilentlyContinue"