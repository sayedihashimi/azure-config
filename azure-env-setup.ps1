
# you can se to
$VerbosePreference = "Continue"

# TODO: This should be passed in as a parameter
$sourceEnvironmentFile = 'C:\Data\Dropbox\Microsoft\Hummingbird\Samples\WorkerAndQueue\Azure\Environments\azureenv.xml'
$destEnvironmentFile = 'C:\temp\azure\azureenv.xml'
$defaultSubName = 'local'

# constants which change script behavior
$storageUsePrimaryKey = $true
$storageDefaultProtocol = 'https'

############ Begin script

# copy the source file to the destination
Copy-Item -LiteralPath $sourceEnvironmentFile -Destination $destEnvironmentFile

[xml]$configXml = Get-Content $destEnvironmentFile
$currentAzureSubBefore = Get-AzureSubscription -Current

function WriteDebugMessage(){
    param([string] $input)
   "writing: $input" | Write-Verbose
}

function GetStorageConnectionString() {
    param([string] $subscriptionName,
          [string] $storageAccountName)
    # get the subscription id
    $subNode = $configXml.AzureConfiguration.Subscriptions.Subscription | Where-Object {$_.Name -eq $subscriptionName}
    $subId = $subNode.Id

    "GetStorageConnectionString for subscription name [{0}], storage account name [{1}]" -f $subscriptionName, $storageAccountName | WriteDebugMessage

    $storageKey = $null
    if($subscriptionName -ne 'local'){
        $azSub = Get-AzureSubscription | Where-Object {$_.SubscriptionId -eq $subNode.Id}
        Set-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null

        $storageKey = Get-AzureStorageKey -StorageAccountName $storageAccountName
    }
    else{
        $storageKey = 'UseDevelopmentStorage=true'
    }

    $conString = $null

    if($storageKey){
        # format of the con string: DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>
        $accessKey = $null
        if($storageUsePrimaryKey){ $accessKey = $storageKey.Primary }
        else{ $accessKey = $storageKey.Secondary }

        $conString = ("DefaultEndpointsProtocol={0};AccountName={1};AccountKey={2}" -f $storageDefaultProtocol, $storageKey.StorageAccountName, $accessKey)
        "Storage connection string: [{0}]" -f $conString | WriteDebugMessage | Out-Null
    }
    return $conString
}

# Find all StorageAccount elements under Environments and then populate the connection string
foreach($node in $configXml.AzureConfiguration.Environment.ChildNodes){
    # see if the node has a ConnectionString element if it does skip over it
    if(!$node.ConnectionString){
        # does the node have  a SubscriptionName attribute?
        $subName = $node.SubscriptionName
        if(!$subName) {          
            $subName = $node.ParentNode.DefaultSubscriptionName
        }

        if(!$subName){
            $subName = $defaultSubName
        }

        # get the connection string for the asset
        $conString = $null
        if($node.LocalName -eq 'StorageAccount'){
            $conString = GetStorageConnectionString -subscriptionName $subName -storageAccountName $node.Name
            ("Storage key: {0}" -f $conString) | Write-Host -ForegroundColor DarkCyan
        }
    }
}

# restore the original azure subscription
if($currentAzureSubBefore){
    Set-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName
}