USE [Netricity]
GO

/****** Object:  Table [dim].[WebRequestStatus]    Script Date: 9-3-2017 16:37:25 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dim].[WebRequestStatus](
	[Id] [tinyint] IDENTITY(1,1) NOT NULL,
	[WebRequestStatus] [varchar](50) NOT NULL,
	[Description] [varchar](500) NOT NULL,
 CONSTRAINT [PK_HTTPRequestError] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [dim].[WebRequestStatus] ADD  CONSTRAINT [DF_WebRequestStatus_Description]  DEFAULT ('') FOR [Description]
GO

