function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$azurePowershellModulePath= ("{0}\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1" -f ${env:ProgramFiles(x86)})
if(Test-Path $azurePowershellModulePath){
# import the Azure cmd lets
Import-Module $azurePowershellModulePath
}

# TODO: Remove this its just for debugging
if((Get-Module azure-helpers)){
    Remove-Module azure-helpers
}
$VerbosePreference = "Continue"
# import the helper functions we've created
Import-Module (Join-Path -Path (Get-ScriptDirectory) -ChildPath 'azure-helpers.psm1') -PassThru