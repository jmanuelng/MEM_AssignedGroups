<#

.SYNOPSIS
    Gets list of AzureAD groups that have Intune assignments.

.DESCRIPTION
    Script will get a list of all AzureAD groups and look for Intune assginments, 
    it will then create a report file with the list of all groups found with assignments.

    Original script from Timmy Andersson (@TimmyITdotcom), described in the following blog:
    https://timmyit.com/2019/12/04/get-all-assigned-intune-policies-and-apps-per-azure-ad-group/


.NOTES

    To do:
        - Complete to get endpoint security, baseline and other sources of assignments
        - Make it faster
        - Review work from Ondrej Sebela: https://doitpsway.com/get-all-intune-policies-assigned-to-the-specified-account-using-powershell

#>

#Region Settings

$CurrentTime = [System.DateTimeOffset]::Now
$ExportCSV=".\MEM_AssignedGroups_" + $hours + "h_$((Get-Date -format yyyy-MMM-dd-ddd` hh-mm` tt).ToString()).csv"

#Endregion Settings

#Region GraphConnect
# Connect and change schema 

Connect-MSGraph -ForceInteractive
Update-MSGraphEnvironment -SchemaVersion beta
Connect-MSGraph

$Groups = Get-AADGroup | Get-MSGraphAllPages

#Endregion GraphConnection


#Region Main

Foreach ($Group in $Groups) {
    
    # Results Arrays
    $appsArray = @()
    $complianceArray = @()
    $configurationArray = @()
    $psscriptsArray = @()
    $admtemplatesArray = @()
    $result = 0

    Write-host "AAD Group Name: $($Group.displayName)" -ForegroundColor Green
    
    # Apps
    $AllAssignedApps = Get-IntuneMobileApp -Filter "isAssigned eq true" -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "`tNumber of Apps found: $($AllAssignedApps.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllAssignedApps) {
        
        Write-host "`t`t $($Config.displayName)" -ForegroundColor Yellow

        $appsArray += $Config.displayName
        $result = 1

    }
    
    
    # Device Compliance
    $AllDeviceCompliance = Get-IntuneDeviceCompliancePolicy -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "`tNumber of Device Compliance policies found: $($AllDeviceCompliance.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllDeviceCompliance) {
        
        Write-host "`t`t $($Config.displayName)" -ForegroundColor Yellow

        $complianceArray += $Config.displayName
        $result = 1    
        
    }
    
    
    # Device Configuration
    $AllDeviceConfig = Get-IntuneDeviceConfigurationPolicy -Select id, displayName, lastModifiedDateTime, assignments -Expand assignments | Where-Object {$_.assignments -match $Group.id}
    Write-host "`tNumber of Device Configurations found: $($AllDeviceConfig.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllDeviceConfig) {
        
        Write-host "`t`t $($Config.displayName)" -ForegroundColor Yellow

        $configurationArray += $Config.displayName
        $result = 1
        
    }
    
    # Device Configuration Powershell Scripts 
    $Resource = "deviceManagement/deviceManagementScripts"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=groupAssignments"
    $DMS = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllDeviceConfigScripts = $DMS.value | Where-Object {$_.assignments -match $Group.id}
    Write-host "`tNumber of Device Configurations Powershell Scripts found: $($AllDeviceConfigScripts.DisplayName.Count)" -ForegroundColor cyan
    
    Foreach ($Config in $AllDeviceConfigScripts) {
        
        Write-host "`t`t $($Config.displayName)" -ForegroundColor Yellow

        $psscriptsArray += $Config.displayName
        $result = 1
        
    }
    
    
    
    # Administrative templates
    $Resource = "deviceManagement/groupPolicyConfigurations"
    $graphApiVersion = "Beta"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=Assignments"
    $ADMT = Invoke-MSGraphRequest -HttpMethod GET -Url $uri
    $AllADMT = $ADMT.value | Where-Object {$_.assignments -match $Group.id}
    Write-host "`tNumber of Device Administrative Templates found: $($AllADMT.DisplayName.Count)" -ForegroundColor cyan
    Foreach ($Config in $AllADMT) {
        
        Write-host "`t`t $($Config.displayName)" -ForegroundColor Yellow

        $admtemplatesArray += $Config.displayName
        $result = 1
        
    }

    #If groups hast assignment, write it to CSV report
    if ($result -eq 1) {

        #Separate results with comma
        $reportApps = ($appsArray -join ", ")
        $reportCompliance = ($complianceArray -join ", ")
        $reportConfiguration = ($configurationArray -join ", ")
        $reportPsscripts = ($psscriptsArray -join ", ")
        $reportAdmtemplates = ($admtemplatesArray -join ", ")

        #Get all assignments results for a group to an object
        $Report = @{
            'Group' = $Group.displayName;
            'Applications' = $reportApps;
            'DeviceCompliance' = $reportCompliance;
            'DeviceConfiguration' = $reportConfiguration;
            'DeviceConfigurationScripts' = $reportPsscripts;
            'AdministrativeTemplates' = $reportAdmtemplates
        }

        #Inform progress on screen
        $activityMsg = "Exporting Microsoft Intune assginment details"
        $statusMsg = "... Assignment details for Group: " + $Group.displayName
        Write-Progress -Id 1 -Activity $activityMsg -Status $statusMsg

        $ReportCSV = New-Object PSObject -Property $Report

        #Export to file
        $ReportCSV | Select-Object Group,Applications,DeviceCompliance,DeviceConfiguration,DeviceConfigurationScripts,AdministrativeTemplates | Export-Csv -Path $ExportCSV -Encoding utf8 -Notype -Append

    }

 
}

#Endregion Main