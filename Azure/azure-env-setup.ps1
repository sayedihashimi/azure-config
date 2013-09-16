param(
    [Parameter(Mandatory = $true)]
    [string]$sourceEnvFile,

    [Parameter(Mandatory = $true)]
    [string]$destEnvFile,

    [string]$azurePowershellModulePath="C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1",

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

# TODO :Finish later
# import the helper functions we've created
$scriptDir = Get-ScriptDirectory
Import-Module (Join-Path -Path $scriptDir -ChildPath 'azure-helpers.psm1')


# set this after importing the module
$VerbosePreference = "Continue"

$defaultSubName = 'local'
$defaultLocalDbServerName = '(LocalDb)\v11.0'
$defaultStorageLocation = 'West US'

# TODO: GAP: We cannot get the SQL Database password, need to update the APIs to expose it or
#            or some better runtime support for getting the password somehow
$dbPassword = 'p@ssw0rd'
# constants which change script behavior
$storageUsePrimaryKey = $true
$storageDefaultProtocol = 'https'
$dbServerRootDomain = ".database.windows.net,1433"

############ Begin script

# copy the source file to the destination
Copy-Item -LiteralPath $sourceEnvFile -Destination $destEnvFile

[xml]$configXml = Get-Content $destEnvFile
$currentAzureSubBefore = Get-AzureSubscription -Current

if($CreateNonExistingObjects){
    $currentSubscription = Get-AzureSubscription -Current

    "Creating non-existing object in environment" | WriteDebugMessage
    foreach($node in $configXml.AzureConfiguration.Environment.ChildNodes){
        if(($node -is [System.Xml.XmlComment])){
            continue
        }

        $envName = $configXml.AzureConfiguration.Environment.Name
        $subName = GetSubscriptionValueForNode -xmlNode $node
        $subNode = $configXml.AzureConfiguration.Subscriptions.Subscription | Where-Object {$_.Name -eq $subName}
        $subId = $subNode.Id

        if($subName -eq 'local'){
            # create local resources here
            # TODO: What needs to be done here?
        }
        else{
            if($subId -ne $currentSubscription.SubscriptionId){                
                $azSub = (Get-AzureSubscription | Where-Object {$_.SubscriptionId -eq $subNode.Id})[0]
                # Set-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null
                Select-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null
            }

            if($node.LocalName -eq 'StorageAccount'){
                # if the storage account doesn't exit create it
                $storageName = GetFullStorageAccountName -baseName $node.Name -subId $subId -envName $envName
                # Get-AzureStorageAccount -StorageAccountName $node.Name | Out-Null
                Get-AzureStorageAccount -StorageAccountName $storageName | Out-Null
                if(!($?)){
                    "Creating storage account [{0}]" -f $storageName | WriteDebugMessage
                    $newStorageAcct = (New-AzureStorageAccount -StorageAccountName $storageName -Location $defaultStorageLocation)
                    "Done creating storage account" | WriteDebugMessage
                }
            }
            elseif($node.LocalName -eq 'SqlDatabase'){
                # see if the db server exists or not
                $dbServer = (Get-AzureSqlDatabaseServer | Where-Object {$_.ServerName -eq $node.ServerName })
                "what happened" | WriteDebugMessage
            }
        }
    }
}

# Find all StorageAccount elements under Environments and then populate the connection string
foreach($node in $configXml.AzureConfiguration.Environment.ChildNodes){
    if(($node -is [System.Xml.XmlComment])){
        continue
    }

    $subName = GetSubscriptionValueForNode -xmlNode $node
    $subNode = $configXml.AzureConfiguration.Subscriptions.Subscription | Where-Object {$_.Name -eq $subName}
    $subId = $subNode.Id
    
    # see if the node has a ConnectionString element if it does skip over it
    if(!$node.ConnectionString){                     
        # get the connection string for the asset
        $conString = $null
        $envName = $configXml.AzureConfiguration.Environment.Name
        if($node.LocalName -eq 'StorageAccount'){
            $storageKey = GetFullStorageAccountName -baseName $node.Name -subId $subId -envName $envName
            $conString = GetStorageConnectionString -configXml $configXml -subscriptionName $subName -storageAccountName $storageKey -envName $envName
            # add the ConnectionString attribute to the element
            $node.SetAttribute('ConnectionString',$conString)
        }
        elseif($node.LocalName -eq 'SqlDatabase'){
            $dbServer = (Get-AzureSqlDatabaseServer | Where-Object {$_.ServerName -eq $node.ServerName })
            $dbName = $node.Name

            $dbConString = (Get-SQLAzureDatabaseConnectionString -DatabaseServerName $dbServer.ServerName -DatabaseName $node.Name -UserName $dbServer.AdministratorLogin -Password $dbPassword)
            "DB connection string: [{0}]" -f $dbConString | WriteDebugMessage

            $node.SetAttribute("ConnectionString",$dbConString)
        }
    }
    else{
        "Skipped updating ConnectionString because the element has alredy defined the attribute" | WriteDebugMessage
    }
}

# save the new XML file to the destination
"Saving config file with the updated contents at [{0}]" -f $destEnvFile | WriteDebugMessage
$configXml.Save($destEnvFile)

# restore the original azure subscription
if($currentAzureSubBefore){
    # Set-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName
    Select-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName | Out-Null
}
# TODO: Remove this later
$VerbosePreference = "SilentlyContinue"