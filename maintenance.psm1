param(
	[parameter(Position=3,Mandatory=$true)][string]$WorkspaceId,
	[parameter(Position=4,Mandatory=$true)][string]$SharedKey

)


function Show-Param {
	Write-Output "Workspace ID: $WorkspaceId"
	Write-Output "SharedKey: $SharedKey"	
}

#Region Azure VM
function Get-AzVmTagValue($tagname){
   $vms = @()
   get-azvm | ForEach-Object {
       $vmname = $_.Name
       $tagvalue = $_.Tags[$tagname]
       if($null -ne $tagvalue){
        $object = [PSCustomObject]@{
            VmName = $vmname
            TagValue = $tagvalue
        }
        $vms += $object         
       }     
   }
   $vms
}

# Sunday = 0
# Usage:
# Example #1: to query the 2nd Tuesday of October 2012:
# Get-WeekDayInMonth –month 10 –year 2012 –Weeknumber 2 –Weeday 2
# Get-WeekDayInMonth 10 2012 2 2
function Get-WeekDayInMonth ([int]$Month, [int]$year, [int]$WeekNumber, [int]$WeekDay)
{
    $FirstDayOfMonth = Get-Date -Year $year -Month $Month -Day 1 -Hour 0 -Minute 0 -Second 0
    #First week day of the month (i.e. first monday of the month)
    [int]$FirstDayofMonthDay = $FirstDayOfMonth.DayOfWeek
    $Difference = $WeekDay - $FirstDayofMonthDay
    If ($Difference -lt 0)
    {
    $DaysToAdd = 7 - ($FirstDayofMonthDay - $WeekDay)
    } elseif ($difference -eq 0 )
    {
    $DaysToAdd = 0
    }else {
    $DaysToAdd = $Difference
    }
    $FirstWeekDayofMonth = $FirstDayOfMonth.AddDays($DaysToAdd)
    Remove-Variable DaysToAdd
    #Add Weeks
    $DaysToAdd = ($WeekNumber -1)*7
    $TheDay = $FirstWeekDayofMonth.AddDays($DaysToAdd)
    If (!($TheDay.Month -eq $Month -and $TheDay.Year -eq $Year))
    {
    $TheDay = $null
    }
    $TheDay
}

function Convert-DayToNumber([string]$day){
    switch($day) {
        "sun" {0}
        "mon" { 1 } 
        "tue" {2}
        "wed" {3}
        "thu" {4}
        "fri" {5}
        "sat" {6}
        "default"  {99}        
     }
}
function Assert-AzVmInMaintenance{
    param(
        # mstr in the format mo-xddd-hhmm-hhmm-w
        [Parameter(Mandatory=$true)][string]$mtnstr,
        # optional parameter = process offset in minutes. Time in advance that will allow for Automation Job Queuing/Completion and Log Anaytics publishing
        # default value is 10
        [Parameter(Mandatory=$false)][int]$processoffset,
        # optional parameter = date to test for maintenance window
        # default value is now()
        [Parameter(Mandatory=$false)][datetime]$thedate        
    )
    if(!($thedate)){
        # getting current date in UTC as testing date
        $thedate = (Get-Date).ToUniversalTime()
    }
    if(!($processoffset)){
        $processoffset = 10
    }
    $thedate = $thedate.AddMinutes($processoffset)
    $parts = $mtnstr.split("-")
    $strday = $parts[1].Substring(1,3)
    # configured maintenance: day, index, year and month:
    $day = Convert-DayToNumber($strday)
    $nday = [int]($parts[1].Substring(0,1))
    # using test date year and month because the maintenance string applies for all years and all months
    $year = $thedate.Year
    $month = $thedate.Month    
    # maintenance day of the current month
    $mday = (get-weekdayinmonth $month $year $nday $day)
    # is today maintenance day?
    if($mday.day -eq $thedate.Day){
        # it is maintenace day!           
        $strfrom = $parts[2]
        $strto = $parts[3]
        $fromhour = [int]$strfrom.Substring(0,2)
        $frommin = [int]$strfrom.Substring(2,2)
        $tohour = [int]$strto.Substring(0,2)
        $tomin = [int]$strto.Substring(2,2)        
        # is it after the start of scheduled maintenance?
        if(($thedate.Hour -gt $fromhour) -or ($thedate.Hour -eq $fromhour -and $thedate.Minute -ge $frommin)){            
            # is it also before the end of scheduled maintenance?
            if(($thedate.Hour -lt $tohour) -or ($thedate.Hour -eq $tohour -and $thedate.Minute -le $tomin)){                
                #it is maintenance time!
                return $true
            }
        }
    }        
    # it is not maintenance time
    return $false
}

