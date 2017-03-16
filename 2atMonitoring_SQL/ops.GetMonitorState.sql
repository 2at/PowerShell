USE [Netricity]
GO

/****** Object:  StoredProcedure [ops].[GetMonitorState]    Script Date: 16-3-2017 15:44:47 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [ops].[GetMonitorState]
AS
BEGIN 

SELECT m.*
FROM ops.LatestMonitorState m
INNER JOIN assets.Monitors ON assets.Monitors.Id = m.MonitorId 
WHERE assets.Monitors.ShowInDashboard = 1
ORDER BY
    m.MonitorId ASC
END
GO

