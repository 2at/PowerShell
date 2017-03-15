USE [Netricity]
GO

/****** Object:  Table [assets].[Monitors]    Script Date: 9-3-2017 16:23:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [assets].[Monitors](
	[Id] [smallint] IDENTITY(1,1) NOT NULL,
	[Name] [varchar](255) NOT NULL,
	[ShowInDashboard] [bit] NOT NULL,
 CONSTRAINT [PK_Monitors] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [assets].[Monitors] ADD  CONSTRAINT [DF_Monitors_ShowInDashboard]  DEFAULT ((1)) FOR [ShowInDashboard]
GO

