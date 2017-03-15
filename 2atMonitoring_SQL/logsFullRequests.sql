USE [Netricity]
GO

/****** Object:  Table [logs].[FullRequests]    Script Date: 9-3-2017 16:38:26 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [logs].[FullRequests](
	[RowId] [int] IDENTITY(1,1) NOT NULL,
	[MonitoringRowId] [int] NOT NULL,
	[LogDateTime] [datetime] NOT NULL,
	[Method] [nchar](20) NOT NULL,
	[Url] [varchar](800) NOT NULL,
	[FormData] [varchar](max) NULL,
	[WebRequestStatus] [varchar](50) NOT NULL,
	[WebRequestStatusDescription] [varchar](800) NULL,
	[HTTPStatus] [smallint] NULL,
	[RawResponse] [varchar](max) NULL,
	[RequestGuid] [varchar](100) NULL,
	[Monitor] [varchar](255) NULL,
 CONSTRAINT [PK_FullRequests] PRIMARY KEY CLUSTERED 
(
	[RowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

