#login to azure
$connectionName = "AzureRunAsConnection"
try{
    "Logging in to Azure..."    
    $connection = Get-AutomationConnection -Name $connectionName
    Connect-AzAccount -ServicePrincipal `
                  -Tenant $connection.TenantId `
                  -ApplicationID $connection.ApplicationId `
                  -CertificateThumbprint $connection.CertificateThumbprint    
}
catch {
    if (!$servicePrincipalConnection){
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } 
    else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
# This is where the work starts:
$workspaceid = "<LogAnalyticsWorkspaceId>"
$sharedkey="<LogAnalyticsWorkspaceSaredKey>"
import-module maintenance.psm1 -ArgumentList $workspaceid, $sharedkey -force -verbose 
$datenow = (Get-Date).ToUniversalTime()
Write-Output "Starting VM Maintenance Log for $datenow"
$maintenancetag = 'maintenance'
$n = publish-azvmmaintenance $maintenancetag
Write-Output "$n VMs in maintenance"  