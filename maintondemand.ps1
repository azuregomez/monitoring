 
#param
param(
    [Parameter (Mandatory = $true)]
    [object]$WebhookData        
 )
 if ($null -ne $WebhookData) {
         $WebhookBody = $WebHookData.RequestBody
         $input = (ConvertFrom-Json -InputObject $WebhookBody)    
         $vmname = $input.VmName    
         # dates
         [DateTime]$start = $input.StartDate 
         [DateTime]$end = $input.EndDate			                  
         $connectionName = "AzureRunAsConnection"
         try
         {
             # Get the connection "AzureRunAsConnection "
             $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
             "Logging in to Azure..."
             Add-AzureRmAccount `
                 -ServicePrincipal `
                 -TenantId $servicePrincipalConnection.TenantId `
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
        # This is where the work starts:
        $workspaceid = "<LogAnalyticsWorkspaceId>"
        $sharedkey="<LogAnalyticsWorkspaceSaredKey>"
        import-module maintenance.psm1 -ArgumentList $workspaceid, $sharedkey -force -verbose         
        Write-Output "Starting VM Maintenance Log for $datenow"
        Add-AzVmMaintenance $vmname $start $end
        Write-Output "$vmname in maintenance"  
     }
      else {
         Write-Error "Runbook to be started only from webhook."
     }
 