function Publish-AzVmMaintenance([string] $tagValue){
    $count = 0
    $datenow = (Get-Date).ToUniversalTime()
    $vms = @()
    Get-AzVmTagValue $tagValue | foreach-object {  
        if(Assert-AzVmInMaintenance($_.TagValue)){ 
            $vm = new-object psobject -property @{ 
                "Computer" = $_.VmName  
                "DateValue"= $datenow
                "TagValue" = $_.TagValue
                "MaintenanceType" = "scheduled"            
            }  
            $vms+=$vm
            $count += 1
        } 
    }    
    if($count -gt 0){
        $json = $vms | ConvertTo-Json
        Add-AzMonLogData $json "MaintenanceVM" "DateValue"
    }    
    return $count
}

function Add-AzVmMaintenance([string] $vmname){
    $datenow = (Get-Date).ToUniversalTime()
    $vm = new-object psobject -property @{ 
        "Computer" = $vmname  
        "DateValue"= $datenow        
        "MaintenanceType" = "ondemand"            
    }  
    $json = $vm | ConvertTo-Json
    Add-AzMonLogData $json "MaintenanceVM" "DateValue"
}

#EndRegion

#Region Blobs
function Update-BlobFromArray([string]$storageaccountname, [string]$key, [string]$container, [string]$blobname,[string[]]$lines){
    $text=""    
    foreach($line in $lines){
        $text+=($line+"`r`n");        
    }
    Update-BlobFromText $storageaccountname $key $container $blobname $text
}

function Update-BlobFromText([string]$storageaccountname, [string]$key, [string]$container,[string]$blobname, [string]$text){
    write-host "key=" $key
    $text | out-file "temp" -force    
    $ctx = new-azstoragecontext -storageaccountname $storageaccountname -storageaccountkey $key
    Set-AzStorageBlobContent -file "temp" -container $container -blob $blobname -context $ctx -force
}
#EndRegion

#Region AzMonLogs
Function New-AzLogsSignature($date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $WorkspaceId,$encodedHash
    return $authorization
}

# This is just a test/debug function that logs a message
function Add-AzMonLogEntry([string]$message, [string]$logType){
	$thedate = "{0:s}" -f (get-date) + "Z"     
	$request = new-object psobject -property @{ 
		"Message" = $message   
		"DateValue"= $thedate
	} | convertto-json 
	Add-AzMonLogData $request $logType "DateValue"
}
Function Add-AzMonLogData($json, $logType, $TimeStampField)
{
	$body = [System.Text.Encoding]::UTF8.GetBytes($json)
	
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $thedate = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = New-AzLogsSignature -date $thedate -contentLength $contentLength -method $method -contentType $contentType -resource $resource
	$stringuri = "https://" + $WorkspaceId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $uri = [System.Uri]$stringuri
	
    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $thedate;
        "time-generated-field" = $TimeStampField;
    }	
    Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    #return $response.StatusCode

}
#Endregion


export-modulemember -function Add-AzMonLogData 
export-modulemember -function Add-AzMonLogEntry
export-modulemember -function Update-BlobFromText
export-modulemember -function Update-BlobFromArray
export-modulemember -function Assert-AzVmInMaintenance
export-modulemember -function Get-AzVmTagValue
export-modulemember -function Show-Param
export-modulemember -function Publish-AzVmMaintenance
export-modulemember -function Add-AzVmMaintenance
export-modulemember -function Convert-DayToNumber
export-modulemember -function Get-WeekDayInMonth