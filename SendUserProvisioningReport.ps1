# USER PROVISIONING DIGEST REPORT
# Author: https://github.com/asmalser-msft
#
# - Reads all user account provisioning events from the Azure AD graph for a specificed time period, and emits a digest report.  
# - The digest report is written to a text file on the host system, and can also be sent over email using an Office365 email account
# - This script can be scheduled to run at any desired time interval using the Windows Task Scheduler
# - Requires an application entry and secret key to be registered in the Azure AD tenant where the provisioning events exist, as described at:
# https://docs.microsoft.com/en-us/azure/active-directory/active-directory-reporting-api-prerequisites-azure-portal
# - In additon, "oauth2AllowImplicitFlow":true must be set in the manifest for this application entry. For details, see:
# https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-application-manifest


# ----------------------------------
# Set constants
# ----------------------------------


$ClientID       = "---------- ENTER CLIENT APP ID ----------"       # Insert your application's Client ID, a Globally Unique ID (registered by Global Admin)
$ClientSecret   = "---------- ENTER CLIENT SECRET ----------"   # Insert your application's Client Key/Secret string
$tenantdomain   = "---------- ENTER VERIFIED TENANT DOMAIN ----------"    # AAD Tenant; for example, contoso.onmicrosoft.com

$sendEmail = $true       #set to $false to not send email and just write the report to a text file
$emailRecipients = "---------- ENTER EMAIL ADDRESS ----------", "---------- ENTER EMAIL ADDRESS ----------" #Comma-delimited recipient email addresses
$emailFrom = "---------- ENTER EMAIL ADDRESS OF SENDER ----------"
$emailUsername = "---------- ENTER O365 USERNAME OF SENDER ----------"
$emailPassword = "ENTER O365 PASSWORD OF SENDER"
$fileOutputPath = ""  #example: c:\reports; defaults to same folder as script

#Get a report for the last 24 hours by default. Use $fromDate and $toDate below to set the desired range
$date = (Get-Date).AddDays(-1) 
$dateFormated = $date.ToString("yyyy-MM-dd")
$fromDate = "{0:s}" -f $dateFormated + "T00:00:00Z"
$toDate = "{0:s}" -f $dateFormated + "T23:59:59Z"  

$loginURL       = "https://login.microsoftonline.com"     # AAD Instance, for example https://login.microsoftonline.com; Don't change if this for the public Microsoft Azure
$resource       = "https://graph.windows.net"             # Azure AD Graph API resource URI; Don't change if this is in the public Microsoft Azure


# ----------------------------------
# Reporting functions 
# ----------------------------------

