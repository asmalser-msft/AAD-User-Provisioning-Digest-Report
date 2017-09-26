USER PROVISIONING DIGEST Report
Author: asmalser

 - Reads all user account provisioning events from the Azure AD graph for a specificed time period, and emits a digest report.  

- The digest report is written to a text file on the host system, and can also be sent over email using an Office365 email account

- This script can be scheduled to run at any desired time interval using the Windows Task Scheduler

- Requires an application entry and secret key to be registered in the Azure AD tenant where the provisioning events exist, as described at:
 https://docs.microsoft.com/en-us/azure/active-directory/active-directory-reporting-api-prerequisites-azure-portal

- In additon, "oauth2AllowImplicitFlow":true must be set in the manifest for this application entry. For details, see:
 https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-application-manifest
