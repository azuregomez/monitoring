<h2>Basic Monitoring for Azure VMs</h2>
Azure Monitor provides many "out of the box" metrics that youy can use to monitor your VMs. However, when the requirements get more specific, we often have to use Kusto Queries.
<h2>Business Case</h2>
This repository provides a solution for the followin scenario: A company wants to use Azure Monitor and alerts for the following events:
<ol>
<li>Alert when a VM has high CPU utilization.  Filtered by Subscription and Resource Group.
<li>Alert when a VM has low memory.  Filtered by Subscription and Resource Group.
<li>Alert when a VM has low disk space.  Filtered by Subscription and Resource Group.
<li>Alert when a VM is down, the agent is  not reporting, or is generally unhealthy.  Filtered by Subscription and Resource Group.
</ol>
The solution requires to have the VMs enrolled to a Log Analytics workspace and leverages the query capabilities of Azure Monitor Logs (aka Log Analytics).
https://docs.microsoft.com/en-us/azure/azure-monitor/log-query/logs-structure

CPU High

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
| where sub == "f05bd3e7-fe83-40ae-9dec-7f146792b60d" and rg == 'panpoc-rg'
| summarize AggregatedValue = avg(CounterValue) by tostring(sub), tostring(rg), bin(TimeGenerated, 5m), Computer
