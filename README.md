<h2>Basic Monitoring for Azure VMs</h2>
Azure Monitor provides many "out of the box" metrics that youy can use to monitor your VMs. However, when the requirements get more specific, we often have to use Kusto Queries.
This repo and the solution presented here would not be possible without the awesome help from Rob Kuehfus https://github.com/rkuehfus and Shannon Kuehn https://github.com/sbkuehn
<h2>Business Case</h2>
This repository provides a solution for the followin scenario: A company wants to use Azure Monitor and alerts for the following events:
<ol>
<li>Alert when a VM has high CPU utilization. Over 90% for 5 minutes.  Filtered by Subscription and Resource Group.
<li>Alert when a VM has low memory. Less than 200MB available for 5 minutes. Filtered by Subscription and Resource Group.
<li>Alert when a VM has low disk space. Less that 10% Available.  Filtered by Subscription and Resource Group.
<li>Alert when a VM is down, the agent is not reporting, or is generally unhealthy for a period of 5 minutes.  Filtered by Subscription and Resource Group.
</ol>
The solution requires to have the VMs enrolled to a Log Analytics workspace and leverages the query capabilities of Azure Monitor Logs (aka Log Analytics). <br/>
https://docs.microsoft.com/en-us/azure/azure-monitor/log-query/logs-structure

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
| summarize TimeGenerated=max(TimeGenerated) by Computer
| where TimeGenerated < ago(5m)
| project TimeGenerated, Computer
| extend localtimestamp = utc_to_us_date_format(TimeGenerated)
| extend HostName = strcat(Computer, ' - Last Heartbeat: ', localtimestamp)
| summarize AggregatedValue = count() by HostName, TimeGenerated
```
<img src="https://storagegomez.blob.core.windows.net/public/images/vmdown.png"/>
