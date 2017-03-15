USE [Netricity]
GO

/****** Object:  Table [metrics].[HTTPMonitoring]    Script Date: 9-3-2017 16:44:32 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [metrics].[HTTPMonitoring](
	[RowId] [int] IDENTITY(1,1) NOT NULL,
	[LogDateTime] [datetime] NOT NULL,
	[HostId] [int] NOT NULL,
	[UriStemId] [int] NOT NULL,
	[UriQueryId] [int] NOT NULL,
	[MethodId] [tinyint] NOT NULL,
	[WebRequestStatusId] [tinyint] NOT NULL,
	[HTTPStatus] [smallint] NOT NULL,
	[TimeTaken] [int] NOT NULL,
	[XSharePointHealthScore] [tinyint] NULL,
	[SPIisLatency] [int] NULL,
	[SPRequestDuration] [int] NULL,
	[ServerId] [int] NOT NULL,
	[ResponseLength] [int] NULL,
	[SessionId] [int] NULL,
	[StepNumber] [smallint] NULL,
	[RequestNumber] [smallint] NULL,
	[IsStepResult] [bit] NULL,
	[MonitorId] [smallint] NULL,
 CONSTRAINT [PK_HTTPMonitoring] PRIMARY KEY CLUSTERED 
(
	[RowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

ALTER TABLE [metrics].[HTTPMonitoring] ADD  CONSTRAINT [DF_HTTPMonitoring_ErrorId]  DEFAULT ((0)) FOR [WebRequestStatusId]
GO

