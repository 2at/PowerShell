USE [Netricity]
GO

/****** Object:  Table [ops].[MonitorSessions]    Script Date: 9-3-2017 16:40:10 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [ops].[MonitorSessions](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[JobDate] [datetime] NOT NULL,
	[Name] [varchar](255) NOT NULL,
	[Servers] [varchar](max) NOT NULL,
 CONSTRAINT [PK_MonitorSessions] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [ops].[MonitorSessions] ADD  CONSTRAINT [DF_Table_1_JobDaate]  DEFAULT (getdate()) FOR [JobDate]
GO

ALTER TABLE [ops].[MonitorSessions] ADD  CONSTRAINT [DF_MonitorSessions_Servers]  DEFAULT ('') FOR [Servers]
GO

