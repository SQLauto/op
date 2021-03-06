﻿/*
    This code is blogged here
    http://weblogs.sqlteam.com/peterl/archive/2008/10/10/Keep-track-of-all-your-jobs-schedules.aspx
*/
CREATE PROCEDURE dbo.uspGetScheduleTimes
    (
      @startDate DATETIME ,
      @endDate DATETIME
    )
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @StartDTDate DATE;
	DECLARE @endDTDate DATE 
	SET @StartDTDate = @startDate;
	SET @endDTDate = @startDate;
-- Create a tally table. If you already have one of your own please use that instead.
    CREATE TABLE #tallyNumbers
        (
          num SMALLINT PRIMARY KEY CLUSTERED
        );
 
    DECLARE @index SMALLINT;
 
    SET @index = 1;
 
    WHILE @index <= 8640
        BEGIN
            INSERT  #tallyNumbers
                    ( num )
            VALUES  ( @index );
 
            SET @index = @index + 1;
        END;
 
-- Create a staging table for jobschedules
    CREATE TABLE #jobSchedules
        (
          rowID INT IDENTITY(1, 1)
                    PRIMARY KEY CLUSTERED ,
          serverName sysname NOT NULL ,
          jobName sysname NOT NULL ,
          jobDescription NVARCHAR(512) NOT NULL ,
          scheduleName sysname NOT NULL ,
          scheduleID INT NOT NULL ,
          categoryName sysname NOT NULL ,
          freq_type INT NOT NULL ,
          freq_interval INT NOT NULL ,
          freq_subday_type INT NOT NULL ,
          freq_subday_interval INT NOT NULL ,
          freq_relative_interval INT NOT NULL ,
          freq_recurrence_factor INT NOT NULL ,
          startDate DATE NOT NULL ,
          startTime TIME NOT NULL ,
          endDate DATE NOT NULL ,
          endTime TIME NOT NULL ,
          jobEnabled INT NOT NULL ,
          scheduleEnabled INT NOT NULL
        );
 
-- Popoulate the staging table for JobSchedules with SQL Server 2005+
    INSERT  #jobSchedules
            ( serverName ,
              jobName ,
              jobDescription ,
              scheduleName ,
              scheduleID ,
              categoryName ,
              freq_type ,
              freq_interval ,
              freq_subday_type ,
              freq_subday_interval ,
              freq_relative_interval ,
              freq_recurrence_factor ,
              startDate ,
              startTime ,
              endDate ,
              endTime ,
              jobEnabled ,
              scheduleEnabled
            )
            SELECT  srv.srvname ,
                    sj.name ,
                    COALESCE(sj.description, '') ,
                    ss.name ,
                    ss.schedule_id ,
                    sc.name ,
                    ss.freq_type ,
                    ss.freq_interval ,
                    ss.freq_subday_type ,
                    ss.freq_subday_interval ,
                    ss.freq_relative_interval ,
                    ss.freq_recurrence_factor ,
                    COALESCE(STR(ss.active_start_date, 8),
                             CONVERT(CHAR(8), GETDATE(), 112)) ,
                    STUFF(STUFF(REPLACE(STR(ss.active_start_time, 6), ' ', '0'),
                                3, 0, ':'), 6, 0, ':') ,
                    STR(ss.active_end_date, 8) ,
                    STUFF(STUFF(REPLACE(STR(ss.active_end_time, 6), ' ', '0'),
                                3, 0, ':'), 6, 0, ':') ,
                    sj.enabled ,
                    ss.enabled
            FROM    msdb..sysschedules AS ss
                    INNER JOIN msdb..sysjobschedules AS sjs ON sjs.schedule_id = ss.schedule_id
                    INNER JOIN msdb..sysjobs AS sj ON sj.job_id = sjs.job_id
                    INNER JOIN sys.sysservers AS srv ON srv.srvid = sj.originating_server_id
                    INNER JOIN msdb..syscategories AS sc ON sc.category_id = sj.category_id
            WHERE   ss.freq_type IN ( 1, 4, 8, 16, 32 )
            ORDER BY srv.srvname ,
                    sj.name ,
                    ss.name;

-- Only deal with jobs that has active start date before @endDate
    DELETE  FROM #jobSchedules
    WHERE   startDate > @endDate;

