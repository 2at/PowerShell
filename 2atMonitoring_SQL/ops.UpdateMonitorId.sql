USE [Netricity]
GO

/****** Object:  StoredProcedure [ops].[UpdateMonitorId]    Script Date: 16-3-2017 15:43:38 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [ops].[UpdateMonitorId]	
	@HostId int,
	@UriStemId int,
	@MonitorId int	
AS
BEGIN
	UPDATE m
SET
	MonitorId=@MonitorId
FROM
	metrics.HTTPMonitoring m
	INNER JOIN (
		SELECT SessionId, StepNumber FROM
			metrics.HTTPMonitoring m 
		WHERE
			RowId IN ( SELECT MIN(RowId) MinRowId FROM metrics.HTTPMonitoring m GROUP BY SessionId, StepNumber)
			AND HostId=@HostId
			AND UriStemId=@UriStemId
			AND MonitorId IS NULL
	) r ON m.SessionId=r.SessionId AND m.StepNumber=r.StepNumber
END
GO

