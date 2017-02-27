Set-StrictMode -Version 2.0

Add-Type -Assembly System.Web

Add-Type -Path "$PSScriptRoot\HtmlAgilityPack.dll"
[HtmlAgilityPack.HtmlNode]::ElementsFlags.Remove("form") | Out-Null

Import-Module "$PSScriptRoot\2atWeb.psm1" -Force -Verbose:$false
Import-Module "$PSScriptRoot\2atGeneral.psm1" -Force -Verbose:$false

Function RelToAbs {
	Param(
		[Parameter(Mandatory=$true)]
		[ValidateScript({(New-Object System.Uri $_)})]
		[string]$BaseUrl,
		
		[Parameter(Mandatory=$true)]
		[string]$RelativeUrl,
		
		[switch]$NoHtmlDecode
	)
	if (! $NoHtmlDecode) { $RelativeUrl = [System.Web.HttpUtility]::HtmlDecode($RelativeUrl) }

	if ([System.Uri]::IsWellFormedUriString($RelativeUrl,[System.UriKind]::Absolute)) { return $RelativeUrl }
	
	if ([System.Uri]::IsWellFormedUriString($RelativeUrl,[System.UriKind]::Relative)) {
		$l = (New-Object System.Uri((New-Object System.Uri $BaseUrl), $RelativeUrl)).AbsoluteUri
		Write-Verbose "Absolute URL is $l"
		return $l
	}
	
	throw "RelativeUrl is not a valid (absolute or relative) url: '$RelativeUrl'"
}

Function Step {
	Param(
		[Parameter(Mandatory=$true)]
		[ValidateScript({(New-Object System.Uri $_)})]
		[string]$Url,
				
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session,
		
		[string]$Method = 'GET',
		
		[ValidateScript({ $_ -is [HashTable] -or $_ -is [System.Collections.Generic.Dictionary[string,string]] })]
		[object]$FormData
	)
	
	$res = Get-WebResponse -Url $Url -Method $Method -FormData $FormData -CookieContainer $Session.CookieContainer -Proxy $Session.Proxy -UserAgent 'Mozilla/5.0 (2AT Monitoring; +http://2at.nl)' -Credentials $Session.Credentials
	
	if ($Session.History | ?{ $Url -eq $_.Url -and $Method -eq $_.Method -and $res.ResponseBody -eq $_.ResponseBody }) {
		$res.WebRequestStatus='LoopDetected'
		$res.WebRequestStatusDescription="The same URL was already visited on the same Step and received the same ResponseBody. ($Url)"
	}
	
	$Session.History += $res
	
	if ($res.WebRequestStatus -eq [System.Net.WebExceptionStatus]::Success) {
		if ($res.HTTPStatus -In (301, 302, 303, 307)) {
			$l = RelToAbs -BaseUrl $url -RelativeUrl $res.ResponseHeaders['Location'] -NoHtmlDecode
			Write-Verbose "REDIRECT ($($res.HTTPStatus)) -> $l"
			Step -Url $l -Session $Session
			return
		}
		
		if ($res.HTTPStatus -eq 200) {
			if ($res.ResponseBody.EndsWith('<noscript><p>Script is disabled. Click Submit to continue.</p><input type="submit" value="Submit" /></noscript></form><script language="javascript">window.setTimeout(''document.forms[0].submit()'', 0);</script></body></html>')) {
				Write-Verbose "ADFS auto POST"
				ProcessForm -Previous $res -Session $Session
				return
			}
			
			$u = (new-object System.Uri $res.Url).GetLeftPart([System.UriPartial]::Path)
			if ($Session.LoginSteps[$u]) {
				RunStep -Step $Session.LoginSteps[$u] -Previous $res -Session $Session
				return
			}
		}
	}
}

Function ProcessForm {
	Param(
		[HashTable]$FormData,

		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Previous,
		
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session
	)
	
	$htmldoc = New-Object HtmlAgilityPack.HtmlDocument
	$htmldoc.LoadHtml($Previous.ResponseBody)
	$form = $htmldoc.DocumentNode.SelectNodes('//form')[0]
	$l = RelToAbs $Previous.Url $form.Attributes['action'].Value

	$b = New-Object 'System.Collections.Generic.Dictionary[string,string]'
	$form.SelectNodes('//input') | ?{ $_.Attributes['name'] -And $_.Attributes['value'] } | %{ 
		$b[$_.Attributes['name'].Value] = [System.Web.HttpUtility]::HtmlDecode($_.Attributes['value'].Value)
	}
	if ($FormData) { $FormData.Keys | %{ $b[$_]=$FormData[$_] } }
	
	Write-Verbose "FORM: $(($b.Keys | %{ $_ + '=' + $b[$_] } ) -join [Environment]::NewLine)"
	Step -Url $l -Method $form.Attributes['method'].Value -FormData $b -Session $Session
}

