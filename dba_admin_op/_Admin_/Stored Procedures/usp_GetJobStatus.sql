﻿-- =============================================
-- Author:		Sharon
-- Create date: 24/05/2016
-- Description:	Get Job
-- ToDo : Activate by - Alert,Scheduale,none
-- =============================================
CREATE PROCEDURE [_Admin_].[usp_GetJobStatus]
AS
BEGIN
	SET NOCOUNT ON;
	
	--IF OBJECT_ID('tempdb..#MPLog') IS NOT NULL DROP TABLE #MPLog;
	--CREATE TABLE #MPLog(MP_Name NVARCHAR(1000),FLog NVARCHAR(MAX));
	--EXEC [_Admin_].[usp_GetMPLogs];

	IF EXISTS(SELECT TOP 1 1 FROM SYS.databases D WHERE D.name = 'SSIS')
	BEGIN
		SELECT	j.name [JobName],
				js.step_id [StepID],
				js.step_name [StepName],
				--js.database_name [ExecutingDBOnJob],
				CASE 
				WHEN JSS.[SubSystem] = 'Maintenance Plans(SSIS)' AND MP.Error COLLATE DATABASE_DEFAULT != '' THEN LR.last_run_outcome + ' + Minor Errors'
				WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) OR ST.StepID IS NULL THEN LR.last_run_outcome 
						ELSE 'Did not run' END	[Outcome],
				CASE WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) THEN case WHEN ST.StepID IS NULL THEN null
									else LR.last_run_datetime END
						ELSE NULL END [LastRunDatetime] ,
				[Utility].[ufn_DATEDIFF2String](CASE WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) THEN case WHEN ST.StepID IS NULL THEN null
									else LR.last_run_datetime END
						ELSE NULL END,GETDATE()) [Diff],
			   JSS.[SubSystem],
			   CASE WHEN LR.last_run_datetime >= xSDT.StartDateTime THEN
					   CASE  
						WHEN JSS.[SubSystem] = 'Maintenance Plans(SSIS)' THEN CASE WHEN MP.Error COLLATE DATABASE_DEFAULT = '' THEN JH.message ELSE ISNULL(MP.Error COLLATE DATABASE_DEFAULT,JH.message) END
						WHEN LR.last_run_outcome = 'Failed' AND JS.subsystem = 'SSIS' THEN JH.message
						WHEN LR.last_run_outcome = 'Failed' AND JS.subsystem = 'TSQL' THEN JH.message
					   ELSE NULL END 
			   ELSE NULL END [Message],
			   CASE WHEN J.description LIKE '%report server%' THEN 'Report Server, ' ELSE '' END + ISNULL('Alert - ' + Al.name + ', ','') + ISNULL('Schedule - ' + SCH.name,'') [Caller]
		FROM	msdb.dbo.sysjobs j
				INNER JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
				CROSS APPLY(SELECT TOP 1 CASE WHEN patINDEX('%"Maintenance Plans\%',js.command) > 0 THEN 'Maintenance Plans(SSIS)' ELSE
				CASE js.subsystem
			WHEN 'ActiveScripting' THEN 'ActiveX Script'
			WHEN 'CmdExec' THEN 'Operating system (CmdExec)'
			WHEN 'PowerShell' THEN 'PowerShell'
			WHEN 'Distribution' THEN 'Replication Distributor'
			WHEN 'Merge' THEN 'Replication Merge'
			WHEN 'QueueReader' THEN 'Replication Queue Reader'
			WHEN 'Snapshot' THEN 'Replication Snapshot'
			WHEN 'LogReader' THEN 'Replication Transaction-Log Reader'
			WHEN 'ANALYSISCOMMAND' THEN 'SQL Server Analysis Services Command'
			WHEN 'ANALYSISQUERY' THEN 'SQL Server Analysis Services Query'
			WHEN 'SSIS' THEN 'SQL Server Integration Services Package'
			WHEN 'TSQL' THEN 'Transact-SQL script (T-SQL)'
			ELSE js.subsystem END
		  END AS [SubSystem]) JSS
				LEFT JOIN (SELECT	DISTINCT Ij.name,ISNULL(IIF(LAG(Ijs.on_success_step_id) OVER(ORDER BY Ijs.step_id) = 0,Ijs.step_id,LAG(Ijs.on_success_step_id) OVER(ORDER BY Ijs.step_id)),Ijs.step_id) StepID
							FROM	msdb.dbo.sysjobs Ij
									inner join msdb.dbo.sysjobsteps Ijs on Ij.job_id = Ijs.job_id
									) ST ON ST.StepID = JS.step_id and ST.name = j.name
				CROSS APPLY (SELECT TOP 1 msdb.dbo.agent_datetime(
								   case when js.last_run_date = 0 then NULL else js.last_run_date end,
								   case when js.last_run_time = 0 then NULL else js.last_run_time end) last_run_datetime,
								   case WHEN ST.StepID IS NULL THEN 'Disabled'
									when js.last_run_outcome = 0 then 'Failed'
									when js.last_run_outcome = 1 then 'Succeeded'
									when js.last_run_outcome = 2 then 'Retry'
									when js.last_run_outcome = 3 then 'Canceled'
									else 'Unknown'
								   end AS last_run_outcome
								   ) LR
				LEFT JOIN msdb.dbo.sysjobhistory JH ON j.job_id = JH.job_id
					AND JH.step_id = JS.step_id
					AND msdb.dbo.agent_datetime(JH.run_date,JH.run_time) = case WHEN ST.StepID IS NULL THEN null else LR.last_run_datetime END
				LEFT JOIN msdb..sysalerts Al ON Al.job_id = j.job_id
				OUTER APPLY (SELECT TOP 1 s2.name FROM msdb..sysjobschedules S INNER JOIN msdb..sysschedules S2 ON S2.schedule_id = S.schedule_id WHERE j.job_id = s.job_id)SCH
				--LEFT JOIN #MPLog MP ON j.name LIKE MP.MP_Name + '%'
				OUTER APPLY (SELECT REPLACE(REPLACE(T.Error,'<X>',''),'</X>','')
							FROM	(SELECT  ld.error_message  X
									FROM    msdb..sysmaintplan_plans mp
											INNER JOIN msdb..sysmaintplan_subplans msp ON mp.id = msp.plan_id
											OUTER APPLY (SELECT TOP 1 * FROM msdb..sysmaintplan_log mpl WHERE msp.subplan_id = mpl.subplan_id ORDER BY mpl.start_time DESC)mpl
											LEFT JOIN msdb..sysmaintplan_logdetail ld ON mpl.task_detail_id = ld.task_detail_id
									WHERE   j.name LIKE mp.name + '%'
									FOR XML PATH(''))T(Error))MP(Error)
				OUTER APPLY (SELECT	TOP 1 [StartDateTime] = msdb.dbo.agent_datetime(
									   CASE WHEN xjs.last_run_date = 0 then NULL else xjs.last_run_date end,
									   CASE WHEN xjs.last_run_time = 0 then NULL else xjs.last_run_time end)
								FROM	msdb.dbo.sysjobsteps xjs
										LEFT JOIN (SELECT	ja.job_id,
															j.name AS job_name,
															ja.start_execution_date,      
															ISNULL(last_executed_step_id,0)+1 AS current_executed_step_id,
															Js.step_name
													FROM	msdb.dbo.sysjobactivity ja 
															LEFT JOIN msdb.dbo.sysjobhistory jh ON ja.job_history_id = jh.instance_id
															INNER JOIN msdb.dbo.sysjobs j ON ja.job_id = j.job_id
															INNER JOIN msdb.dbo.sysjobsteps js ON ja.job_id = js.job_id
																AND ISNULL(ja.last_executed_step_id,0)+1 = js.step_id
													WHERE	ja.session_id = (SELECT TOP 1 session_id FROM msdb.dbo.syssessions ORDER BY agent_start_date DESC)
															AND start_execution_date is not null
															AND stop_execution_date is null)Ac ON aC.job_id = xjs.job_id
								WHERE	j.job_id = xjs.job_id
										AND (Ac.start_execution_date != msdb.dbo.agent_datetime(case when xjs.last_run_date = 0 then NULL else xjs.last_run_date end,
									   case when xjs.last_run_time = 0 then NULL else xjs.last_run_time end) or Ac.start_execution_date is null)
								order by xjs.step_id)xSDT
				OUTER APPLY (SELECT	TOP 1 ja.run_requested_date FROM msdb.dbo.sysjobactivity ja WHERE j.job_id = ja.job_id ORDER BY ja.run_requested_date desc)JxA
				OUTER APPLY( SELECT  TOP 1 MESSAGE--,event_message_id,package_name,event_name,message_source_name,package_path,execution_path,message_type,message_source_type
							   FROM    SSISDB.catalog.event_messages em
							   WHERE   em.package_name COLLATE database_default = RIGHT( SUBSTRING(js.command,0,patINDEX('%.dtsx%',js.command)), CHARINDEX( '\', REVERSE( SUBSTRING(js.command,0,patINDEX('%.dtsx%',js.command))) + '\' ) - 1 ) +N'.dtsx'
										--AND em.operation_id = (SELECT MAX(execution_id) FROM SSISDB.catalog.executions)
										AND event_name = 'OnError'
						ORDER BY event_message_id DESC
				)SS
  
		WHERE	j.enabled = 1
		ORDER BY j.name,js.step_id;
	END
	ELSE
	BEGIN
		SELECT	j.name [JobName],
				js.step_id [StepID],
				js.step_name [StepName],
				--js.database_name [ExecutingDBOnJob],
				CASE 
				WHEN JSS.[SubSystem] = 'Maintenance Plans(SSIS)' AND MP.Error COLLATE DATABASE_DEFAULT != '' THEN LR.last_run_outcome + ' + Minor Errors'
				WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) OR ST.StepID IS NULL THEN LR.last_run_outcome 
						ELSE 'Did not run' END	[Outcome],
				CASE WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) THEN case WHEN ST.StepID IS NULL THEN null
									else LR.last_run_datetime END
						ELSE NULL END [LastRunDatetime] ,
				[Utility].[ufn_DATEDIFF2String](CASE WHEN LR.last_run_datetime >= ISNULL(xSDT.StartDateTime,JxA.run_requested_date) THEN case WHEN ST.StepID IS NULL THEN null
									else LR.last_run_datetime END
						ELSE NULL END,GETDATE()) [Diff],
			   JSS.[SubSystem],
			   CASE WHEN LR.last_run_datetime >= xSDT.StartDateTime THEN
					   CASE 
						WHEN JSS.[SubSystem] = 'Maintenance Plans(SSIS)' THEN CASE WHEN MP.Error COLLATE DATABASE_DEFAULT = '' THEN JH.message ELSE ISNULL(MP.Error COLLATE DATABASE_DEFAULT,JH.message) END
						WHEN LR.last_run_outcome = 'Failed' AND JS.subsystem = 'SSIS' THEN JH.message
						WHEN LR.last_run_outcome = 'Failed' AND JS.subsystem = 'TSQL' THEN JH.message
					   ELSE NULL END 
			   ELSE NULL END [Message],
			   CASE WHEN J.description LIKE '%report server%' THEN 'Report Server, ' ELSE '' END + ISNULL('Alert - ' + Al.name + ', ','') + ISNULL('Schedule - ' + SCH.name,'') [Caller]
		FROM	msdb.dbo.sysjobs j
				INNER JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
				CROSS APPLY(SELECT TOP 1 CASE WHEN patINDEX('%"Maintenance Plans\%',js.command) > 0 THEN 'Maintenance Plans(SSIS)' ELSE
				CASE js.subsystem	WHEN 'ActiveScripting' THEN 'ActiveX Script'
									WHEN 'CmdExec' THEN 'Operating system (CmdExec)'
									WHEN 'PowerShell' THEN 'PowerShell'
									WHEN 'Distribution' THEN 'Replication Distributor'
									WHEN 'Merge' THEN 'Replication Merge'
									WHEN 'QueueReader' THEN 'Replication Queue Reader'
									WHEN 'Snapshot' THEN 'Replication Snapshot'
									WHEN 'LogReader' THEN 'Replication Transaction-Log Reader'
									WHEN 'ANALYSISCOMMAND' THEN 'SQL Server Analysis Services Command'
									WHEN 'ANALYSISQUERY' THEN 'SQL Server Analysis Services Query'
									WHEN 'SSIS' THEN 'SQL Server Integration Services Package'
									WHEN 'TSQL' THEN 'Transact-SQL script (T-SQL)'
									ELSE js.subsystem END
								  END AS [SubSystem]) JSS
				LEFT JOIN (SELECT	DISTINCT Ij.name,ISNULL(IIF(LAG(Ijs.on_success_step_id) OVER(ORDER BY Ijs.step_id) = 0,Ijs.step_id,LAG(Ijs.on_success_step_id) OVER(ORDER BY Ijs.step_id)),Ijs.step_id) StepID
							FROM	msdb.dbo.sysjobs Ij
									inner join msdb.dbo.sysjobsteps Ijs on Ij.job_id = Ijs.job_id
									) ST ON ST.StepID = JS.step_id and ST.name = j.name
				CROSS APPLY (SELECT TOP 1 msdb.dbo.agent_datetime(
								   case when js.last_run_date = 0 then NULL else js.last_run_date end,
								   case when js.last_run_time = 0 then NULL else js.last_run_time end) last_run_datetime,
								   case WHEN ST.StepID IS NULL THEN 'Disabled'
									when js.last_run_outcome = 0 then 'Failed'
									when js.last_run_outcome = 1 then 'Succeeded'
									when js.last_run_outcome = 2 then 'Retry'
									when js.last_run_outcome = 3 then 'Canceled'
									else 'Unknown'
								   end AS last_run_outcome
								   ) LR
				LEFT JOIN msdb.dbo.sysjobhistory JH ON j.job_id = JH.job_id
					AND JH.step_id = JS.step_id
					AND msdb.dbo.agent_datetime(JH.run_date,JH.run_time) = case WHEN ST.StepID IS NULL THEN null else LR.last_run_datetime END
				LEFT JOIN msdb..sysalerts Al ON Al.job_id = j.job_id
				OUTER APPLY (SELECT TOP 1 s2.name FROM msdb..sysjobschedules S INNER JOIN msdb..sysschedules S2 ON S2.schedule_id = S.schedule_id WHERE j.job_id = s.job_id)SCH
				--LEFT JOIN #MPLog MP ON j.name LIKE MP.MP_Name + '%'
				OUTER APPLY (SELECT REPLACE(REPLACE(T.Error,'<X>',''),'</X>','')
							FROM	(SELECT  ld.error_message  X
									FROM    msdb..sysmaintplan_plans mp
											INNER JOIN msdb..sysmaintplan_subplans msp ON mp.id = msp.plan_id
											OUTER APPLY (SELECT TOP 1 * FROM msdb..sysmaintplan_log mpl WHERE msp.subplan_id = mpl.subplan_id ORDER BY mpl.start_time DESC)mpl
											LEFT JOIN msdb..sysmaintplan_logdetail ld ON mpl.task_detail_id = ld.task_detail_id
									WHERE   j.name LIKE mp.name + '%'
									FOR XML PATH(''))T(Error))MP(Error)
				OUTER APPLY (SELECT	TOP 1 [StartDateTime] = msdb.dbo.agent_datetime(
									   CASE WHEN xjs.last_run_date = 0 then NULL else xjs.last_run_date end,
									   CASE WHEN xjs.last_run_time = 0 then NULL else xjs.last_run_time end)
								FROM	msdb.dbo.sysjobsteps xjs
										LEFT JOIN (SELECT	ja.job_id,
															j.name AS job_name,
															ja.start_execution_date,      
															ISNULL(last_executed_step_id,0)+1 AS current_executed_step_id,
															Js.step_name
													FROM	msdb.dbo.sysjobactivity ja 
															LEFT JOIN msdb.dbo.sysjobhistory jh ON ja.job_history_id = jh.instance_id
															INNER JOIN msdb.dbo.sysjobs j ON ja.job_id = j.job_id
															INNER JOIN msdb.dbo.sysjobsteps js ON ja.job_id = js.job_id
																AND ISNULL(ja.last_executed_step_id,0)+1 = js.step_id
													WHERE	ja.session_id = (SELECT TOP 1 session_id FROM msdb.dbo.syssessions ORDER BY agent_start_date DESC)
															AND start_execution_date is not null
															AND stop_execution_date is null)Ac ON aC.job_id = xjs.job_id
								WHERE	j.job_id = xjs.job_id
										AND (Ac.start_execution_date != msdb.dbo.agent_datetime(case when xjs.last_run_date = 0 then NULL else xjs.last_run_date end,
									   case when xjs.last_run_time = 0 then NULL else xjs.last_run_time end) or Ac.start_execution_date is null)
								order by xjs.step_id)xSDT
				OUTER APPLY (SELECT	TOP 1 ja.run_requested_date FROM msdb.dbo.sysjobactivity ja WHERE j.job_id = ja.job_id ORDER BY ja.run_requested_date desc)JxA

  
		WHERE	j.enabled = 1
		ORDER BY JSS.[SubSystem],j.name,js.step_id;
	END
END