-- Only deal with jobs that has active end date after @startDate
    DELETE  FROM #jobSchedules
    WHERE   endDate < @startDate;

    CREATE TABLE #dayInformation
        (
          infoDate DATETIME PRIMARY KEY CLUSTERED ,
          weekdayName VARCHAR(9) NOT NULL ,
          statusCode INT NOT NULL ,
          lastDay TINYINT DEFAULT 0
        );
 

     INSERT  #dayInformation
                ( infoDate ,
                    weekdayName ,
                    statusCode
                )
		SELECT	I.infoDate,DATENAME(WEEKDAY, I.infoDate) [weekdayName],
				CASE WHEN number BETWEEN 1 AND 7
					THEN 1
					WHEN number BETWEEN 8 AND 14
					THEN 2
					WHEN number BETWEEN 15 AND 21
					THEN 4
					WHEN number BETWEEN 22 AND 28
					THEN 8
					ELSE 0
				END [statusCode]
		FROM	master.dbo.spt_values
				CROSS APPLY (SELECT @startDate - DAY(@startDate) +  number infoDate)I
		WHERE	type = 'P'
				AND number BETWEEN 1 AND DATEDIFF(DAY, @startDate - DAY(@startDate) + 1, DATEADD(MONTH, 1, @startDate - DAY(@startDate) + 1))
			
 
    UPDATE  di
    SET     di.statusCode = di.statusCode + 16
    FROM    #dayInformation AS di
            INNER JOIN ( SELECT DATEDIFF(MONTH, '19000101', infoDate) AS theMonth ,
                                DATEPART(DAY, MAX(infoDate)) - 6 AS theDay
                         FROM   #dayInformation
                         GROUP BY DATEDIFF(MONTH, '19000101', infoDate)
                       ) AS x ON x.theMonth = DATEDIFF(MONTH, '19000101',
                                                       di.infoDate)
    WHERE   DATEPART(DAY, di.infoDate) >= x.theDay;
 
    UPDATE  di
    SET     di.lastDay = 16
    FROM    #dayInformation AS di
            INNER JOIN ( SELECT DATEDIFF(MONTH, '19000101', infoDate) AS theMonth ,
                                MAX(infoDate) AS theDay
                         FROM   #dayInformation
                         GROUP BY DATEDIFF(MONTH, '19000101', infoDate)
                       ) AS x ON x.theMonth = DATEDIFF(MONTH, '19000101',
                                                       di.infoDate)
    WHERE   di.infoDate = x.theDay;
 
    UPDATE  #dayInformation
    SET     lastDay = DATEPART(DAY, infoDate)
    WHERE   DATEPART(DAY, infoDate) BETWEEN 1 AND 4;
 
-- Stage all individual schedule times
    CREATE TABLE #scheduleTimes
        (
          rowID INT NOT NULL ,
          infoDate DATETIME NOT NULL ,
          startTime DATETIME NOT NULL ,
          endTime DATETIME NOT NULL ,
          waitSeconds INT DEFAULT 0
        );
 
    CREATE CLUSTERED INDEX IX_rowID ON #scheduleTimes(rowID);

-- Insert one time only schedules
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime
            )
            SELECT  rowID ,
                    startDate ,
                    startTime ,
                    endTime
            FROM    #jobSchedules
            WHERE   freq_type = 1
                    AND startDate BETWEEN @StartDTDate AND @endDTDate
					AND startTime BETWEEN CONVERT(TIME,@StartDate) AND CONVERT(TIME,@endDate);

