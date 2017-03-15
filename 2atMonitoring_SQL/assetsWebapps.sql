USE [Netricity]
GO

/****** Object:  Table [assets].[WebApps]    Script Date: 9-3-2017 16:23:30 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [assets].[WebApps](
	[Id] [smallint] IDENTITY(1,1) NOT NULL,
	[WebAppNum] [int] NOT NULL,
	[Description] [varchar](255) NOT NULL,
	[ServerId] [int] NOT NULL,
 CONSTRAINT [PK_WebApps2] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [assets].[WebApps] ADD  CONSTRAINT [DF_WebApps_Description]  DEFAULT ('') FOR [Description]
GO