Function ProcessLink {
	Param(
		[Parameter(Mandatory=$true)]
		[string]$LinkText,

		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Previous,
		
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session
	)
	
	$htmldoc = New-Object HtmlAgilityPack.HtmlDocument
	$htmldoc.LoadHtml($Previous.ResponseBody)
	$links = $htmldoc.DocumentNode.SelectNodes('//a[@href]') | ?{ $_ -and $_.InnerText.Trim() -eq $LinkText } | %{ $_.Attributes['href'].Value } | select -Unique

	$c = ($links | measure).Count
	if ($c -ne 1) { 
		Write-Warning "Found $c links matching '$LinkText', expected exactly one."
		$Previous.WebRequestStatus='LinkFailed'
		$Previous.WebRequestStatusDescription="Found $c links matching '$LinkText', expected exactly one."
		return
	}

	$l = RelToAbs $Previous.Url $links
	Write-Verbose "LINK: $l"
	
	Step -url $l -Session $Session
}

Function UpdateSession {
	Param(
		[Parameter(Mandatory=$true)]	
		[HashTable]$Step,
		
		[Parameter(Mandatory=$true)]	
		[PSCustomObject]$Session,
		
		[PSCustomObject]$TMGInfo,
		
		[Switch]$IsNewSession
	)
	Write-Debug "Updating $(if($IsNewSession) {'NEW'})session"
	
	if (!$IsNewSession -and ($Step['SqlConnection'] -or $Step['Name'])) { throw 'Specifying a SqlConnection or Name is only supported for new sessions' }

	if ($Step['Proxy']) { $Session.Proxy = New-Object System.Net.WebProxy $Step.Proxy	}
	if ($Step['LoginSteps']) { $Session.LoginSteps = $Step.LoginSteps }
	if ($Step['Servers']) { SetSessionCookies -Session $Session -TMGInfo $TMGInfo -Servers $Step.Servers }
	if ($Step['Credentials']) {
		if ($Step.Credentials -is [PSCredential]) {
			$Session.Credentials = $Step.Credentials.GetNetworkCredential()
		} elseif ($Step.Credentials -is [System.Net.ICredentials]) {
			$Session.Credentials = $Step.Credentials
		} else {
			throw "Session credentials specified are of an unsupported type: $($Step.Credentials.GetType().FullName), please use either a PSCredential or a NetworkCredential"
		}
	}
	
	if ($IsNewSession) { $Session }
}

Function NewSession {
	Param(
		[Parameter(Mandatory=$true)]	
		[HashTable]$Step,
		
		[PSCustomObject]$TMGInfo
	)
	
	$Session = @{
		Id=-1
		Name=$Step['Name']
		CookieContainer = New-Object System.Net.CookieContainer
		Proxy=$null
		SqlConnection=$Step['SqlConnection']
		LoginSteps=@{}
		Credentials=$null
		History=@()
		RequestNumber=1
		Monitor=if ($Step['Monitor']) { $Step.Monitor } else { @{} }
	}	

	if ($Session.SqlConnection) {
		Write-Verbose "NEWSESSION: Connecting to SQL '$($Step.SqlConnection)'"
		
		Import-Module "$PSScriptRoot\2atSql.psm1" -Force -Verbose:$false
		Set-SqlData -ConnectionString $Session.SqlConnection -CommandText 'ops.LogJob' -Parameters @{ Job='HTTPMonitor'; Title='Job started' }
		$MonitorSession = Get-SqlData -ConnectionString $Session.SqlConnection -CommandText 'ops.SaveMonitorSession' -Parameters @{ Name=$Session.Name; Servers=($Step['Servers'] -Join ' / ') }
		$Session.Id = $MonitorSession.SessionId
	}

	if (!$Step['Servers']) { Write-Verbose 'NEWSESSION: New session created without cookies' }
	
	UpdateSession -Step $Step -Session ([PSCustomObject]$Session) -TMGInfo $TMGInfo -IsNewSession
}

