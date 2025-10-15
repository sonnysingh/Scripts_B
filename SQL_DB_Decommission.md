# SQL Database Decommission Checklist

This document outlines the detailed steps for decommissioning a SQL Server database hosted on a shared SQL Server. It covers database removal, cleanup of related objects, and proper dismantling of log shipping configurations.

---

## 1. Database Decommissioning Tasks

### a. Disable Application Access
- Revoke or disable logins related to the application.
- Verify no active connections.

### b. Backup
- Take a final full backup of the database (retain for compliance if required).
- Store in archive location.

### c. Remove Database
```sql
ALTER DATABASE [YourDBName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [YourDBName];
```

---

## 2. Related SQL Server Objects Cleanup

### a. Logins
- Identify logins specific to the database:
```sql
sp_help_revlogin;
```
- Drop or disable unnecessary logins:
```sql
DROP LOGIN [LoginName];
```

### b. SQL Agent Jobs
- Disable jobs related to the database:
```sql
EXEC msdb.dbo.sp_update_job @job_name = 'JobName', @enabled = 0;
```
- Drop if not required:
```sql
EXEC msdb.dbo.sp_delete_job @job_name = 'JobName';
```

### c. SSIS/SSAS Packages
- Remove or disable SSIS packages linked to the database.
- Remove SSAS data sources and cubes pointing to the database.

### d. Reporting Services (SSRS)
- Identify and remove SSRS data sources and reports connected to the database.

### e. Linked Servers
- Drop linked server objects not required:
```sql
EXEC sp_dropserver 'LinkedServerName', 'droplogins';
```

---

## 3. Log Shipping Decommissioning Steps

### a. Validate Current Status
- On **Primary**:
```sql
EXEC master.dbo.sp_help_log_shipping_primary_database @database = 'YourDBName';
```
- On **Secondary**:
```sql
EXEC master.dbo.sp_help_log_shipping_secondary_database @secondary_database = 'YourDBName';
```

### b. Disable Log Shipping Jobs
- On **Primary**:
```sql
EXEC msdb.dbo.sp_update_job @job_name = 'LSBackup_YourDBName', @enabled = 0;
```
- On **Secondary**:
```sql
EXEC msdb.dbo.sp_update_job @job_name = 'LSCopy_YourDBName', @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = 'LSRestore_YourDBName', @enabled = 0;
```

### c. Remove Log Shipping Configuration
- On **Primary**:
```sql
EXEC master.dbo.sp_delete_log_shipping_primary_database @database = 'YourDBName';
```
- On **Secondary**:
```sql
EXEC master.dbo.sp_delete_log_shipping_secondary_database @secondary_database = 'YourDBName';
```
- On **Monitor** (if configured):
```sql
EXEC master.dbo.sp_delete_log_shipping_alert_job;
EXEC master.dbo.sp_delete_log_shipping_monitor_secondary @secondary_database = 'YourDBName';
EXEC master.dbo.sp_delete_log_shipping_monitor_primary @primary_database = 'YourDBName';
```

### d. Drop Secondary Database (if required)
```sql
DROP DATABASE [YourDBName];
```

### e. Cleanup Jobs & History
- Manually delete orphaned log shipping jobs if any remain.
- Purge old history:
```sql
DELETE FROM msdb.dbo.log_shipping_monitor_history_detail WHERE database_name = 'YourDBName';
```

### f. Validate Cleanup
```sql
SELECT * FROM msdb.dbo.log_shipping_primary_databases;
SELECT * FROM msdb.dbo.log_shipping_secondary_databases;
```
- Both should return **0 rows**.

---

## 4. Post-Decommission Validation
- Confirm database is removed from `sys.databases`.
- Confirm no active logins remain.
- Confirm no scheduled jobs reference the old database.
- Confirm SSRS/SSIS/SSAS objects are removed.
- Confirm no linked servers are left pointing to the decommissioned database.

---

✅ With these steps, the database and its associated configurations (including log shipping) are fully decommissioned from the environment.

