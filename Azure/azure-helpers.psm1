
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

function UpdateFileWithEndpointInfo(){
    param(
        [Parameter(Mandatory=$true)]
        [xml]
        $configXml,

        [Parameter(Mandatory=$true)]
        [string]
        $destEnvFile
    )
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
}
function AzureCreateNonExistingObjects(){
    param(
        [Parameter(Mandatory=$true)]
        [xml]
        $configXml
    )

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

# Functions related to the VS project
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

    $result = (Join-Path -Path (((get-item $project.FileName).Directory).FullName) -ChildPath $subPath)
    return $result
}

function GetOutputPathForProject(){
    param(
        $project = (Get-Project)
    )

    $outputPathForProj = ($project.ConfigurationManager.ActiveConfiguration.Properties.Item("OutputPath").Value.ToString())
    
    # resolve it to a full path
    $oldLoc = Get-Location
    Set-Location (((get-item $project.FileName).Directory).FullName)
    $fullPathToOutputFolder = (Resolve-Path $outputPathForProj).ToString()
    Set-Location $oldLoc
    
    # make sure the path ends with a \ before returning to the caller
    $fulPathToOutputFolder = $fullPathToOutputFolder.Trim()
    if(!$fullPathToOutputFolder.EndsWith('\')){
        $fullPathToOutputFolder += '\'
    }

    return $fullPathToOutputFolder
}

function GetProjectAzureOutputFile(){
    param(
        $project = (Get-Project),
        
        [string]
        $envName = 'local'
    )

    return ("{0}{1}.xml" -f (GetOutputPathForProject), $envName)    
}

# This function will look in the local.xml file to see if there is an existing storage acct with the given name
# if not then it will be added to the file and then the local.xml file
# next time the cmd is executed to insert con strings this will be picked up
function AzureAddStorageAcctToProject(){
    param(
        $project = (Get-Project),
        
        [Parameter(Mandatory=$true)]
        [string]
        $storageAcctName,

        [string]
        $envName = 'local',
        # the name of the subscription that should be used, these are names from local.xml
        [string]
        $subName = 'dev'
    )

    $configXmlPath = (GetAzureConfigFileForProject -projectName $project.Name -envName $envName)

    # convert it to a full path
    $oldLoc = Get-Location
    Set-Location (((get-item $project.FileName).Directory).Parent.FullName)
    $configXmlPath = (Resolve-Path $configXmlPath)
    Set-Location $oldLoc

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

function AzureUpdateProjectOutputFile(){
    param(
        $project = (Get-Project),

        [string]
        $envName = 'local',

        $sourceEnvFile,
        $destEnvFile,

        [switch]
        $CreateNonExistingObjects
    )

    if(!$sourceEnvFile){
        $sourceEnvFile = GetAzureConfigFileForProject -projectName $project.Name -envName $envName
    }
    if(!$destEnvFile){
        $destEnvFile = GetProjectAzureOutputFile -project $project -envName $envName
    }

    # TODO: Is this necessary?
    Copy-Item -LiteralPath $sourceEnvFile -Destination $destEnvFile
    
    [xml]$configXml = Get-Content $destEnvFile
    $currentAzureSubBefore = Get-AzureSubscription -Current

    if($CreateNonExistingObjects){
        "Calling CreateNonExistingObjects" | Write-Host
        AzureCreateNonExistingObjects -configXml $configXml
    }

    UpdateFileWithEndpointInfo -configXml $configXml -destEnvFile $destEnvFile

    # restore the original azure subscription
    if($currentAzureSubBefore){
        # Set-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName
        Select-AzureSubscription -SubscriptionName $currentAzureSubBefore.SubscriptionName | Out-Null
    }
}

# Set-Alias Update-AzureProjFile UpdateFileWithEndpointInfo

Export-ModuleMember -function AzureCreateNonExistingObjects,AzureUpdateProjectOutputFile, AzureAddStorageAcctToProject

Export-ModuleMember -function *