Function SetSessionCookies {
	Param(
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session,

		[Parameter(Mandatory=$true)]
		[PSCustomObject]$TMGInfo,

		[Parameter(Mandatory=$true)]
		[string[]]$Servers
	)

	$TMGInfo.CookieIndex | %{
		$cookieName = $_.Cookie
		$Url = New-Object System.Uri $_.Url

		$rule = $TMGInfo.Rules[$cookieName.SubString(7)]

		if (! $rule) {
			Write-Warning "Unable to add cookie to session. No matching rule found for cookie '$cookieName' ($Url). Possible cause is an outdated TMGRuleGUIDs.xml file." 
			return
		}
		
		foreach($server in $Servers) {
			$entry = $rule.ServerFarm | ?{ $_.HostName -Match $server }
			if ($entry) { break }
		}
		if (! $entry) { 
			Write-Warning "Unable to add cookie to session. No matching server found for rule '$($rule.Name)' ($Url)"
			return
		}
		
		$cookie = New-Object System.Net.Cookie $cookieName, $entry.GUID, '/', $Url.Host
		$cookie.HttpOnly = $true
		
		$Session.CookieContainer.Add($Url, $cookie)

		Write-Verbose "Added cookie to session: $cookieName=$($entry.GUID) ($Url)"
	}
}

Function ValidateResponse {
	Param(
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Response,
		
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Validate
	)

	if ($Response.WebRequestStatus -ne [System.Net.WebExceptionStatus]::Success) { 
		Write-Verbose "Skipped validation because request already marked as failed ($($Response.WebRequestStatus)"
		return
	}
	
	if ($Validate['Url']) {
		if ($Response.Url.TrimEnd('/') -ne $Validate.Url.TrimEnd('/')) {
			$Response.WebRequestStatus='UrlValidationFailed'
			$Response.WebRequestStatusDescription="Url validation failed, found '$($Response.Url)', expected '$($Validate.Url)'"
			Write-Warning $Response.WebRequestStatusDescription
			return
		} else {
			Write-Verbose 'Url validation succeeded'
		}
	}
	if ($Validate['ContentMatch']) {
		if (! ($Response.ResponseBody -match $Validate.ContentMatch)) {
			$Response.WebRequestStatus='ContentValidationFailed'
			$Response.WebRequestStatusDescription="Content validation failed, page '$($Response.Url)' does not match '$($Validate.ContentMatch)'"
			Write-Warning $Response.WebRequestStatusDescription
		} else {
			Write-Verbose "Content validation succeeded '$($Validate.ContentMatch)'"
		}
	}
	if ($Validate['Time']) {
		if (! ([int]$Response.TimeToFirstByte.TotalMilliseconds -le [int]$Validate.Time)) {
			$Response.WebRequestStatus='ContentValidationFailed'
			$Response.WebRequestStatusDescription="Time exceeded, page took $([int]$Response.TimeToFirstByte.TotalMilliseconds)ms, maximum was set at $([int]$Validate.Time)ms ($($Response.Url))"
			Write-Warning $Response.WebRequestStatusDescription
		} else {
			Write-Verbose "Time validation succeeded ($([int]$Response.TimeToFirstByte.TotalMilliseconds)ms < $([int]$Validate.Time)ms)"
		}
	}

}

