USE [Netricity]
GO

/****** Object:  Table [dim].[UriStem]    Script Date: 9-3-2017 16:35:41 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

SET ANSI_PADDING ON
GO

CREATE TABLE [dim].[UriStem](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[UriStem] [varchar](255) NOT NULL,
	[PageType] [varchar](10) NOT NULL,
 CONSTRAINT [PK_UriStem2] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO

SET ANSI_PADDING OFF
GO

ALTER TABLE [dim].[UriStem] ADD  CONSTRAINT [DF_UriStem_PageType]  DEFAULT ('') FOR [PageType]
GO
