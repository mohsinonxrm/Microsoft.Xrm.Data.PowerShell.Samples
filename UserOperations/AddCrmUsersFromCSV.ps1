﻿#requires -module PowerShellGet
# Generated by: Sean McNellis (seanmcn)
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
param
(
  [string]$ServerUrl = 'http://yourServer:80',
  [string]$OrganizationName = 'YourOrg',
  [Parameter(Mandatory = $true)]
  [pscredential]$AdminUserCredentials = (Get-Credential),
  [string]$csvPath = ".\AddCrmUsersFromCSV.csv",
  [switch]$CreateActiveDirUsers
)
Function New-ADUserFromCsv
{
    param
    (   
        [PSObject]$User
    )

    $userIdentity = $User.Identity

    Write-Output "Retrieve AD User $userIdentity" 
    $adUser = Get-ADUser -Identity $userIdentity
    
    If($adUser -ne $null)
    {

    }
    Else
    {
        Write-Output "Creating User $userIdentity to AD" 

        $changePasswordAtLogon = If($User.ChangePasswordAtLogon -eq 'true') { $true } Else { $false }
        $passwordNeverExpires = If($User.PasswordNeverExpires -eq 'true') { $true } Else { $false }
        
        New-AdUser -Name $User.Identity -SamAccountName $User.Identity -UserPrincipalName $User.UserPrincipalName `
        -DisplayName $User.DisplayName -GivenName $User.GivenName -SurName $User.SurName -HomePhone $User.PhoneNumber `
        -MobilePhone $User.MobilePhone -PostalCode $User.PostalCode -City $User.City `
        -Country $User.Country -State $User.State -StreetAddress $User.StreetAddress `
        -Title $User.Title -Department $User.Department -Office $User.Office -Fax $User.Fax `
        -AccountPassword (ConvertTo-SecureString -String $User.Password -AsPlainText -Force) `
        -ChangePasswordAtLogon $changePasswordAtLogon `
        -PasswordNeverExpires $passwordNeverExpires

        Write-Output "Enabling User $userIdentity" 
        Enable-ADAccount -Identity $User.Identity
    }
}

Function Create-CrmUser
{
    param
    (   
        [PSObject]$User
    )

    $businessUnitName = $User.BusinessUnitName
    $domainName = $User.DomainName

    $businessUnit = Get-CrmRecords -EntityLogicalName businessunit -FilterAttribute name -FilterOperator eq -FilterValue $businessUnitName -Fields businessunitid
    
    If($businessUnit.CrmRecords.Count -eq 0)
    {
        Write-Error "Business Unit $businessUnitName does not exist"
        return
    }
    Else
    {
        $businessUnitId = $businessUnit.CrmRecords[0].businessunitid.Guid
        $User.BusinessUnitId = $businessUnitId

        $crmUser = Get-CrmRecords -EntityLogicalName systemuser -FilterAttribute domainname -FilterOperator eq -FilterValue $domainName -Fields domainname,isdisabled
    
        If($crmUser.CrmRecords.Count -eq 0)
        {
            Write-Output "Creating CRM User $domainName"

            $systemUserId = New-CrmRecord -EntityLogicalName systemuser `
            -Fields @{"domainname"=$User.DomainName;"firstname"=$User.GivenName;`
            "lastname"=$User.SurName;"businessunitid"=(New-CrmEntityReference -EntityLogicalName businessunit -Id $businessUnitId);`
            "homephone"=$User.HomePhone;"mobilephone"=$User.MobilePhone;"address1_postalcode"=$User.PostalCode;`
            "address1_city"=$User.City;"address1_country"=$User.Country;"address1_stateorprovince"=$User.State;`
            "address1_line1"=$User.StreetAddress;"jobtitle"=$User.Title}

            $User.SystemUserId = $systemUserId            
        }
        Else
        {
            If($crmUser.CrmRecords[0].isdisabled_Property.Value -eq $False)
            {
                Write-Output "CRM User $domainName already exists"
                $User.SystemUserId = $crmUser.CrmRecords[0].systemuserid.Guid
            }
            Else
            {
                Write-Output "CRM User $domainName already exists but disabled state"
            }
        }
    }    
}