-- Insert daily schedules
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime ,
              waitSeconds
            )
            SELECT  js.rowID ,
                    di.infoDate ,
                    cast(di.infoDate as datetime) + cast(js.startTime as datetime) ,
                    cast(di.infoDate as datetime) + cast(js.endTime as datetime) ,
                    CASE js.freq_subday_type
                      WHEN 1 THEN 0
                      WHEN 2 THEN js.freq_subday_interval
                      WHEN 4 THEN 60 * js.freq_subday_interval
                      WHEN 8 THEN 3600 * js.freq_subday_interval
                    END
            FROM    #jobSchedules AS js
                    INNER JOIN #dayInformation AS di ON di.infoDate >= @startDate
                                                        AND di.infoDate <= @endDate
            WHERE   js.freq_type = 4
                    AND DATEDIFF(DAY, js.startDate, di.infoDate) % js.freq_interval = 0;
	--SELECT 'Insert daily schedules' [x],* FROM #scheduleTimes;
	-- Insert weekly schedules
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime ,
              waitSeconds
            )
            SELECT  js.rowID ,
                    di.infoDate ,
                    cast(di.infoDate as datetime) + cast(js.startTime as datetime) ,
                    cast(di.infoDate as datetime) + cast(js.endTime as datetime) ,
                    CASE js.freq_subday_type
                      WHEN 1 THEN 0
                      WHEN 2 THEN js.freq_subday_interval
                      WHEN 4 THEN 60 * js.freq_subday_interval
                      WHEN 8 THEN 3600 * js.freq_subday_interval
                    END
            FROM    #jobSchedules AS js
                    INNER JOIN #dayInformation AS di ON di.infoDate BETWEEN @StartDTDate AND @endDTDate
            WHERE   js.freq_type = 8
                    AND 1 = CASE WHEN js.freq_interval & 1 = 1
                                      AND di.weekdayName = 'Sunday' THEN 1
                                 WHEN js.freq_interval & 2 = 2
                                      AND di.weekdayName = 'Monday' THEN 1
                                 WHEN js.freq_interval & 4 = 4
                                      AND di.weekdayName = 'Tuesday' THEN 1
                                 WHEN js.freq_interval & 8 = 8
                                      AND di.weekdayName = 'Wednesday' THEN 1
                                 WHEN js.freq_interval & 16 = 16
                                      AND di.weekdayName = 'Thursday' THEN 1
                                 WHEN js.freq_interval & 32 = 32
                                      AND di.weekdayName = 'Friday' THEN 1
                                 WHEN js.freq_interval & 64 = 64
                                      AND di.weekdayName = 'Saturday' THEN 1
                                 ELSE 0
                            END
                    AND ( DATEDIFF(DAY, js.startDate, di.infoDate) / 7 )
                    % js.freq_recurrence_factor = 0;
--SELECT 'Insert weekly schedules' [x],* FROM #scheduleTimes;
-- Insert monthly schedules
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime ,
              waitSeconds
            )
            SELECT  js.rowID ,
                    di.infoDate ,
                    cast(di.infoDate as datetime) + cast(js.startTime as datetime) ,
                    cast(di.infoDate as datetime) + cast(js.endTime as datetime) ,
                    CASE js.freq_subday_type
                      WHEN 1 THEN 0
                      WHEN 2 THEN js.freq_subday_interval
                      WHEN 4 THEN 60 * js.freq_subday_interval
                      WHEN 8 THEN 3600 * js.freq_subday_interval
                    END
            FROM    #jobSchedules AS js
                    INNER JOIN #dayInformation AS di ON di.infoDate BETWEEN @StartDTDate AND @endDTDate
            WHERE   js.freq_type = 16
                    AND DATEPART(DAY, di.infoDate) = js.freq_interval
                    AND DATEDIFF(MONTH, js.startDate, di.infoDate)
                    % js.freq_recurrence_factor = 0;
--SELECT 'Insert monthly schedules' [x],* FROM #scheduleTimes;
 
