param(
    [Parameter(Mandatory = $true)]
    [string]$sourceEnvFile,

    [Parameter(Mandatory = $true)]
    [string]$destEnvFile,

    [string]$azurePowershellModulePath="C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1",

    [switch]
    $CreateNonExistingObjects
)

Import-Module $azurePowershellModulePath

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

function WriteDebugMessage(){
    param([string] $input)
   "$input" | Write-Verbose
}

function Get-SQLAzureDatabaseConnectionString
{
    param(
        [String]$DatabaseServerName,
        [String]$DatabaseName,
        [String]$UserName,
        [String]$Password
    )
    $conString = $null

    if($subscriptionName -ne 'local'){
        $conString = ("Server=tcp:{0}{1};Database={2};User ID={3}@{0};Password={4};Trusted_Connection=False;Encrypt=True;Connection Timeout=30;" -f
            $DatabaseServerName,$dbServerRootDomain, $DatabaseName, $UserName, $Password)
    }
    else{
        if(!($DatabaseServerName)){
            $DatabaseServerName = $defaultLocalDbServerName
        }

        $conString = ("Data Source={0};Initial Catalog={1};Integrated Security=SSPI" -f $DatabaseServerName, $DatabaseName)
    }

    return $conString
}

function GetStorageConnectionString() {
    param([string] $subscriptionName,
          [string] $storageAccountName,
          [string] $envName)
    # get the subscription id
    $subNode = $configXml.AzureConfiguration.Subscriptions.Subscription | Where-Object {$_.Name -eq $subscriptionName}
    $subId = $subNode.Id

    "GetStorageConnectionString for subscription name [{0}], storage account name [{1}]" -f $subscriptionName, $storageAccountName | WriteDebugMessage

    $conString = $null
    $storageKey = $null
    if($subscriptionName -ne 'local'){
        $azSub = (Get-AzureSubscription | Where-Object {$_.SubscriptionId -eq $subNode.Id})[0]
        # Set-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null
        Select-AzureSubscription -SubscriptionName $azSub.SubscriptionName | Out-Null

        $fullStorageName = GetFullStorageAccountName -baseName $storageAccountName -subId $subId -envName $envName
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

function GetFullStorageAccountName(){
    param(
        [Parameter(Mandatory=$true)]
        [string]$baseName,
        [Parameter(Mandatory=$true)]
        [string]$subId,
        [Parameter(Mandatory=$true)]
        [string]$envName
    )

    

    $storageName = (("{0}-{1}-{2}" -f $baseName, $subId.Substring(0,12), $envName).ToLower());
    
    # remove any non-alpha characters http://stackoverflow.com/questions/3114027/regex-expressions-for-all-non-alphanumeric-symbols
    $storageName = ([System.Text.RegularExpressions.Regex]::Replace($storageName,"\W|_",""))
    if($storageName.Length -gt 24){
        $storageName = $storageName.Substring(0,24)
    } #8C234E83-0A3B-44CE-90DE-ED9C9336BDF1

    return $storageName
}

function Detect-IPAddress
{
    $ipregex = "(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
    $text = Invoke-RestMethod 'http://www.whatismyip.com/api/wimi.php'
    $result = $null

    If($text -match $ipregex)
    {
        $ipaddress = $matches[0]
        $ipparts = $ipaddress.Split('.')
        $ipparts[3] = 0
        $startip = [string]::Join('.',$ipparts)
        $ipparts[3] = 255
        $endip = [string]::Join('.',$ipparts)

        $result = @{StartIPAddress = $startip; EndIPAddress = $endip}
    }

    return $result
}

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
            $conString = GetStorageConnectionString -subscriptionName $subName -storageAccountName $storageKey -envName $envName
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