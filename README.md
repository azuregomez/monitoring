<h2>Custom Monitoring for Azure VMs with Azure Monitor Logs</h2>
Azure Monitor provides many "out of the box" metrics that you can use to monitor your VMs. However, when the requirements get more specific, we often have to use Kusto Queries.
<h3>Business Case</h3>
This repository provides a solution for the following scenario: <br/>
A company wants to use Azure Monitor and alerts for the following events:
<ol>
<li>Alert when a VM has high CPU utilization. Over 90% for 5 minutes.  Filtered by Subscription and Resource Group.
<li>Alert when a VM has low memory. Less than 200MB available for 5 minutes. Filtered by Subscription and Resource Group.
<li>Alert when a VM has low disk space. Less that 10% Available.  Filtered by Subscription and Resource Group.
<li>Alert when a VM is down, the agent is not reporting, or is generally unhealthy for a period of 5 minutes.  Filtered by Subscription and Resource Group.
</ol>
The alerts must exclude a list of VMs that are under a maintenance window. Each VM may have a different maintenance window <br/>
The maintenance window is specified in VM tag 'maintenance' with the format "zz-xddd-hhmm-HHMM-", where:
<table>
<tr><td>zz</td><td>Not used for alerting Purpose</td></tr>
<tr><td>x</td><td>n-th weekday of the month when maintenance is performed every month. As in 3rd Wednesday, x=3</td></tr>
<tr><td>ddd</td><td>First 3 letters of the weekday when maintenance is performed</td></tr>
<tr><td>hh</td><td>Hour of the day when maintenance starts</td></tr>
<tr><td>mm</td><td>Hour of the day when maintenance starts</td></tr>
<tr><td>HH</td><td>Hour of the day when maintenance ends</td></tr>
<tr><td>MM</td><td>Hour of the day when maintenance ends</td></tr>
<tr><td>Z</td><td>Not used for alerting purpose</td></tr>
</table>
This way, a VM with scheduled maintenance every 2nd Tuesday of the month from 10PM to 11:30PM, would have the 'maintenance' tag value "zz-2tue-1000-1130-w"<br/>
ALL TIMES TIMES ARE IN UTC. <br/>
In addition to having scheduled maintenance, it is desirable to be able to put a VM under maintenance alert excemption on demand. This way any VM can be temporarily removed from the alerts at any time for an indefinite period of time (not implemented in the solution yet).
<h3>Solution</h3>
<ol>
<li>Azure Automation Runbook scheduled to run every hour to:
<ul>
<li>Query VM Tag "maintenance" and determine the list of VMs that will be in maintenence in the next hour. The runbook will run 10 minutes before each hour (0:50, 1:50, 2:50) and will run 10 minutes ahead for determining maintenance VMs. This way it will scoop the right VMs in the right maintenance window and allow 10 minutes for Az Automation job queuing, job completion, and Log Analytics record ingestion.  The end result will be that alerts will stop just a few minutes before the actual maintenance time.
<li>Send the list of VMs to a Custom Table in Log Analytics. The table is named MaintenanceVM_CL.
</ul>
<li>Kusto queries for alerts joining the MaintenanceVM_CL custom table on Computer, taking into account the new maintenance records for the last hour so those VMs can be excluded from the query results.  
</ol>
<h3>Solution Components</h3>
<table>
<tr><td>maintenance.psm1</td><td>Powershell module to be uploaded to your Azure Automation Account. This code is used by the Automation runbook</td></tr>
<tr><td>maintondemand.ps1</td><td>Automation runbook to be uploaded and scheduled every hour at the 50 min offset. Workspace Id and Shared Key need to be updated with your Log Analytics info.</td></tr>
<tr><td>Log Analytics Alerts</td><td>The code for the queries is provided below in the section Alert Implementation with Kusto Queries. The subscription id and resource group need to be updated with your values.</td></tr>
</table>
<h3>Limitations</h3>
<ul>
<li>The solution works as long as every VM in the organization has a different name.  Good naming standards are a best practice.  Any collision with VM names would adversely affect this implementation.  A potential solution to this issue is to use resourceId instead of VM Name
<li>The 'maintenance' tag requires the use of UTC. This is for code simplification and the fact that Log Analytics uses UTC times. Azure runs in UTC so your Azure operations should too.
</ul>
<h3>Pre-requisites</h3>
<ul>
<li>A Log Analytics Workspace.
<li>All VMs that will be monitored have to be enrolled in the Workspace
</ul>
<hr>
<h3>Alert Implementation with Kusto Queries</h3>
Go to Azure Monitor > Alerts<br/>
For each Alert:
<ol>
<li>Click on New Alert Rule
<li>Click on Resource "Select" Button.
<li>Filter by resource type "Log Analytics Workspaces" and select the Workspace.<br/>
<img src="https://storagegomez.blob.core.windows.net/public/images/alertrule.png"/>
<li>Click on Condition "Add" button and Select Custom log search as Signal Name<br/>
<img src="https://storagegomez.blob.core.windows.net/public/images/customlogsearch.png"/>
<li>Configure the Kusto query as described below for each case.
<li>Configure Actions
<li>Click on Create Alert Rule
</ol>