-- Insert monthly relative schedules
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime ,
              waitSeconds
            )
            SELECT  js.rowID ,
                    di.infoDate ,
                    cast(di.infoDate as datetime) + cast(js.startTime as datetime) ,
                    cast(di.infoDate as datetime) + cast(js.endTime as datetime) ,
                    CASE js.freq_subday_type
                      WHEN 1 THEN 0
                      WHEN 2 THEN js.freq_subday_interval
                      WHEN 4 THEN 60 * js.freq_subday_interval
                      WHEN 8 THEN 3600 * js.freq_subday_interval
                    END
            FROM    #jobSchedules AS js
                    INNER JOIN #dayInformation AS di ON di.infoDate BETWEEN @StartDTDate AND @endDTDate
            WHERE   js.freq_type = 32
                    AND 1 = CASE WHEN js.freq_interval = 1
                                      AND di.weekdayName = 'Sunday' THEN 1
                                 WHEN js.freq_interval = 2
                                      AND di.weekdayName = 'Monday' THEN 1
                                 WHEN js.freq_interval = 3
                                      AND di.weekdayName = 'Tuesday' THEN 1
                                 WHEN js.freq_interval = 4
                                      AND di.weekdayName = 'Wednesday' THEN 1
                                 WHEN js.freq_interval = 5
                                      AND di.weekdayName = 'Thursday' THEN 1
                                 WHEN js.freq_interval = 6
                                      AND di.weekdayName = 'Friday' THEN 1
                                 WHEN js.freq_interval = 7
                                      AND di.weekdayName = 'Saturday' THEN 1
                                 WHEN js.freq_interval = 8
                                      AND js.freq_relative_interval = di.lastDay
                                 THEN 1
                                 WHEN js.freq_interval = 9
                                      AND di.weekdayName NOT IN ( 'Sunday',
                                                              'Saturday' )
                                 THEN 1
                                 WHEN js.freq_interval = 10
                                      AND di.weekdayName IN ( 'Sunday',
                                                              'Saturday' )
                                 THEN 1
                                 ELSE 0
                            END
                    AND di.statusCode & js.freq_relative_interval = js.freq_relative_interval
                    AND DATEDIFF(MONTH, js.startDate, di.infoDate)
                    % js.freq_recurrence_factor = 0;
--SELECT 'Insert monthly relative schedules' [x],* FROM #scheduleTimes;
 
-- Get the daily recurring schedule times
    INSERT  #scheduleTimes
            ( rowID ,
              infoDate ,
              startTime ,
              endTime ,
              waitSeconds
            )
            SELECT  st.rowID ,
                    st.infoDate ,
                    DATEADD(SECOND, tn.num * st.waitSeconds, st.startTime) ,
                    st.endTime ,
                    st.waitSeconds
            FROM    #scheduleTimes AS st
                    CROSS JOIN #tallyNumbers AS tn
            WHERE   tn.num * st.waitSeconds <= DATEDIFF(SECOND, st.startTime,st.endTime)
                    AND st.waitSeconds > 0;
--SELECT 'Insert daily recurring schedules' [x],* FROM #scheduleTimes;
 
-- Present the result
    SELECT  js.scheduleID ,
            js.serverName ,
            js.jobName ,
            js.jobDescription ,
            js.scheduleName ,
            js.categoryName ,
            CONVERT(DATE,st.infoDate) infoDate,
            CONVERT(CHAR(8),st.startTime, 108) startTime
    FROM    #scheduleTimes AS st
            INNER JOIN #jobSchedules AS js ON js.rowID = st.rowID
	WHERE	st.startTime BETWEEN @startDate AND @endDate
			AND js.jobEnabled = 1
            AND js.scheduleEnabled = 1;
	
	
	SELECT	js.scheduleID ,
            js.serverName ,
            js.jobName ,
            js.jobDescription ,
            js.scheduleName ,
			'Will run ' + x.HowManyTime + ' times between ' + CONVERT(VARCHAR(25),@startDate,120) + ' and ' + CONVERT(VARCHAR(25),@endDate,120) + '. ' + 
			eX.DiffTime
	FROM	#jobSchedules AS js	
			CROSS APPLY (SELECT CONVERT(VARCHAR(10),COUNT_BIG(1)) [HowManyTime] FROM #scheduleTimes AS st WHERE js.rowID = st.rowID AND st.startTime BETWEEN @startDate AND @endDate)x
			CROSS APPLY (SELECT TOP 1 'Every ' + CONVERT(VARCHAR(10),DATEDIFF(MINUTE,st.startTime ,ix.startTime)) + ' minute' [DiffTime]
						 FROM	#scheduleTimes AS st 
								CROSS APPLY (SELECT TOP 1 ist.startTime 
											 FROM	#scheduleTimes AS ist 
											 WHERE	js.rowID = ist.rowID AND ist.startTime BETWEEN @startDate AND @endDate
													AND ist.startTime > st.startTime
											 )ix
						WHERE	js.rowID = st.rowID 
								AND st.startTime BETWEEN @startDate AND @endDate)eX
	WHERE	js.jobEnabled = 1
            AND js.scheduleEnabled = 1;

-- Clean up
    DROP TABLE    #jobSchedules,
              #dayInformation,
              #scheduleTimes,
              #tallyNumbers;
END