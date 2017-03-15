USE [Netricity]
GO

/****** Object:  Table [ops].[LatestMonitorState]    Script Date: 9-3-2017 16:34:11 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [ops].[LatestMonitorState](
	[LogDateTime] [datetime] NOT NULL,
	[HTTPStatus] [int] NOT NULL,
	[HostId] [int] NOT NULL,
	[MonitorId] [int] NOT NULL,
	[Monitorname] [varchar](255) NULL,
	[WebRequestStatus] [varchar](255) NULL
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

