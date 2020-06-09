# Generated by: Kenichiro Nakamura (kenakamu)
#
# Copyright © Microsoft Corporation.  All Rights Reserved.
# This code released under the terms of the 
# Microsoft Public License (MS-PL, http://opensource.org/licenses/ms-pl.html.)
# Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment. 
# THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
# INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. 
# We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that. 
# You agree: 
# (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; 
# (ii) to include a valid copyright notice on Your software product in which the Sample Code is embedded; 
# and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code 

Connect-CrmOnlineDiscovery -InteractiveMode

# Get all QuickFind views (query type of 4)

$views = Get-CrmRecords -EntityLogicalName savedquery -FilterAttribute querytype -FilterOperator eq -FilterValue 4 -Fields name,fetchxml,returnedtypecode

$results = New-Object System.Collections.Generic.List[string]

foreach($view in $views.CrmRecords)
{
    $entityname = $view.returnedtypecode
    $xml = [xml]$view.fetchxml
    $filters = $xml.fetch.entity.filter.condition | ? value -eq "{0}"
    $int = 0
    foreach($filter in $filters)
    {
        # if you want to generate fields detail, do it here.
        $int++
        if($filter.attribute -contains "composite")
        {
            Write-Host $entityname has $filter.attribute
        }
    }
    
    $results.Add("$entityname has $int search fields.")   
}

$results.Sort()
$results