USE [Netricity]
GO

/****** Object:  View [helper].[SURFnetUpTimeReport]    Script Date: 23-3-2017 10:15:38 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE VIEW [helper].[SURFnetUpTimeReport]
AS
SELECT   Name, DATE, PERIOD, SUM(UP) * 5 AS UP, SUM(DOWN) * 5 AS DOWN
FROM     (SELECT   assets.Monitors.Name, ops.UpDownTime.Time5m, ops.UpDownTime.UpCount, ops.UpDownTime.DownCount,
                               (SELECT   CONVERT(date, ops.UpDownTime.Time5m) AS Expr1) AS DATE,
                               (SELECT   CASE WHEN ops.UpDownTime.UpCount = 0 THEN 0 ELSE 1 END AS Expr1) AS UP,
                               (SELECT   CASE WHEN ops.UpDownTime.UpCount = 0 THEN 1 ELSE 0 END AS Expr1) AS DOWN,
                               (SELECT   CASE WHEN
                                                (SELECT   CONVERT(time, ops.UpDownTime.Time5m, 108)) BETWEEN '07:00:00' AND '18:59:59' THEN '7:00-19:00' ELSE '19:00-7:00' END AS Expr1) AS PERIOD
             FROM      assets.Monitors INNER JOIN
                           ops.UpDownTime ON assets.Monitors.Id = ops.UpDownTime.MonitorID
             WHERE    (assets.Monitors.Id IN ('18', '19', '20'))) AS a
GROUP BY DATE, PERIOD, Name

GO

EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPane1', @value=N'[0E232FF0-B466-11cf-A24F-00AA00A3EFFF, 1.00]
Begin DesignProperties = 
   Begin PaneConfigurations = 
      Begin PaneConfiguration = 0
         NumPanes = 4
         Configuration = "(H (1[40] 4[20] 2[20] 3) )"
      End
      Begin PaneConfiguration = 1
         NumPanes = 3
         Configuration = "(H (1 [50] 4 [25] 3))"
      End
      Begin PaneConfiguration = 2
         NumPanes = 3
         Configuration = "(H (1 [50] 2 [25] 3))"
      End
      Begin PaneConfiguration = 3
         NumPanes = 3
         Configuration = "(H (4 [30] 2 [40] 3))"
      End
      Begin PaneConfiguration = 4
         NumPanes = 2
         Configuration = "(H (1 [56] 3))"
      End
      Begin PaneConfiguration = 5
         NumPanes = 2
         Configuration = "(H (2 [66] 3))"
      End
      Begin PaneConfiguration = 6
         NumPanes = 2
         Configuration = "(H (4 [50] 3))"
      End
      Begin PaneConfiguration = 7
         NumPanes = 1
         Configuration = "(V (3))"
      End
      Begin PaneConfiguration = 8
         NumPanes = 3
         Configuration = "(H (1[56] 4[18] 2) )"
      End
      Begin PaneConfiguration = 9
         NumPanes = 2
         Configuration = "(H (1 [75] 4))"
      End
      Begin PaneConfiguration = 10
         NumPanes = 2
         Configuration = "(H (1[66] 2) )"
      End
      Begin PaneConfiguration = 11
         NumPanes = 2
         Configuration = "(H (4 [60] 2))"
      End
      Begin PaneConfiguration = 12
         NumPanes = 1
         Configuration = "(H (1) )"
      End
      Begin PaneConfiguration = 13
         NumPanes = 1
         Configuration = "(V (4))"
      End
      Begin PaneConfiguration = 14
         NumPanes = 1
         Configuration = "(V (2))"
      End
      ActivePaneConfig = 0
   End
   Begin DiagramPane = 
      Begin Origin = 
         Top = 0
         Left = 0
      End
      Begin Tables = 
         Begin Table = "a"
            Begin Extent = 
               Top = 9
               Left = 57
               Bottom = 206
               Right = 295
            End
            DisplayFlags = 280
            TopColumn = 0
         End
      End
   End
   Begin SQLPane = 
   End
   Begin DataPane = 
      Begin ParameterDefaults = ""
      End
      Begin ColumnWidths = 9
         Width = 284
         Width = 1000
         Width = 1000
         Width = 1000
         Width = 1000
         Width = 1000
         Width = 1000
         Width = 1000
         Width = 1000
      End
   End
   Begin CriteriaPane = 
      Begin ColumnWidths = 12
         Column = 1440
         Alias = 900
         Table = 1170
         Output = 720
         Append = 1400
         NewValue = 1170
         SortType = 1350
         SortOrder = 1410
         GroupBy = 1350
         Filter = 1350
         Or = 1350
         Or = 1350
         Or = 1350
      End
   End
End
' , @level0type=N'SCHEMA',@level0name=N'helper', @level1type=N'VIEW',@level1name=N'SURFnetUpTimeReport'
GO

EXEC sys.sp_addextendedproperty @name=N'MS_DiagramPaneCount', @value=1 , @level0type=N'SCHEMA',@level0name=N'helper', @level1type=N'VIEW',@level1name=N'SURFnetUpTimeReport'
GO