Function Assign-CrmUserSecurityRole
{
    param
    (   
        [PSObject]$User
    )

    $domainName = $User.DomainName
    $securityRoleName = $User.SecurityRoleName
    $systemUserId = $User.SystemUserId
    $businessUnitId = $User.BusinessUnitId

    $fetch = @"
<fetch version="1.0" output-format="xml-platform" mapping="logical" distinct="false" no-lock="true">
  <entity name="role">
    <attribute name="roleid" />
    <filter type="and">
      <condition attribute="name" operator="eq" value="{0}" />
      <condition attribute="businessunitid" operator="eq" value="{1}" />
    </filter>
  </entity>
</fetch>
"@

    $fetch = $fetch -F $securityRoleName, $businessUnitId

    $securityRole = Get-CrmRecordsByFetch -Fetch $fetch

    If($securityRole.CrmRecords.Count -eq 0)
    {
        Write-Error "SecurityRole $securityRoleName does not exist"
        return
    }
    Else
    {
        #get the record where this user is in the Admin Cobject
        $adminObject = Get-CrmRecords -conn $conn -EntityLogicalName systemuser -FilterOperator eq -FilterAttribute domainname -FilterValue "$($domainname)" -Fields domainname,fullname
        #get the guid for the user
        $adminId = (($adminObject | Where-Object {$_.keys -eq "crmRecords"}).values).systemuserid.guid
        #get the role object
        $adminRoleObject = Get-CrmUserSecurityRoles -conn $conn -UserId $adminId | Where-Object {$_.rolename -eq  $securityRoleName}
        $adminroles = ($adminRoleObject).roleid.guid
        $adminRoleName =  $adminroleobject.rolename
        if($adminRoleName -eq $securityRoleName)
        {
            Write-Output "$domainname is already in the role: $securityRoleName"
        }
        else
        {
            Write-Output "Assign $securityRoleName role to $domainName"
            $securityRoleId = $securityRole.CrmRecords[0].roleid.Guid
            Add-CrmSecurityRoleToUser -UserId $systemUserId -SecurityRoleId $securityRoleId
        }

    }    
}

# Script parameters #
$loadedandCorrectVersion = (get-command -module 'Microsoft.Xrm.Data.Powershell' -ErrorAction Ignore).version -eq '2.5'
if(-not $loadedandCorrectVersion)
{
  find-module -Name Microsoft.Xrm.Data.Powershell -MinimumVersion 2.5 -MaximumVersion 2.5 | Install-Module -Scope CurrentUser -AllowClobber -Force
  Import-Module -Name Microsoft.Xrm.Data.Powershell -MinimumVersion 2.5 -MaximumVersion 2.5 -Force -RequiredVersion 2.5
}
if(get-command -module 'Microsoft.Xrm.Data.Powershell')
{
    $crmAdminUser =$AdminUserCredentials.UserName
    Write-Output "Connecting to CRM OnPremise as $crmAdminUser"
    $crmCred = $AdminUserCredentials
    Try
    {
        # Refer to https://msdn.microsoft.com/en-us/library/dn756303.aspx for more detail 
        $global:conn = Get-CrmConnection -OrganizationName $organizationName -ServerUrl $serverUrl -Credential $crmCred -ErrorAction Stop
    }
    Catch
    {
        throw 
    }

    Write-Output "Loading User CSV File $csvpath"
    if(Test-Path $csvPath)
    {
        $users = Import-Csv -Path $csvPath
        foreach($user in $users)
        {
           if(get-aduser -identity $User.Identity -ErrorAction SilentlyContinue)
           {
             $u = get-aduser -Identity $user.identity -Properties ('displayname', 'emailaddress', 'givenName','Title','telephoneNumber','surname','StreetAddress','state','city','co','mobilephone', 'PostalCode','Department')
             $user.City = $u.city
             $user.givenname = $u.Surname
             $user.HomePhone = $u.telephoneNumber
             $user.MobilePhone = $u.mobilephone
             $user.City = $u.city
             $user.Country = $u.co
             $User.StreetAddress = $u.StreetAddress
             $user.State = $u.state
             $user.Title = $u.title
             $user.PostalCode = $u.PostalCode
             $User.Department = $u.department
            }
            elseif($CreateActiveDirUsers)
            {
				#create new array if switch is thrown for the new-aduserfromcsv to create.
				$adUsers2Create +=$user
            }
			else
			{
				Write-Warning "$($user.Identity) wasn't found in Active Directory"
				Write-Warning "Removing this user: $($user.Identity) from users to add to CRM"
				$users = $users |  Where-Object {$_ -ne $user}
			}
        }
		if($CreateActiveDirUsers)
		{
			Write-Output "Creating AD User and Enable it"
			$adUsers2Create | ForEach-Object {New-ADUserFromCsv -User $_ }
		}
        Write-Output "Create Crm User on Dynamics CRM OnPremise"
        $users | ForEach-Object {Create-CrmUser -User $_}

        Write-Output "Assign Security Role to Crm User"
        $users | ForEach-Object {Assign-CrmUserSecurityRole -User $_}

        Write-Output "Completed"
    }
    else
    {
        Write-Output "$csvPath doesn't exist check input"
    }
}
else
{ throw "cannot load the powershell module 'Microsoft.Xrm.Data.Powershell'"}
