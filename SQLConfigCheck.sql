

-- Check Last Full Backup 

print 'Checking the Last Full backup'
SELECT 
    d.name AS DatabaseName,
    MAX(b.backup_finish_date) AS LastBackupDate
FROM 
    sys.databases d
LEFT JOIN 
    msdb.dbo.backupset b ON d.name = b.database_name
GROUP BY 
    d.name
ORDER BY 
    d.name;


-- Check if SQL backup Compression is enabled


-- Is Compression Set
IF (SELECT value FROM sys.configurations where name like  '%backup%compression%default%') = 0
BEGIN
	Print 'Backup compression not enabled'
END



-- Backup Check with Restore Commands

;WITH cte_Databases AS

(

	SELECT	@@SERVERNAME AS [INSTANCE_NAME], DB_ID(name) AS DBID
		 ,name  AS DBName 
	FROM master..sysdatabases 	
)


,cte_DataSize AS

(

	SELECT DB_NAME(mf.database_id) AS DBName, mf.physical_name, mf.name, SUM(CAST(mf.Size AS BIGINT)) * 8 * 1024 AS FileSize, COUNT(*) AS DataFileCount

	FROM master.sys.master_files mf

	INNER JOIN cte_Databases d

		ON mf.Database_ID = d.DBID

	WHERE mf.type_desc = 'ROWS'

	GROUP BY DB_NAME(mf.database_id), mf.physical_name, mf.name

)

,cte_LogSize AS

(

	SELECT DB_NAME(mf.database_id) AS DBName, mf.physical_name, mf.name, (CAST(mf.Size AS BIGINT)) * 8  * 1024  AS FileSize, COUNT(*) AS DataFileCount

	FROM master.sys.master_files mf

	INNER JOIN cte_Databases d

		ON mf.Database_ID = d.DBID

	WHERE mf.type_desc = 'LOG'

	GROUP BY DB_NAME(mf.database_id), mf.physical_name, mf.name, mf.Size

)

,cte_BackupSizeFull AS

(

	SELECT
		 bs.Database_Name				AS DBName
		 ,bmf.physical_device_name
		 ,bs.type
		--,CAST(bs.backup_size as decimal)/1024/1024/1024/1024	AS FullBackupSize
		--,AVG(CAST(bs.backup_size as decimal))/1024/1024/1024 AS FullBackupSize

		,CONVERT(DECIMAL(10,2),ROUND(AVG(bs.compressed_backup_size/1024/1024/1024),4)) AS FullBackupSizeGB
	FROM msdb.dbo.backupset bs

	INNER JOIN msdb.dbo.backupmediafamily bmf 

		ON bmf.media_set_id = bs.media_set_id

	INNER JOIN msdb.dbo.backupfile bf  

		ON bf.backup_set_id = bs.backup_set_id

	INNER JOIN cte_Databases d

		ON bs.Database_Name = d.DBName

	WHERE bs.Backup_Start_Date >= DATEADD(day, -7, GETDATE())

	AND bs.Type = 'd' 

	AND bf.File_Type = 'd'

	AND bmf.device_type != 7

	GROUP BY bs.Database_Name, bs.compressed_backup_size, bmf.physical_device_name, bs.type

)

--SELECT srvname from sys.sysservers