function Get-AzureProvisioningAuditReportData
{
    param
    (
        [Parameter(Mandatory=$true)]
        $tenantDomain, #Format: domain.onmicrosoft.com, contoso.com, etc.
        $fromDate, #Format: 2017-05-29T14:33:50Z
		$toDate #Format: 2017-05-29T14:33:50Z
    )
	
	if($tenantDomain -eq $null)
    {
        Throw "Please enter your tenant domain (domain.onmicrosoft.com, contoso.com, etc.)"
    }
	
	if($fromDate -eq $null)
    {
        $fromDate = "{0:s}" -f (get-date).AddDays(-7) + "Z" # Default to 7 days in the past
    }
	
	if($toDate -eq $null)
    {
        $toDate = "{0:s}" -f (get-date) + "Z" # Default to now
    }
	
	# Create HTTP header, get an OAuth2 access token based on client id, secret and tenant domain
	$body       = @{grant_type="client_credentials";resource=$resource;client_id=$ClientID;client_secret=$ClientSecret}
	$oauth      = Invoke-RestMethod -Method Post -Uri $loginURL/$tenantdomain/oauth2/token?api-version=beta -Body $body
	if ($oauth.access_token -ne $null) { 
		$GraphAccessToken = $oauth.access_token
	}

	
	if($token -eq $null)
    {
        echo "OAUTH TOKEN IS NULL"
    }
	
	   
	# Parse audit report items
	$i=0
	$reportProperties = @{
		usersCreated = @()
		usersUpdated = @()
		usersDisabled = @()
		usersDeleted = @()
		userCreateErrors = @()
		userUpdateErrors = @()
		userDisableErrors = @()
		userDeleteErrors = @()
		fullEventDetails = @()
		fromDate = $fromDate
		toDate = $toDate
	}
	$reportData = new-object psobject -Property $reportProperties
	$headerParams = @{"Authorization"="Bearer $GraphAccessToken"}
	$url = "https://graph.windows.net/" + $tenantDomain + "/activities/audit?api-version=beta&`$filter=(category eq 'Sync' and activity eq 'Export' and activityDate gt " + $fromDate + " and activityDate lt " + $toDate + ")"

	# loop through each query page (1 through n)
	Do{
		# display each event on the console window
		# Write-Output $url
		$myReport = (Invoke-WebRequest -UseBasicParsing -Headers $headerParams -Uri $url)
		
	    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")
		$json = New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer
		$json.MaxJsonLength = 999999999
		$myReportContent = $json.DeserializeObject($myReport.Content)
		
		foreach ($event in ($myReportContent).value) {
			
			foreach ($detail in $event.additionalDetails) {
				if ($detail.name -eq "EventName") {
					$eventName = $detail.value
				}
			}
		
			if ($event.activityResultStatus -eq "Success") {
				if ($eventName -eq "EntryExportAdd") {
					$reportData.usersCreated += $event.activityResultDescription
				}
				if ($eventName -eq "EntryExportUpdate") {
					$reportData.usersUpdated += $event.activityResultDescription
				}
				if ($eventName -eq "EntryExportUpdateSoftDelete") {
					$reportData.usersDisabled += $event.activityResultDescription
				}
				if ($eventName -eq "EntryExportDelete") {
					$reportData.usersDeleted += $event.activityResultDescription
				}
			}			
			if ($event.activityResultStatus -eq "Failure") {
				if ($eventName -eq "EntryExportAdd") {
					$reportData.userCreateErrors += ($event.activityResultDescription -split ";")[0] #trim extended details
				}
				if ($eventName -eq "EntryExportUpdate") {
					$reportData.userUpdateErrors += ($event.activityResultDescription -split ";")[0] #trim extended details
				}
				if ($eventName -eq "EntryExportUpdateSoftDelete") {
					$reportData.userDisableErrors += ($event.activityResultDescription -split ";")[0] #trim extended details
				}
				if ($eventName -eq "EntryExportDelete") {
					$reportData.userDeleteErrors += ($event.activityResultDescription -split ";")[0] #trim extended details
				}
			}
			$reportData.fullEventDetails += $event 
		}
	
		$url = ($myReportContent).'@odata.nextLink'
		$i = $i+1
	} while($url -ne $null)
	
		#remove duplicates
		$reportData.usersCreated = $reportData.usersCreated | select -uniq | sort
		$reportData.usersUpdated = $reportData.usersUpdated | select -uniq | sort
		$reportData.usersDisabled = $reportData.usersDisabled | select -uniq | sort
		$reportData.usersDeleted = $reportData.usersDeleted | select -uniq | sort
		$reportData.userCreateErrors = $reportData.userCreateErrors | select -uniq | sort
		$reportData.userUpdateErrors = $reportData.userUpdateErrors | select -uniq | sort
		$reportData.userDisableErrors = $reportData.userDisableErrors | select -uniq | sort
		$reportData.userDeleteErrors = $reportData.userDeleteErrors | select -uniq | sort
	
		return $reportData
}

