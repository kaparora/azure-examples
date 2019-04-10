<#
    .DESCRIPTION
        An example Azure Automation runbook which runs pre script followed by a disk snap followed by a post script.
        The scripts must be saved in a storage account in a FileShare
        The Storage account key must be saved in a secret in KeyVault
        The service principal of the azure automation account must have access to the keyvault
        Snapshot names are created using timestamp

    .NOTES
        AUTHOR: Kapil Arora @kapilarora
        LASTEDIT: Apr 10, 2019
        LICENSE: MIT License
#>

Param
(
  [Parameter (Mandatory= $false)]
  [String] $resourceGroupName = "test",

  [Parameter (Mandatory= $false)]
  [String] $diskNamesCommaSeperated = "test_DataDisk_0",

  [Parameter (Mandatory= $false)]
  [String] $connectionName = "AzureRunAsConnection",

  [Parameter (Mandatory= $false)]
  [String] $location = "westeurope",

  [Parameter (Mandatory= $false)]
  [String] $vaultName = "test-vault",

  [Parameter (Mandatory= $false)]
  [String] $keyName = "test-key",

  [Parameter (Mandatory= $false)]
  [String] $storageAccountName = "test-storage-account",

  [Parameter (Mandatory= $false)]
  [String] $fileShareName = "test-share",

  [Parameter (Mandatory= $false)]
  [String] $preScriptPath = "test-pre.sh",

  [Parameter (Mandatory= $false)]
  [String] $postScriptPath = "test-post.sh",

  [Parameter (Mandatory= $false)]
  [String] $vmName = "rtest-vm"
)
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

$diskNames = $diskNamesCommaSeperated.replace(' ','').split(',')


$timestamp = Get-Date -Format dd-MM-yyyy-hh-mm-ss
$snapshotNamePrefix = "snap-" + $timestamp


try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -Tenant $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Write-Output("Getting Storage Account key from KeyVault")
$StorageAccountKey = (Get-AzKeyVaultSecret -VaultName $vaultName -Name $keyName).SecretValueText
Write-Output("Getting Storage Context for Storage Account kaaror")
$StorageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $StorageAccountKey

Write-Output("Downloading pre script from Storage Account Files")
Get-AzStorageFileContent -ShareName $fileShareName -Path $preScriptPath -Context $StorageContext -Destination 'C:\Temp\'
Write-Output("Running Pre Script")
$InvokeResult = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -Name $vmName -CommandId 'RunShellScript' -ScriptPath "C:\Temp\$preScriptPath"
Write-Output ($InvokeResult.Value[0].Message)

$count = 0
foreach($diskName in $diskNames) 
{
    $count = $count + 1
    $snapshotName = $snapshotNamePrefix + "-"+$count
    Write-Output("Getting Disk Id for disk: $diskName")
    $diskId = (Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $diskName).Id

    Write-Output("Creating a Snapshot config for $diskName")
    $snapshot =  New-AzSnapshotConfig -SourceUri $diskId -Location $location -CreateOption copy
    Write-Output("Creating a Snapshot with name $snapshotName on disk $diskName")    New-AzSnapshot -Snapshot $snapshot -SnapshotName $snapshotName -ResourceGroupName $resourceGroupName
    Write-Output("Snapshot command executed")
}


Write-Output("Downloading post script from Storage Account Files")
Get-AzStorageFileContent -ShareName $fileShareName -Path $postScriptPath -Context $StorageContext -Destination 'C:\Temp\'
Write-Output("Running Post Script")
$InvokeResult = Invoke-AzVMRunCommand -ResourceGroupName $resourceGroupName -Name $vmName -CommandId 'RunShellScript' -ScriptPath "C:\Temp\$postScriptPath"
Write-Output ($InvokeResult.Value[0].Message)