SELECT

   db.[INSTANCE_NAME]   AS INSTANCE_NAME
   
	,UPPER(ds.DBName)		AS DBName

	,ds.FileSize			AS DataSize

	,ds.name       AS DataFileName

	,ds.physical_name AS DataFileLocation

	,ls.FileSize			AS LogSize

	,ls.name       AS LogFileName

	,ls.physical_name AS LogFileLocation

	,bsf.FullBackupSizeGB		AS FullBackupSizeGB

	,bsf.physical_device_name   AS FullBackupPath,
		
		--Specifying the APPID, replacing DatabaseName to include APPID
	  'MOVE ''' + ds.name  + ''' TO ''' + REPLACE(ds.physical_name, bsf.DBName, bsf.DBName+'_'+'_APP-10708_'+'')+ '''' AS MoveDataFileComand,
	  'MOVE ''' + ls.name  + ''' TO ''' + REPLACE(ls.physical_name, bsf.DBName, bsf.DBName+'_'+'_APP-10708_'+'')+ '''' AS MoveLogFileComand,
	  'RESTORE DATABASE ['+ db.[INSTANCE_NAME]+'_'+ bsf.DBName+'] FROM DISK ='+ ''''+bsf.physical_device_name+''''+ 'WITH ' + 'MOVE ''' + ds.name  + ''' TO ''' + REPLACE(ds.physical_name, bsf.DBName, bsf.DBName+'')+ ''''+
	  ', MOVE ''' + ls.name  + ''' TO ''' + REPLACE(ls.physical_name, bsf.DBName, bsf.DBName+'')+ '''' +',STATS=10' AS MoveLogFileComand

	  --Specifying your own Location and DatabaseName
	  --'MOVE ''' + ds.name  + ''' TO ''' + @strRestoreMDFFilesTo + ''',' as [RestoreCommand_MoveDataFiles],
	 -- 'MOVE ''' + ls.name  + ''' TO ''' + @strRestoreLDFFilesTo + ''',' as [RestoreCommand_MoveLogFiles],
	  --'RESTORE DATABASE ['+ db.[INSTANCE_NAME]+'_'+  bsf.DBName+'] FROM DISK ='+ ''''+bsf.physical_device_name+''''+ 'WITH ' as [RestoreCommand_MultiDisk]

FROM 
cte_Databases as db

inner join cte_DataSize ds

on ds.DBName = db.DBName

INNER JOIN cte_LogSize ls

	ON ds.DBName = ls.DBName

LEFT OUTER JOIN cte_BackupSizeFull bsf

	ON ds.DBName = bsf.DBName

WHERE ds.DBName not in ('master', 'model', 'tempdb', 'msdb')
ORDER BY ds.DBName;


-- Check Agent Job runtimes

USE msdb;
GO

SELECT 
    j.name AS JobName,
    h.run_date AS RunDate,
    h.run_time AS RunTime,
    h.run_duration AS RunDuration,
    CASE 
        WHEN h.run_duration < 100 THEN CAST(h.run_duration AS VARCHAR(2)) + ' seconds'
        WHEN h.run_duration < 10000 THEN CAST(h.run_duration / 100 AS VARCHAR(2)) + ' minutes ' + CAST(h.run_duration % 100 AS VARCHAR(2)) + ' seconds'
        ELSE CAST(h.run_duration / 10000 AS VARCHAR(2)) + ' hours ' + CAST((h.run_duration % 10000) / 100 AS VARCHAR(2)) + ' minutes ' + CAST(h.run_duration % 100 AS VARCHAR(2)) + ' seconds'
    END AS FormattedRunDuration
FROM 
    sysjobs j
INNER JOIN 
    sysjobhistory h ON j.job_id = h.job_id
WHERE 
    h.step_id = 0 -- Only get the job outcome, not individual steps
ORDER BY 
    h.run_date DESC, h.run_time DESC;



-- Check if Server Part of a cluster

	IF SERVERPROPERTY('IsClustered') = 1
	BEGIN
    	PRINT 'This SQL Server instance is part of a cluster.';
	END
	ELSE IF SERVERPROPERTY('IsClustered') = 0
	BEGIN
    	PRINT 'This SQL Server instance is not part of a cluster.';
	END
	ELSE
	BEGIN
    	PRINT 'Unable to determine cluster status.';
	END


-- Check if Server is part of Log shipping

	USE msdb;
	GO

	IF (SELECT secondary_database
	FROM log_shipping_secondary_databases) IS  NULL

	BEGIN
	print 'This SQL Server instance is not part of Log Shipping.';
	END
	ELSE IF (SELECT secondary_database
	FROM log_shipping_secondary_databases) IS NOT NULL
	BEGIN
    	PRINT 'This SQL Server instance is part of Log Shipping.';
	SELECT *
	FROM log_shipping_monitor_primary
	SELECT *
	FROM log_shipping_monitor_secondary;
	END
	ELSE IF (SELECT primary_database
	FROM log_shipping_primary_databases) IS NOT NULL
	BEGIN
    	PRINT 'This SQL Server instance is not part of Log Shipping.';
	END


-- Check if Server Is part of Replication


IF (	SELECT name
FROM  sys.databases
WHERE (is_published | is_subscribed | is_merge_published | is_distributor = 1)) IS NULL
BEGIN
	print 'This Server is not part of Replication'
END
ELSE IF (	SELECT name
FROM  sys.databases
WHERE (is_published | is_subscribed | is_merge_published | is_distributor = 1)) IS NOT NULL
BEGIN
	print 'This Server is part of Replication'
	SELECT * FROM  sys.databases WHERE (is_published | is_subscribed | is_merge_published | is_distributor = 1);
END


-- Check DB level settings

SELECT name,  
       DATABASEPROPERTYEX(name, 'Recovery') AS RecoveryMode, 
       DATABASEPROPERTYEX(name, 'Status') AS Status,
	   DATABASEPROPERTYEX(name, 'Collation') AS Collation,
	   DATABASEPROPERTYEX(name, 'IsAutoClose') AS IsAutoClose,
		DATABASEPROPERTYEX(name, 'IsAutoShrink') AS IsAutoShrink,
		DATABASEPROPERTYEX(name, 'Recovery') AS RecoveryModel
FROM   master.dbo.sysdatabases 
ORDER BY 1


-- Check DB levle permissions

-- User Mapping

SELECT 
    DB_NAME() as DB_Name,
    User_Type = 
    CASE mmbrp.[type] 
    WHEN 'G' THEN 'Windows Group' 
    WHEN 'S' THEN 'SQL User' 
    WHEN 'U' THEN 'Windows User' 
    END,
    Database_User_Name = mmbrp.[name],
    Login_Name = ul.[name],
    DB_Role = rolp.[name]
FROM 
    sys.database_role_members mmbr, -- The Role OR members associations table
    sys.database_principals rolp,     -- The DB Roles names table
    sys.database_principals mmbrp,    -- The Role members table (database users)
    sys.server_principals ul          -- The Login accounts table
WHERE 
    Upper(mmbrp.[type]) IN ( 'S', 'U', 'G' )
    -- No need for these system account types
    AND Upper (mmbrp.[name]) NOT IN ('SYS','INFORMATION_SCHEMA')
    AND rolp.[principal_id] = mmbr.[role_principal_id]
    AND mmbrp.[principal_id] = mmbr.[member_principal_id]
    AND ul.[sid] = mmbrp.[sid]
    --AND rolp.[name] LIKE '%' + @dbRole + '%'
GO



-- DB Level permissions
SELECT 
    name AS LogicalFileName,
    physical_name AS PhysicalFileName,
    type_desc AS FileType
FROM 
    sys.master_files


-- DB Level Settings

SELECT name,  
       DATABASEPROPERTYEX(name, 'Recovery') AS RecoveryMode, 
       DATABASEPROPERTYEX(name, 'Status') AS Status,
	   DATABASEPROPERTYEX(name, 'Collation') AS Collation,
	   DATABASEPROPERTYEX(name, 'IsAutoClose') AS IsAutoClose,
		DATABASEPROPERTYEX(name, 'IsAutoShrink') AS IsAutoShrink,
		DATABASEPROPERTYEX(name, 'MaxSizeInBytes') AS MaxSizeInBytes,
		DATABASEPROPERTYEX(name, 'UserAccess') AS UserAccess


FROM   master.dbo.sysdatabases 
ORDER BY 1


--Check Server Level settings

SELECT
    name,
    value_in_use
FROM
    sys.configurations
WHERE
    description LIKE '%max%%parallelism%' OR
	description LIKE '%min%%memory%%'
	OR description LIKE '%min%%memory%%'
	OR description LIKE '%recovery%%'
	OR description LIKE '%allow%%'
	OR description LIKE '%user%%' 
	OR description LIKE '%open%%'
	OR description LIKE '%locks%%'
	OR description LIKE '%nested%%'
	OR description LIKE '%remote%%'
	OR description LIKE '%server%%'
	OR description LIKE '%default%%'
	OR description LIKE '%show%%'
	OR description LIKE '%network%%'
	OR description LIKE '%c2%%'
	OR description LIKE '%two%%'
	OR description LIKE '%cross%%'
	OR description LIKE '%cursor%%'
	OR description LIKE '%index%%'
	OR description LIKE '%set%%'
	OR description LIKE '%user%%'
	OR description LIKE '%max%%'
	OR description LIKE '%ft%%'
	OR description LIKE '%access%%'
	OR description LIKE '%optimize%%'
	OR description LIKE '%EKM%%'
	OR description LIKE '%blokced%%'
	OR description LIKE '%clr%%'
	OR description LIKE '%PH%%'
	OR description LIKE '%precompute%%'
	OR description LIKE '%affinity%%'
	OR description LIKE '%scan%%'
	OR description LIKE '%lightweight%%'
	OR description LIKE '%query%%'
	OR description LIKE '%in-doubt%%'
	OR description LIKE '%automatic%%'
	OR description LIKE '%column%%'
	OR description LIKE '%ADR%%'
	OR description LIKE '%filestream%%'
	OR description LIKE '%version%%'
	OR description LIKE '%polybase%%'
	OR description LIKE '%hadoop%%'
	OR description LIKE '%xp_cmdshell%%'
	OR description LIKE '%Agent%%'
	OR description LIKE '%Ole%%'
	OR description LIKE '%SMO%%'
	OR description LIKE '%external%%'


-- Disk Space

-- Estimated backup Size with compression

create table #backupsizetemp 
                            (database_name sysname, database_size varchar(18),[unallocated space] varchar(18), reserved varchar(18), data varchar(18),
                            index_size varchar(18),
                            unused varchar(18)
                            )
                                insert into #backupsizetemp (database_name,database_size,[unallocated space],reserved,data,index_size,unused)
                                EXEC sp_spaceused @oneresultset =1;
                                select EstiamtedBackupSizeGB = 
                                CAST(TRIM(REPLACE(reserved, 'kb', '')) AS DECIMAL(10,2)) / 1048576.8 
                                from #backupsizetemp


-- DB Growth

-- https://www.mssqltips.com/sqlservertip/6158/how-to-check-monthly-growth-of-database-in-sql-server/


--T-SQL Script to Show Database Growth Based on Backup Sizes

--SECTION 1 BEGIN
WITH BackupsSize AS(
SELECT TOP 1000
      rn = ROW_NUMBER() OVER (ORDER BY DATEPART(year,[backup_start_date]) ASC, DATEPART(month,[backup_start_date]) ASC)
    , [Year]  = DATEPART(year,[backup_start_date])
    , [Month] = DATEPART(month,[backup_start_date])
    , [Backup Size GB] = CONVERT(DECIMAL(10,2),ROUND(AVG([backup_size]/1024/1024/1024),4))
    , [Compressed Backup Size GB] = CONVERT(DECIMAL(10,2),ROUND(AVG([compressed_backup_size]/1024/1024/1024),4))
FROM 
    msdb.dbo.backupset
WHERE 
    [database_name] = N'XXXX'
AND [type] = 'D'
AND backup_start_date BETWEEN DATEADD(mm, - 13, GETDATE()) AND GETDATE()
GROUP BY 
    [database_name]
    , DATEPART(yyyy,[backup_start_date])
    , DATEPART(mm, [backup_start_date])
ORDER BY [Year],[Month]) 
--SECTION 1 END
 
--SECTION 2 BEGIN
SELECT 
   b.Year,
   b.Month,
   b.[Backup Size GB],
   0 AS deltaNormal,
   b.[Compressed Backup Size GB],
   0 AS deltaCompressed
FROM BackupsSize b
WHERE b.rn = 1
UNION
SELECT 
   b.Year,
   b.Month,
   b.[Backup Size GB],
   b.[Backup Size GB] - d.[Backup Size GB] AS deltaNormal,
   b.[Compressed Backup Size GB],
   b.[Compressed Backup Size GB] - d.[Compressed Backup Size GB] AS deltaCompressed
FROM BackupsSize b
CROSS APPLY (
   SELECT bs.[Backup Size GB],bs.[Compressed Backup Size GB]
   FROM BackupsSize bs
   WHERE bs.rn = b.rn - 1
) AS d
--SECTION 2 END



-- SQL Set-up Specific



-- SQL Engine account
SELECT  DSS.servicename,
        DSS.startup_type_desc,
        DSS.status_desc,
        DSS.last_startup_time,
        DSS.service_account,
        DSS.is_clustered,
        DSS.cluster_nodename,
        DSS.filename,
        DSS.startup_type,
        DSS.status,
        DSS.process_id
FROM    sys.dm_server_services AS DSS;





-- CPU and Memory



CREATE TABLE #CPUValues(
[index]        SMALLINT,
[description]  VARCHAR(128),
[server_cores] SMALLINT,
[value]        VARCHAR(5) 
)
 
CREATE TABLE #MemoryValues(
[index]         SMALLINT,
[description]   VARCHAR(128),
[server_memory] DECIMAL(10,2),
[value]         VARCHAR(64) 
)
 
INSERT INTO #CPUValues
EXEC xp_msver 'ProcessorCount'
 
INSERT INTO #MemoryValues 
EXEC xp_msver 'PhysicalMemory'
 
SELECT 
   SERVERPROPERTY('SERVERNAME') AS 'instance',
   v.sql_version,
   (SELECT SUBSTRING(CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')),0,CHARINDEX('Edition',CONVERT(VARCHAR(255),SERVERPROPERTY('EDITION')))) + 'Edition') AS sql_edition,
   SERVERPROPERTY('ProductLevel') AS 'service_pack_level',
   SERVERPROPERTY('ProductVersion') AS 'build_number',
   (SELECT DISTINCT local_tcp_port FROM sys.dm_exec_connections WHERE session_id = @@SPID) AS [port],
   (SELECT [value] FROM sys.configurations WHERE name like '%min server memory%') AS min_server_memory,
   (SELECT [value] FROM sys.configurations WHERE name like '%max server memory%') AS max_server_memory,
   (SELECT ROUND(CONVERT(DECIMAL(10,2),server_memory/1024.0),1) FROM #MemoryValues) AS server_memory,
   server_cores, 
   (SELECT COUNT(*) AS 'sql_cores' FROM sys.dm_os_schedulers WHERE status = 'VISIBLE ONLINE') AS sql_cores,
   (SELECT [value] FROM sys.configurations WHERE name like '%degree of parallelism%') AS max_dop,
   (SELECT [value] FROM sys.configurations WHERE name like '%cost threshold for parallelism%') AS cost_threshold_for_parallelism 
FROM #CPUValues
LEFT JOIN (
      SELECT
      CASE 
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '8%'    THEN 'SQL Server 2000'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '9%'    THEN 'SQL Server 2005'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.0%' THEN 'SQL Server 2008'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '10.5%' THEN 'SQL Server 2008 R2'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '11%'   THEN 'SQL Server 2012'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '12%'   THEN 'SQL Server 2014'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '13%'   THEN 'SQL Server 2016'     
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '14%'   THEN 'SQL Server 2017'
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '15%'   THEN 'SQL Server 2019' 
         WHEN CONVERT(VARCHAR(128), SERVERPROPERTY ('PRODUCTVERSION')) like '16%'   THEN 'SQL Server 2022' 
         ELSE 'UNKNOWN'
      END AS sql_version
     ) AS v ON 1 = 1
 
DROP TABLE #CPUValues
DROP TABLE #MemoryValues


-- Check Disk Space
SELECT DISTINCT
    vs.volume_mount_point,
    vs.file_system_type,
    vs.logical_volume_name,
    CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
    CONVERT(DECIMAL(18,2), vs.available_bytes/1073741824.0) AS [Available Size (GB)],
    CONVERT(DECIMAL(18,2), vs.available_bytes * 1. / vs.total_bytes * 100.) AS [Space Free %]
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs
ORDER BY vs.volume_mount_point OPTION (RECOMPILE);

























































































