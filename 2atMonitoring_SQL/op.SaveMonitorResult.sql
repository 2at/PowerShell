USE [Netricity]
GO

/****** Object:  StoredProcedure [ops].[SaveMonitorResult]    Script Date: 16-3-2017 15:41:36 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [ops].[SaveMonitorResult]
	@LogDateTime datetime,
	@Host varchar(255),
	@UriStem varchar(255),
	@UriQuery varchar(255),
	@Method varchar(255),
	@HTTPStatus smallint,
	@TimeTaken int,
	@RequestStatus varchar(255),
	@XSharePointHealthScore tinyint=NULL,
	@SPIisLatency int=NULL,
	@SPRequestDuration int=NULL,
	@Server varchar(255)='',
	@Url varchar(800),
	@FormData varchar(max)=NULL,
	@RequestStatusDescription varchar(800)=NULL,
	@RawResponse varchar(max)=NULL,
	@RequestGuid varchar(100)=NULL,
	@SessionId int,
	@Monitor varchar(255)='',
	@StepNumber smallint,
	@RequestNumber smallint,
	@IsStepResult bit
AS
BEGIN
	DECLARE @HostId int
	DECLARE @UriStemId int
	DECLARE @UriQueryId int
	DECLARE @MonitorId int
	DECLARE @ServerId int
	DECLARE @MethodId tinyint
	DECLARE @WebRequestStatusId tinyint

	SELECT @HostId=id FROM dim.HTTPHost WHERE Host=@Host
	IF (@HostId IS NULL)
	BEGIN
		INSERT INTO dim.HTTPHost(Host) VALUES (@Host)
		SET @HostId=@@IDENTITY
	END

	SELECT @UriStemId=id FROM dim.UriStem WHERE UriStem=@UriStem
	IF (@UriStemId IS NULL)
	BEGIN
		INSERT INTO dim.UriStem(UriStem) VALUES (@UriStem)
		SET @UriStemId=@@IDENTITY
	END

	SELECT @UriQueryId=id FROM dim.UriQuery WHERE UriQuery=@UriQuery
	IF (@UriQueryId IS NULL)
	BEGIN
		INSERT INTO dim.UriQuery(UriQuery) VALUES (@UriQuery)
		SET @UriQueryId=@@IDENTITY
	END

	SELECT @MethodId=id FROM dim.HTTPMethod WHERE Method=@Method
	IF (@MethodId IS NULL)
	BEGIN
		INSERT INTO dim.HTTPMethod(Method) VALUES (@Method)
		SET @MethodId=@@IDENTITY
	END

	SELECT @WebRequestStatusId=id FROM dim.WebRequestStatus WHERE WebRequestStatus=@RequestStatus
	IF (@WebRequestStatusId IS NULL)
	BEGIN
		INSERT INTO dim.WebRequestStatus(WebRequestStatus) VALUES (@RequestStatus)
		SET @WebRequestStatusId=@@IDENTITY
	END

	SET @Monitor=COALESCE(@Monitor, '')
	IF (@Monitor IS NULL)
		SET @MonitorId=0
	ELSE
	BEGIN
		SELECT @MonitorId=id FROM assets.Monitors WHERE Name=@Monitor
		IF (@MonitorId IS NULL)
		BEGIN
			INSERT INTO assets.Monitors(Name) VALUES (@Monitor)
			SET @MonitorId=@@IDENTITY
		END
	END

	IF NOT EXISTS(SELECT MonitorId FROM ops.LatestMonitorState WHERE MonitorId=@MonitorId)
		INSERT INTO ops.LatestMonitorState(LogDateTime,HTTPStatus,HostId,MonitorId,Monitorname,WebRequestStatus) 
		VALUES (@LogDateTime,@HTTPStatus,@HostId,@MonitorId,@Monitor,@RequestStatus)			
	ELSE
		UPDATE ops.LatestMonitorState 
		SET LogDateTime = @LogDateTime, HTTPStatus = @HTTPStatus, HostId = @HostId, MonitorId = @MonitorId, Monitorname = @Monitor, WebRequestStatus = @RequestStatus
		WHERE MonitorId = @MonitorId

	SET @Server=COALESCE(@Server, '')
	SELECT @ServerId=id FROM assets.IISServers WHERE Servername=@Server
	IF (@ServerId IS NULL)
	BEGIN
		INSERT INTO assets.IISServers(Servername) VALUES (@Server)
		SET @ServerId=@@IDENTITY
	END

	INSERT INTO metrics.HTTPMonitoring(LogDateTime, HostId, UriStemId, UriQueryId, MethodId, HTTPStatus, TimeTaken, WebRequestStatusId, XSharePointHealthScore, SPIisLatency, SPRequestDuration, ServerId, ResponseLength, SessionId, StepNumber, RequestNumber, IsStepResult, MonitorId)
	VALUES (@LogDateTime, @HostId, @UriStemId, @UriQueryId, @MethodId, @HTTPStatus, @TimeTaken, @WebRequestStatusId, @XSharePointHealthScore, @SPIisLatency, @SPRequestDuration, @ServerId, DATALENGTH(@RawResponse), @SessionId, @StepNumber, @RequestNumber, @IsStepResult, @MonitorId)

	IF (@WebRequestStatusId<>18)
		INSERT INTO logs.FullRequests (MonitoringRowId, LogDateTime, Method, Url, FormData, WebRequestStatus, WebRequestStatusDescription, HTTPStatus, RawResponse, RequestGuid)
		VALUES (@@IDENTITY, @LogDateTime, @Method, @Url, @FormData, @RequestStatus, @RequestStatusDescription, @HTTPStatus, @RawResponse, @RequestGuid)

	-- Extra code om SLA rapportage te doen over perioden van 5 minuten
              
	IF (@IsStepResult = 1 AND @MonitorId <> 0)
		BEGIN
			DECLARE @Time5m datetime = DATEADD(mi, DATEDIFF(mi, 0, @LogDateTime)/5*5, 0)
			DECLARE @Up int = CASE WHEN @WebRequestStatusId = 18 THEN 1 ELSE 0 END

			INSERT INTO ops.UpDownTime(Time5m, MonitorId, UpCount, DownCount)
            SELECT @Time5m, @MonitorID, @Up, 1-@Up WHERE NOT EXISTS (SELECT Time5m FROM ops.UpDownTime WHERE Time5m = @Time5m AND MonitorID = @MonitorID)

			IF (@@ROWCOUNT = 0)
				UPDATE ops.UpDownTime
				SET UpCount = UpCount + @Up, DownCount = DownCount + 1 - @Up
				WHERE Time5m = @Time5m AND MonitorID = @MonitorID
              END

END
GO

