### Intune Admin Checklist:

[Tenant admin | Tenant status](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/TenantAdminMenu/~/tenantStatus)

Connector Status:
- [ ] Confirm connectors are syncronising
- [ ] Confirm connecters are not expiring.

Service health and message center:
- [ ] Check "Service Health" for any active degradation notices.
- [ ] Check "Message center" for any upcoming changes that might affect your tennent and plan accordingly. 

[Endpoint Security | Antivirus](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/antivirus)

- [ ] Check "Unhealthy endpoints" and create incidents to resolve any issues.
- [ ] Check "Active malware" and create incidents to resolve any issues.

[Endpoint Security | Firewall](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/firewall)

- [ ] Check "MDM devices running Windows 10 or later with firewall off" and create incidents to resolve any issues.

[Endpoint Security | Conditional Access](https://intune.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Overview)

- [ ] TBA.
 
[Endpoint Security | Firewall](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/firewall)

- [ ] Check for any assignment failures and resolve conflicts. 

[Apps | App install status](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsMonitorMenu/~/appInstallStatus)

- [ ] Check for any install failures and resolve.

[Reports | Windows updates](https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/ReportingMenu/~/windowsUpdateReporting)

- [ ] Check for any Windows update errors.
- [ ] Check for any Driver update errors.

[Reports | Microsoft Defender Antivirus](https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/ReportingMenu/~/defender)

- [ ] Check for any critical devices.
- [ ] Check for any driver update errors.
- [ ] Run the "Antivirus agent status" report
- [ ] Run the "Detected malware" report

[Reports | Firewall](https://intune.microsoft.com/#view/Microsoft_Intune_Enrollment/FirewallReportBlade)

- [ ] Run the "MDM Firewall status​ for Windows 10 and later" report