function Get-AzureProvisioningAuditReport
{
	param
    (
        $reportData #From Get-AzureProvisioningAuditReportData
    )
	
	if($reportData -eq $null)
    {
        $reportData = Script:Get-AzureProvisioningAuditReportData($null)
    }
	
        $countUsersCreated = @($reportData.usersCreated).length
	$countUsersUpdated = @($reportData.usersUpdated).length
	$countUsersDisabled = @($reportData.usersDisabled).length
	$countUsersDeleted = @($reportData.usersDeleted).length
	$countUserCreateErrors = @($reportData.userCreateErrors).length
	$countUserUpdateErrors = @($reportData.userUpdateErrors).length 
	$countUserDisableErrors = @($reportData.userDisableErrors).length 
	$countUserDeleteErrors = @($reportData.userDeleteErrors).length 
	$fromDate = $reportData.fromDate
	$toDate = $reportData.toDate
	
	#PowerShell bug fix
        if ($reportData.usersCreated.length -eq 0) { $countUsersCreated = 0 }
        if ($reportData.usersUpdated.length -eq 0) { $countUsersUpdated = 0 }
        if ($reportData.usersUDisabled.length -eq 0) { $countUsersDisabled = 0 }
        if ($reportData.usersDeleted.length -eq 0) { $countUsersDeleted = 0 }
        if ($reportData.userCreateErrors.length -eq 0) { $countUserCreateErrors = 0 }
        if ($reportData.userUpdateErrors.length -eq 0) { $countUserUpdateErrors = 0 }
        if ($reportData.userDisableErrors.length -eq 0) { $countUserDisableErrors = 0 }
        if ($reportData.userDeleteErrors.length -eq 0) { $countUserDeleteErrors = 0 }

	$report =  "--------------------------------`r`n"
	$report +=  "SUMMARY `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "From '$fromDate' to '$toDate' `r`n"
	$report +=  "Users created: $countUsersCreated `r`n"
	$report +=  "Users updated: $countUsersUpdated `r`n"
	$report +=  "Users disabled: $countUsersDisabled `r`n"
	$report +=  "Users deleted: $countUsersDeleted `r`n"
	$report +=  "User creation failures: $countUserCreateErrors `r`n"	
	$report +=  "User update failures: $countUserUpdateErrors `r`n"
	$report +=  "User disable failures: $countUserDisableErrors `r`n"
	$report +=  "User delete failures: $countUserDeleteErrors `r`n"
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USERS CREATED `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.usersCreated)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USERS UPDATED `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.usersUpdated)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USERS DISABLED `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.usersDisabled)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USERS DELETED `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.usersDeleted)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USER CREATE ERRORS `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.userCreateErrors)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USER UPDATE ERRORS `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.userUpdateErrors)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USER DISABLE ERRORS `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.userDisableErrors)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "USER DELETE ERRORS `r`n"
	$report +=  "--------------------------------`r`n"
	foreach ($user in $reportData.userDeleteErrors)
	{
		$report +=  "$user `r`n"
	}
	$report +=  " `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "ADDITIONAL DETAILS `r`n"
	$report +=  "--------------------------------`r`n"
	$report +=  "Go to the report URL below and set: `r`n"
	$report +=  "  *Category = 'Account Provisioning' `r`n"
	$report +=  "  *Activity = 'Export' `r`n"
	$report +=  "  *Date Range = After $fromDate `r`n"
	$report +=  "  *Search for any user ID in question `r`n"
	$report +=  " `r`n"
	$report +=  "https://portal.azure.com/#blade/Microsoft_AAD_IAM/StartboardApplicationsMenuBlade/Audit/menuId/  `r`n"
	$report +=  " `r`n"

	return $report		
}


# ----------------------------------
# Script code
# ----------------------------------


$reportData = Get-AzureProvisioningAuditReportData -tenantDomain $tenantDomain -fromDate $fromDate -toDate $toDate
$report = Get-AzureProvisioningAuditReport -reportData $reportData	
$errorCount = $reportData.userCreateErrors.length + $reportData.userUpdateErrors.length
if ($errorCount > 0) {
	$priority = "High"
}
else {
	$priority = "Normal" 
}

$secpasswd = ConvertTo-SecureString $emailPassword -AsPlainText -Force
$emailLoginCredentials = New-Object System.Management.Automation.PSCredential ($emailUsername, $secpasswd)
		
if ($sendEmail) {			
	Send-MailMessage -Subject "AD Provisioning Report - $dateFormated [$errorCount errors]" -Body $report -To $emailRecipients -From $emailFrom -SmtpServer smtp.office365.com -usessl -Credential $emailLoginCredentials -Port 587 -Priority $priority
}

$filePath = $fileOutputPath + "ADProvisioningReport-$dateFormated.txt"

$report | Out-File -FilePath $filePath -Force
		
echo "Wrote ADProvisioningReport-$dateFormated.txt"



