

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
    param(
        [Parameter(Mandatory=$true)]
        $configXml,

        [Parameter(Mandatory=$true)]
        [string] 
        $subscriptionName,
        
        [Parameter(Mandatory=$true)]
        [string] 
        $storageAccountName,

        [Parameter(Mandatory=$true)]
        [string] 
        $envName
    )
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
    $subName = $xmlNode.SubscriptionName
    if(!$subName) {          
        $subName = $xmlNode.ParentNode.DefaultSubscriptionName
    }

    if(!$subName){
        $subName = $defaultSubName
    }

    return $subName
}

function GetFullStorageAccountName(){
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $baseName,

        [Parameter(Mandatory=$true)]
        [string]
        $subId,

        [Parameter(Mandatory=$true)]
        [string]
        $envName
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

function GetProjDirectory(){
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $projectName
    )

    $proj = Get-Project $projectName
    return (get-item ($proj.FullName)).Directory.FullName
}

function GetAzureConfigFileForProject(){
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $projectName,
        [string]
        $envName = 'local'
    )

    $subPath = ("Azure\{0}.xml" -f $envName)
    $result = (Join-Path -Path (GetProjDirectory) -ChildPath $subPath)
    return $result
}

function GetAzureConfigFileForProject(){
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $projectName,
        [string]
        $envName = 'local'
    )

    $subPath = ("Azure\{0}.xml" -f $envName)
    $result = (Join-Path -Path (GetProjDirectory 'WebApplication4') -ChildPath $subPath)
    return $result
}

# This function will look in the local.xml file to see if there is an existing storage acct with the given name
# if not then it will be added to the file and then the local.xml file
# next time the cmd is executed to insert con strings this will be picked up
function AddStorageAcctToProject(){
    param(
        [Parameter(Mandatory=$true)]
        $project,
        
        [Parameter(Mandatory=$true)]
        [string]
        $storageAcctName,

        [string]
        $envName = 'local',
        # the name of the subscription that should be used, these are names from local.xml
        [string]
        $subName = 'dev'
    )

    $configXmlPath = (GetAzureConfigFileForProject -projectName $project -envName $envName)
    [xml]$configXml = Get-Content $configXmlPath
    # inspect the xml file to see if there is already an existing element with that name
    
    $element = ($configXml.AzureConfiguration.Environment.ChildNodes | Where-Object {$_.LocalName -eq 'StorageAccount' -and $_.Name -eq $storageAcctName})
    if($element){
        "`tStorageAccount [{0}] already defined in env file [{1}]" -f $storageAcctName, $envName | Write-Host
        # item already exists
        return;
    }

    # let's add the new element now
    $newElement = $configXml.CreateElement('StorageAccount')
    $newElement.SetAttribute('Name',$storageAcctName)
    $newElement.SetAttribute('SubscriptionName',$subName)
    $configXml.AzureConfiguration.Environment.AppendChild($newElement)
    $configXml.Save($configXmlPath)
}


Export-ModuleMember -function *