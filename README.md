<h2>Basic Monitoring for Azure VMs</h2>
Azure Monitor provides many "out of the box" metrics that youy can use to monitor your VMs. However, when the requirements get more specific, we often have to use Kusto Queries.
This repo and the solution presented here would not be possible without the awesome help from <a href="https://github.com/rkuehfus">Rob Kuehfus</a> and <a href="https://github.com/sbkuehn">Shannon Kuehn</a>
<h2>Business Case</h2>
This repository provides a solution for the following scenario: A company wants to use Azure Monitor and alerts for the following events:
<ol>
<li>Alert when a VM has high CPU utilization. Over 90% for 5 minutes.  Filtered by Subscription and Resource Group.
<li>Alert when a VM has low memory. Less than 200MB available for 5 minutes. Filtered by Subscription and Resource Group.
<li>Alert when a VM has low disk space. Less that 10% Available.  Filtered by Subscription and Resource Group.
<li>Alert when a VM is down, the agent is not reporting, or is generally unhealthy for a period of 5 minutes.  Filtered by Subscription and Resource Group.
</ol>
The alerts must exclude a list of VMs that are under a maintenance window.  For this purpose, we will have a list of VM Names in a blob with 1 VM Name per line.  The blob is mainenance.txt.
The solution requires to have the VMs enrolled to a Log Analytics workspace and leverages the query capabilities of Azure Monitor Logs (aka Log Analytics). <br/>
https://docs.microsoft.com/en-us/azure/azure-monitor/log-query/logs-structure

<h4>Pre-requisites</h4>
<ul>
<li>An Azure Monitor Logs (formerly known as Log Analytics) Workspace
<li>All VMs that will be monitored have to be enrolled in the Workspace
<ul>
<h4>Implementation</h4>
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
| where Computer !in (externaldata(vmname:string) [@"https://storagegomez.blob.core.windows.net/public/maintenance.txt"])
| summarize AggregatedValue = avg(CounterValue) by tostring(sub), tostring(rg), bin(TimeGenerated, 5m), Computer
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
| where Computer !in (externaldata(vmname:string) [@"https://storagegomez.blob.core.windows.net/public/maintenance.txt"])
| summarize AggregatedValue = avg(CounterValue) by tostring(sub), tostring(rg), bin(TimeGenerated, 5m), Computer
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
| where ObjectName == "LogicalDisk" or ObjectName == "Logical Disk"
| where CounterName == "% Free Space"
| where InstanceName <> "_Total"
| where sub == '<subscriptionid>' and rg == '<resourcegroup>'
| where Computer !in (externaldata(vmname:string) [@"https://storagegomez.blob.core.windows.net/public/maintenance.txt"])
| extend Drive = strcat(Computer, ' - ', InstanceName)
| summarize AggregatedValue = avg(CounterValue) by Drive, bin(TimeGenerated, 5m)
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
| where Computer !in (externaldata(vmname:string) [@"https://storagegomez.blob.core.windows.net/public/maintenance.txt"])
| summarize TimeGenerated=max(TimeGenerated) by Computer
| where TimeGenerated < ago(5m)
| project TimeGenerated, Computer
| extend localtimestamp = utc_to_us_date_format(TimeGenerated)
| extend HostName = strcat(Computer, ' - Last Heartbeat: ', localtimestamp)
| summarize AggregatedValue = count() by HostName, TimeGenerated
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