<h3>CPU High</h3>

```
let get_rg = (s:string)
{
split((s), "/", 4)
};
let get_sub = (s:string)
{
split((s), "/", 2)
};
Perf
| extend rg = get_rg(_ResourceId)[0]
| extend sub = get_sub(_ResourceId)[0]
| where ObjectName == 'Processor' and CounterName == '% Processor Time'
| where sub == '<subscriptionid>' and rg == '<resourcegroup>'
| where TimeGenerated >= now(-10m)
| summarize AggregatedValue = avg(CounterValue) by tostring(sub), tostring(rg), bin(TimeGenerated, 5m), Computer
| join kind= leftouter(
    MaintenanceVM_CL 
    | where TimeGenerated >= now(-1h) 
) on Computer
| where MaintenanceType_s == ""

```
<img src="https://storagegomez.blob.core.windows.net/public/images/cpuhigh.png"/>

<h3>Low Memory</h3>

```
let get_rg = (s:string)
{
split((s), "/", 4)
};
let get_sub = (s:string)
{
split((s), "/", 2)
};
Perf
| extend rg = get_rg(_ResourceId)[0]
| extend sub = get_sub(_ResourceId)[0]
| where ObjectName == 'Memory' and CounterName == 'Available MBytes' 
| where sub == '<subscriptionid>' and rg == '<resourcegroup>'
| where TimeGenerated >= now(-10m)
| summarize AggregatedValue = avg(CounterValue) by tostring(sub), tostring(rg), bin(TimeGenerated, 5m), Computer
| join kind= leftouter(
    MaintenanceVM_CL 
    | where TimeGenerated >= now(-1h) 
) on Computer
| where MaintenanceType_s == ""

```
<img src="https://storagegomez.blob.core.windows.net/public/images/memlow.png"/>

<h3>Low Disk Space</h3>

```
let get_rg = (s:string)
{
split((s), "/", 4)
};
let get_sub = (s:string)
{
split((s), "/", 2)
};
Perf
| extend rg = get_rg(_ResourceId)[0]
| extend sub = get_sub(_ResourceId)[0]
| extend Drive = strcat(Computer, ' - ', InstanceName)
| where ObjectName == "LogicalDisk" or ObjectName == "Logical Disk"
| where CounterName == "% Free Space"
| where InstanceName <> "_Total"
| where sub == '<subscriptionid>' and rg == '<resourcegroup>'
| where TimeGenerated >= now(-10m)
| summarize AggregatedValue = avg(CounterValue) by Computer, Drive, bin(TimeGenerated, 5m)
| join kind= leftouter(
    MaintenanceVM_CL 
    | where TimeGenerated >= now(-1h) 
) on Computer
| where MaintenanceType_s == ""

```
<img src="https://storagegomez.blob.core.windows.net/public/images/disklow.png"/>

<h3>VM Down</h3>

```
let utc_to_us_date_format = (t:datetime)
{
strcat(getmonth(t), "/", dayofmonth(t),"/", getyear(t), " ",
bin((t-1h)%12h+1h,1s), iff(t%24h<12h, " AM UTC", " PM UTC"))
};
Heartbeat
| where TimeGenerated < now()
| where SubscriptionId == '<subscriptionid>' and ResourceGroup == '<resourcegroup>'
| summarize TimeGenerated=max(TimeGenerated) by Computer
| project TimeGenerated, Computer
| extend localtimestamp = utc_to_us_date_format(TimeGenerated)
| extend LastHeartbeat = localtimestamp
| summarize AggregatedValue = count() by Computer, LastHeartbeat, TimeGenerated
| where TimeGenerated < ago(5m)
| join kind= leftouter(
    MaintenanceVM_CL 
    | where TimeGenerated >= now(-1h) 
) on Computer 
| where MaintenanceType_s == ""

```
<img src="https://storagegomez.blob.core.windows.net/public/images/vmdown.png"/>

<hr>

Filtering by Subscription and Resource Group allows to:
<ul>
<li>Share the same Azure Monitor Logs Workspace bewteen subscriptions a nd resource groups.  It is a good practice to keep the number of workspaces as low as posible.
<li>Configure different alert signal tresholds for different resource groups taht can map to environment and application.
<li>Configure different action groups for different Resource Groups.
</ul>
Ultimately, if the Subscription or Resource Group filter is not useful for the reader, this can be removed from the Kusto Query.
<hr>
Acknowledgements<br/>
This repo and the solution presented here would not be possible without the awesome guidance from <a href="https://github.com/rkuehfus">Rob Kuehfus</a> and <a href="https://github.com/sbkuehn">Shannon Kuehn</a>
<hr>
References:
https://docs.microsoft.com/en-us/azure/azure-monitor/log-query/logs-structure