Function LogSteps {
	Param(
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session,
		
		[int]
		$StepNumber,
		[PSCustomObject]$Monitor,
		
		[switch]
		$PassThru
	)
	
	$i=1
	foreach($WebResponse in $Session.History) {
		$u = New-Object System.Uri $WebResponse.Url
		$hostname = "$($u.Host)"
		if ($u.Port -ne 80) { $hostname+=":$($u.Port)"}
		if ($u.Query.Length -ne 0) { $query=$u.Query.Substring(1) } else { $query='' } 

		$p = @{
			LogDateTime=$WebResponse.DateTime
			Host=$hostname
			UriStem=$u.AbsolutePath
			UriQuery=$query
			Method=$WebResponse.Method
			HTTPStatus=[int]$WebResponse.HTTPStatus
			TimeTaken=[int]$WebResponse.TimeToFirstByte.TotalMilliseconds
			RequestStatus=[string]$WebResponse.WebRequestStatus
			RequestStatusDescription=$WebResponse.WebRequestStatusDescription
			Url=$WebResponse.Url
			SessionId=$Session.Id
			Monitor=$Monitor
			StepNumber=$StepNumber
			RequestNumber=$Session.RequestNumber++
			IsStepResult=($i -eq $Session.History.Count)
		}

		if ($WebResponse.FormData) {
			$p.FormData=(($WebResponse.FormData.Keys | %{ $_ + '=' + $WebResponse.FormData[$_] } ) -join [Environment]::NewLine)
		}
		
		if ($WebResponse.ResponseHeaders) {
			$p.Server = $WebResponse.ResponseHeaders['X-WFE']
			if (! $p.Server) { $p.Server = $WebResponse.ResponseHeaders['X-Powered-by-server'] }
			
			$p.XSharePointHealthScore=$WebResponse.ResponseHeaders['X-SharePointHealthScore']
			$p.SPIisLatency=$WebResponse.ResponseHeaders['SPIisLatency']
			$p.SPRequestDuration=$WebResponse.ResponseHeaders['SPRequestDuration']
			$p.RequestGuid=$WebResponse.ResponseHeaders['request-id']
			$p.RawResponse=Get-WebResponseString -WebResponse $WebResponse
		}
		
		if ($Session.SqlConnection) {
			Set-SqlData -ConnectionString $Session.SqlConnection -CommandText 'ops.SaveMonitorResult' -Parameters $p
		} else {
			if ($p.HTTPStatus) {
				Write-Host "$(Get-Date) $($p.Server) ($($p.XSharePointHealthScore)) $($p.HTTPStatus) $($p.Method) $($u.GetLeftPart([System.UriPartial]::Path))"
			} else {
				Write-Host "$(Get-Date) $($p.RequestStatus) $($u.GetLeftPart([System.UriPartial]::Path))"
			}
		}
		
		if ($PassThru) { $WebResponse }
		$i++
	}
}

Function RunStep {
	Param(
		[Parameter(Mandatory=$true)]
		[HashTable]$Step,
		
		[PSCustomObject]$Previous,
		
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$Session
	)
		
	switch ($Step.Action)
	{
		'Url'	{
			Write-Debug "URL: $($Step.Url)"
			Step -Url $Step.Url -Session $Session
		}
		'Link'	{
			Write-Debug "LINK: $($Step.LinkText)"
			ProcessLink -LinkText $Step.LinkText -Previous $Previous -Session $Session
		}
		'Form'	{
			Write-Debug "FORM"
			ProcessForm -FormData $Step['FormData'] -Previous $Previous -Session $Session
		}
		default {
			throw "Unrecognized step $($CurrentStep.Action)"
		}
	}

	if ($Step['Validate']) {
		ValidateResponse -Response $Session.History[$Session.History.Length-1] -Validate $Step.Validate
	}
}

Function Invoke-Monitoring {
	Param(
		[Parameter(Mandatory=$true)]
		[System.Array]$Steps,

		[PSCustomObject]$TMGInfo
	)
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	$i=0
	foreach($CurrentStep in $Steps) {
		switch ($CurrentStep.Action) {
			'NewSession' {
				Write-Progress -Activity 'Initializing session' -PercentComplete (100*$i/$Steps.Count)
				Write-Debug 'NEWSESSION'
				
				$Session = NewSession -Step $CurrentStep -TMGInfo $TMGInfo								
				$Previous = $null
			}
			'UpdateSession' {
				Write-Progress -Activity 'Updating session' -PercentComplete (100*$i/$Steps.Count)
				Write-Debug 'UPDATESESSION'

				UpdateSession -Step $CurrentStep -TMGInfo $TMGInfo -Session $Session
			}
			default {
				Write-Progress -Activity 'Retreiving webpage' -CurrentOperation $CurrentStep.Url -PercentComplete (100*$i/$Steps.Count)

				$Monitor = "";
				if ($CurrentStep['Monitor']) { $Monitor = $CurrentStep.Monitor }
				RunStep -Step $CurrentStep -Previous $Previous -Session $Session
				LogSteps -Session $Session -StepNumber ($i+1) -Monitor $Monitor -PassThru
				$Previous = $Session.History | Select -Last 1
				$Session.History=@()
			}
		}
		
		$i++
	}
}

Export-ModuleMember -Function Get-*
Export-ModuleMember -Function Set-*
Export-ModuleMember -Function Invoke-*
