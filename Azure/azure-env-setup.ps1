
# you can se to

#TODO: make into a script parameter
$azurePowershellModulePath = "C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"
Import-Module $azurePowershellModulePath

# set this after importing the module
$VerbosePreference = "Continue"

# TODO: This should be passed in as a parameter
$sourceEnvironmentFile = 'C:\Data\Dropbox\Microsoft\Hummingbird\Samples\WorkerAndQueue\Azure\Environments\azureenv.xml'
$destEnvironmentFile = 'C:\temp\azure\azureenv.xml'
$defaultSubName = 'local'

# TODO: GAP: We cannot get the SQL Database password, need to update the APIs to expose it or
#            or some better runtime support for getting the password somehow
$dbPassword = 'p@ssw0rd'
# constants which change script behavior
$storageUsePrimaryKey = $true
$storageDefaultProtocol = 'https'
$dbServerRootDomain = ".database.windows.net,1433"

############ Begin script

# copy the source file to the destination
Copy-Item -LiteralPath $sourceEnvironmentFile -Destination $destEnvironmentFile

[xml]$configXml = Get-Content $destEnvironmentFile
$currentAzureSubBefore = Get-AzureSubscription -Current

function WriteDebugMessage(){
    param([string] $input)
   "$input" | Write-Verbose
}

function Get-SQLAzureDatabaseConnectionString
{
    Param(
        [String]$DatabaseServerName,
        [String]$DatabaseName,
        [String]$UserName,
        [String]$Password
    )

    Return "Server=tcp:{0}{1};Database={2};User ID={3}@{0};Password={4};Trusted_Connection=False;Encrypt=True;Connection Timeout=30;" -f
        $DatabaseServerName,$dbServerRootDomain, $DatabaseName, $UserName, $Password
}

function GetStorageConnectionString() {
    param([string] $subscriptionName,
          [string] $storageAccountName)
    # get the subscription id
    $subNode = $configXml.AzureConfiguration.Subscriptions.Subscription | Where-Object {$_.Name -eq $subscriptionName}
    $subId = $subNode.Id

    "GetStorageConnectionString for subscription name [{0}], storage account name [{1}]" -f $subscriptionName, $storageAccountName | WriteDebugMessage

    $conString = $null
    $storageKey = $null
    if($subscriptionName -ne 'local'){
        $azSub = Get-AzureSubscription | Where-Object {$_.SubscriptionId -eq $subNode.Id}
        Set-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null

        $storageKey = Get-AzureStorageKey -StorageAccountName $storageAccountName

        if($storageKey){
            # format of the con string: DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>
            $accessKey = $null
            if($storageUsePrimaryKey){ $accessKey = $storageKey.Primary }
            else{ $accessKey = $storageKey.Secondary }

            $conString = ("DefaultEndpointsProtocol={0};AccountName={1};AccountKey={2}" -f $storageDefaultProtocol, $storageKey.StorageAccountName, $accessKey)
            "Storage connection string: [{0}]" -f $conString | WriteDebugMessage | Out-Null

        }
        else{
            "Storage account key not found." |Write-Error
            Exit 2
        }
    }
    else{
        $conString = 'UseDevelopmentStorage=true'
    }

    return $conString
}
function GetSubscriptionValueForNode(){
    param([System.Xml.XmlElement]$xmlNode)
    # does the node have  a SubscriptionName attribute?
    $subName = $node.SubscriptionName
    if(!$subName) {          
        $subName = $node.ParentNode.DefaultSubscriptionName
    }

    if(!$subName){
        $subName = $defaultSubName
    }

    return $subName
}

# Find all StorageAccount elements under Environments and then populate the connection string
foreach($node in $configXml.AzureConfiguration.Environment.ChildNodes){
    $subName = GetSubscriptionValueForNode -xmlNode $node
    
    # see if the node has a ConnectionString element if it does skip over it
    if(!$node.ConnectionString){                     
        # get the connection string for the asset
        $conString = $null
        if($node.LocalName -eq 'StorageAccount'){
            $conString = GetStorageConnectionString -subscriptionName $subName -storageAccountName $node.Name
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
"Saving config file with the updated contents at [{0}]" -f $destEnvironmentFile | WriteDebugMessage
$configXml.Save($destEnvironmentFile)

# restore the original azure subscription
if($currentAzureSubBefore){
    Set-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName
}
# TODO: Remove this later
$VerbosePreference = "SilentlyContinue"