USE [Netricity]
GO

/****** Object:  StoredProcedure [ops].[SaveMonitorSession]    Script Date: 16-3-2017 15:42:04 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [ops].[SaveMonitorSession]
	@Name varchar(255),
	@Servers varchar(max)
AS
BEGIN
	INSERT INTO ops.MonitorSessions(Name, Servers)
	VALUES (@Name, @Servers)

	SELECT @@IDENTITY SessionId
END
GO

