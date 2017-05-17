#region Init and modules
#Requires -Version 4.0
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -Assembly System.Web

Function Import-WebModule {
	Param(
		[Parameter(Mandatory=$true)]
		$Uri
	)

	$tempfile = "$Env:TEMP\$(([Uri]$Uri).AbsolutePath.Replace('/','_'))"

	Invoke-WebRequest -Uri $Uri -OutFile $tempfile
	Add-Content $tempfile -Stream Zone.Identifier [ZoneTransfer]`r`nZoneId=3
	Import-Module $tempfile -Force -Verbose:$false
	Remove-Item $tempfile
}

Import-WebModule http://ps.2at.nl/2017/04/2atWeb.psm1
Import-WebModule http://ps.2at.nl/2017/04/2atGeneral.psm1

Import-WebAssembly -Uri http://ps.2at.nl/2017/04/HtmlAgilityPack.dll -Thumbprint '58C253241303FAFEB6476CC88FD5A1D161365639'
[HtmlAgilityPack.HtmlNode]::ElementsFlags.Remove("form") | Out-Null
#endregion

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
	
	$res = Get-WebResponse -Url $Url -Method $Method -FormData $FormData -CookieContainer $Session.CookieContainer -Proxy $Session.Proxy -UserAgent 'Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; WOW64; Trident/6.0; 2AT Monitoring; +http://2at.nl)' -Credentials $Session.Credentials
	
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
		
		Import-WebModule http://ps.2at.nl/2017/04/2atSql.psm1
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
		
		[string]$Monitor,
		
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

				RunStep -Step $CurrentStep -Previous $Previous -Session $Session
				LogSteps -Session $Session -StepNumber ($i+1) -Monitor $CurrentStep['Monitor'] -PassThru
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



# SIG # Begin signature block
# MIIapQYJKoZIhvcNAQcCoIIaljCCGpICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUaPOET3Zw17negp8I5m1jTpYA
# SoigghWUMIIEmTCCA4GgAwIBAgIPFojwOSVeY45pFDkH5jMLMA0GCSqGSIb3DQEB
# BQUAMIGVMQswCQYDVQQGEwJVUzELMAkGA1UECBMCVVQxFzAVBgNVBAcTDlNhbHQg
# TGFrZSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxITAfBgNV
# BAsTGGh0dHA6Ly93d3cudXNlcnRydXN0LmNvbTEdMBsGA1UEAxMUVVROLVVTRVJG
# aXJzdC1PYmplY3QwHhcNMTUxMjMxMDAwMDAwWhcNMTkwNzA5MTg0MDM2WjCBhDEL
# MAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UE
# BxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxKjAoBgNVBAMT
# IUNPTU9ETyBTSEEtMSBUaW1lIFN0YW1waW5nIFNpZ25lcjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBAOnpPd/XNwjJHjiyUlNCbSLxscQGBGue/YJ0UEN9
# xqC7H075AnEmse9D2IOMSPznD5d6muuc3qajDjscRBh1jnilF2n+SRik4rtcTv6O
# KlR6UPDV9syR55l51955lNeWM/4Og74iv2MWLKPdKBuvPavql9LxvwQQ5z1IRf0f
# aGXBf1mZacAiMQxibqdcZQEhsGPEIhgn7ub80gA9Ry6ouIZWXQTcExclbhzfRA8V
# zbfbpVd2Qm8AaIKZ0uPB3vCLlFdM7AiQIiHOIiuYDELmQpOUmJPv/QbZP7xbm1Q8
# ILHuatZHesWrgOkwmt7xpD9VTQoJNIp1KdJprZcPUL/4ygkCAwEAAaOB9DCB8TAf
# BgNVHSMEGDAWgBTa7WR0FJwUPKvdmam9WyhNizzJ2DAdBgNVHQ4EFgQUjmstM2v0
# M6eTsxOapeAK9xI1aogwDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwQgYDVR0fBDswOTA3oDWgM4YxaHR0cDovL2Ny
# bC51c2VydHJ1c3QuY29tL1VUTi1VU0VSRmlyc3QtT2JqZWN0LmNybDA1BggrBgEF
# BQcBAQQpMCcwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0cnVzdC5jb20w
# DQYJKoZIhvcNAQEFBQADggEBALozJEBAjHzbWJ+zYJiy9cAx/usfblD2CuDk5oGt
# Joei3/2z2vRz8wD7KRuJGxU+22tSkyvErDmB1zxnV5o5NuAoCJrjOU+biQl/e8Vh
# f1mJMiUKaq4aPvCiJ6i2w7iH9xYESEE9XNjsn00gMQTZZaHtzWkHUxY93TYCCojr
# QOUGMAu4Fkvc77xVCf/GPhIudrPczkLv+XZX4bcKBUCYWJpdcRaTcYxlgepv84n3
# +3OttOe/2Y5vqgtPJfO44dXddZhogfiqwNGAwsTEOYnB9smebNd0+dmX+E/CmgrN
# Xo/4GengpZ/E8JIh5i15Jcki+cPwOoRXrToW9GOUEB1d0MYwggUzMIIEG6ADAgEC
# AhEAgNHe/U3DBzyckFGAgIDcJDANBgkqhkiG9w0BAQsFADB9MQswCQYDVQQGEwJH
# QjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3Jk
# MRowGAYDVQQKExFDT01PRE8gQ0EgTGltaXRlZDEjMCEGA1UEAxMaQ09NT0RPIFJT
# QSBDb2RlIFNpZ25pbmcgQ0EwHhcNMTcwMTEzMDAwMDAwWhcNMjAwMTEzMjM1OTU5
# WjCBgDELMAkGA1UEBhMCTkwxEDAOBgNVBBEMBzM1NDIgRFoxEDAOBgNVBAgMB1V0
# cmVjaHQxEDAOBgNVBAcMB1V0cmVjaHQxFTATBgNVBAkMDEVuZXJnaWV3ZWcgMTER
# MA8GA1UECgwIMkFUIEIuVi4xETAPBgNVBAMMCDJBVCBCLlYuMIIBIjANBgkqhkiG
# 9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzB3KZ2CBenaD2WDwOsy0cHE6mLIeIYqWP718
# FuWeUZ5eejvw8BozajbtBWgISZ2IMsTYZ1I7KFBzHgXXkNglmyboa6++x7j2Ws+T
# 0hmHCUZ64AFbOkXjqYsOBCPhi3yuKIRLwc4snA3F3DCH24mBpDYymrU22+0vMIlD
# qpzRXBNEeIhGss3jehu86l85fWVS54F5KGeDYQ2BT0Tc0UO6hMlcpCEVKIbthLm3
# 6q1/oSchRYjHB4JCT1KqACRhD0hJcQmTcJZvhpgOrglUVlj1ClS5xfWgHq3ySShO
# OZMecl0VNMtYxNi5TF1Ae+sie4044ioyGB6dGItGXwhObIk/9wIDAQABo4IBqDCC
# AaQwHwYDVR0jBBgwFoAUKZFg/4pN+uv5pmq4z/nmS71JzhIwHQYDVR0OBBYEFDHc
# 2o80OMg8zNfFWMH8QB57E7rnMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAA
# MBMGA1UdJQQMMAoGCCsGAQUFBwMDMBEGCWCGSAGG+EIBAQQEAwIEEDBGBgNVHSAE
# PzA9MDsGDCsGAQQBsjEBAgEDAjArMCkGCCsGAQUFBwIBFh1odHRwczovL3NlY3Vy
# ZS5jb21vZG8ubmV0L0NQUzBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsLmNv
# bW9kb2NhLmNvbS9DT01PRE9SU0FDb2RlU2lnbmluZ0NBLmNybDB0BggrBgEFBQcB
# AQRoMGYwPgYIKwYBBQUHMAKGMmh0dHA6Ly9jcnQuY29tb2RvY2EuY29tL0NPTU9E
# T1JTQUNvZGVTaWduaW5nQ0EuY3J0MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5j
# b21vZG9jYS5jb20wGQYDVR0RBBIwEIEOc3VwcG9ydEAyYXQubmwwDQYJKoZIhvcN
# AQELBQADggEBAHGDJyOKLJwzdt4Y8ow7H4ZKZXs9Hopf0GhizzhcPWyWL7GI6QHh
# KHzFWYGsFhh2vesuY7p89jthK5YqSn1u2KUQuLWzQZQj3cZCK2BwSz6FpgmmjqIo
# 49qCfKIB5IrEDcZAQPC9wxaXPI+R3B32JmTllBpkFQNTIJVcB7jR/Ft991iV17tM
# Mq0GssMAHnVd/yvTWlUaE7XNtgtNYQ5v/8HxxNtdBXsIbdjiv/A8GjUmyPN8Dum9
# CW82hUqOE7U9AXHZIBWy9yrooSieo26GA1OzrBvnDc+L42JZnjvwdhBqSnbQrSS7
# L6VjVHU+Ct84Fnb5u23Jypdmj9123Hw9qJwwggXYMIIDwKADAgECAhBMqvnK22Nv
# 4B/3TthbA4adMA0GCSqGSIb3DQEBDAUAMIGFMQswCQYDVQQGEwJHQjEbMBkGA1UE
# CBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxmb3JkMRowGAYDVQQK
# ExFDT01PRE8gQ0EgTGltaXRlZDErMCkGA1UEAxMiQ09NT0RPIFJTQSBDZXJ0aWZp
# Y2F0aW9uIEF1dGhvcml0eTAeFw0xMDAxMTkwMDAwMDBaFw0zODAxMTgyMzU5NTla
# MIGFMQswCQYDVQQGEwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAw
# DgYDVQQHEwdTYWxmb3JkMRowGAYDVQQKExFDT01PRE8gQ0EgTGltaXRlZDErMCkG
# A1UEAxMiQ09NT0RPIFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBAJHoVJLSClaxrA0k3cXPRGd0mSs3o30j
# cABxvFPfxPoqEo9LfxBWvZ9wcrdhf8lLDxenPeOwBGHu/xGXx/SGPgr6Plz5k+Y0
# etkUa+ecs4Wggnp2r3GQ1+z9DfqcbPrfsIL0FH75vsSmL09/mX+1/GdDcr0MANaJ
# 62ss0+2PmBwUq37l42782KjkkiTaQ2tiuFX96sG8bLaL8w6NmuSbbGmZ+HhIMEXV
# reENPEVg/DKWUSe8Z8PKLrZr6kbHxyCgsR9l3kgIuqROqfKDRjeE6+jMgUhDZ05y
# KptcvUwbKIpcInu0q5jZ7uBRg8MJRk5tPpn6lRfafDNXQTyNUe0LtlyvLGMa31fI
# P7zpXcSbr0WZ4qNaJLS6qVY9z2+q/0lYvvCo//S4rek3+7q49As6+ehDQh6J2ITL
# E/HZu+GJYLiMKFasFB2cCudx688O3T2plqFIvTz3r7UNIkzAEYHsVjv206LiW7ey
# BCJSlYCTaeiOTGXxkQMtcHQC6otnFSlpUgK7199QalVGv6CjKGF/cNDDoqosIapH
# ziicBkV2v4IYJ7TVrrTLUOZr9EyGcTDppt8WhuDY/0Dd+9BCiH+jMzouXB5BEYFj
# zhhxayvspoq3MVw6akfgw3lZ1iAar/JqmKpyvFdK0kuduxD8sExB5e0dPV4onZzM
# v7NR2qdH5YRTAgMBAAGjQjBAMB0GA1UdDgQWBBS7r34CPfqm8TyEjq3uOJjs2TIy
# 1DAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQwF
# AAOCAgEACvHVRoS3rlG7bLJNQRQAk0ycy+XAVM+gJY4C+f2wog31IJg8Ey2sVqKw
# 1n4Rkukuup4umnKxvRlEbGE1opq0FhJpWozh1z6kGugvA/SuYR0QGyqki3rF/gWm
# 4cDWyP6ero8ruj2Z+NhzCVhGbqac9Ncn05XaN4NyHNNz4KJHmQM4XdVJeQApHMfs
# myAcByRpV3iyOfw6hKC1nHyNvy6TYie3OdoXGK69PAlo/4SbPNXWCwPjV54U99Hr
# T8i9hyO3tklDeYVcuuuSC6HG6GioTBaxGpkK6FMskruhCRh1DGWoe8sjtxrCKIXD
# G//QK2LvpHsJkZhnjBQBzWgGamMhdQOAiIpugcaF8qmkLef0pSQQR4PKzfSNeVix
# BpvnGirZnQHXlH3tA0rK8NvoqQE+9VaZyR6OST275Qm54E9Jkj0WgkDMzFnG5jrt
# Ei5pPGyVsf2qHXt/hr4eDjJG+/sTj3V/TItLRmP+ADRAcMHDuaHdpnDiBLNBvOmA
# kepknHrhIgOpnG5vDmVPbIeHXvNuoPl1pZtA6FOyJ51KucB3IY3/h/LevIzvF9+3
# SQvR8m4wCxoOTnbtEfz16Vayfb/HbQqTjKXQwLYdvjpOlKLXbmwLwop8+iDzxOTl
# zQ2oy5GSsXyF7LUUaWYOgufNzsgtplF/IcE1U4UGSl2frbsbX3QwggXgMIIDyKAD
# AgECAhAufIfMDpNKUv6U/Ry3zTSvMA0GCSqGSIb3DQEBDAUAMIGFMQswCQYDVQQG
# EwJHQjEbMBkGA1UECBMSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHEwdTYWxm
# b3JkMRowGAYDVQQKExFDT01PRE8gQ0EgTGltaXRlZDErMCkGA1UEAxMiQ09NT0RP
# IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTAeFw0xMzA1MDkwMDAwMDBaFw0y
# ODA1MDgyMzU5NTlaMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1h
# bmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGjAYBgNVBAoTEUNPTU9ETyBDQSBM
# aW1pdGVkMSMwIQYDVQQDExpDT01PRE8gUlNBIENvZGUgU2lnbmluZyBDQTCCASIw
# DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKaYkGN3kTR/itHd6WcxEevMHv0x
# HbO5Ylc/k7xb458eJDIRJ2u8UZGnz56eJbNfgagYDx0eIDAO+2F7hgmz4/2iaJ0c
# LJ2/cuPkdaDlNSOOyYruGgxkx9hCoXu1UgNLOrCOI0tLY+AilDd71XmQChQYUSzm
# /sES8Bw/YWEKjKLc9sMwqs0oGHVIwXlaCM27jFWM99R2kDozRlBzmFz0hUprD4Dd
# Xta9/akvwCX1+XjXjV8QwkRVPJA8MUbLcK4HqQrjr8EBb5AaI+JfONvGCF1Hs4NB
# 8C4ANxS5Eqp5klLNhw972GIppH4wvRu1jHK0SPLj6CH5XkxieYsCBp9/1QsCAwEA
# AaOCAVEwggFNMB8GA1UdIwQYMBaAFLuvfgI9+qbxPISOre44mOzZMjLUMB0GA1Ud
# DgQWBBQpkWD/ik366/mmarjP+eZLvUnOEjAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0T
# AQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDAzARBgNVHSAECjAIMAYG
# BFUdIAAwTAYDVR0fBEUwQzBBoD+gPYY7aHR0cDovL2NybC5jb21vZG9jYS5jb20v
# Q09NT0RPUlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwcQYIKwYBBQUHAQEE
# ZTBjMDsGCCsGAQUFBzAChi9odHRwOi8vY3J0LmNvbW9kb2NhLmNvbS9DT01PRE9S
# U0FBZGRUcnVzdENBLmNydDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuY29tb2Rv
# Y2EuY29tMA0GCSqGSIb3DQEBDAUAA4ICAQACPwI5w+74yjuJ3gxtTbHxTpJPr8I4
# LATMxWMRqwljr6ui1wI/zG8Zwz3WGgiU/yXYqYinKxAa4JuxByIaURw61OHpCb/m
# JHSvHnsWMW4j71RRLVIC4nUIBUzxt1HhUQDGh/Zs7hBEdldq8d9YayGqSdR8N069
# /7Z1VEAYNldnEc1PAuT+89r8dRfb7Lf3ZQkjSR9DV4PqfiB3YchN8rtlTaj3hUUH
# r3ppJ2WQKUCL33s6UTmMqB9wea1tQiCizwxsA4xMzXMHlOdajjoEuqKhfB/LYzoV
# p9QVG6dSRzKp9L9kR9GqH1NOMjBzwm+3eIKdXP9Gu2siHYgL+BuqNKb8jPXdf2WM
# jDFXMdA27Eehz8uLqO8cGFjFBnfKS5tRr0wISnqP4qNS4o6OzCbkstjlOMKo7caB
# nDVrqVhhSgqXtEtCtlWdvpnncG1Z+G0qDH8ZYF8MmohsMKxSCZAWG/8rndvQIMqJ
# 6ih+Mo4Z33tIMx7XZfiuyfiDFJN2fWTQjs6+NX3/cjFNn569HmwvqI8MBlD7jCez
# dsn05tfDNOKMhyGGYf6/VXThIXcDCmhsu+TJqebPWSXrfOxFDnlmaOgizbjvmIVN
# lhE8CYrQf7woKBP7aspUjZJczcJlmAaezkhb1LU3k0ZBfAfdz/pD77pnYf99SeC7
# MH1cgOPmFjlLpzGCBHswggR3AgEBMIGSMH0xCzAJBgNVBAYTAkdCMRswGQYDVQQI
# ExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGjAYBgNVBAoT
# EUNPTU9ETyBDQSBMaW1pdGVkMSMwIQYDVQQDExpDT01PRE8gUlNBIENvZGUgU2ln
# bmluZyBDQQIRAIDR3v1Nwwc8nJBRgICA3CQwCQYFKw4DAhoFAKB4MBgGCisGAQQB
# gjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHgXo77f
# GHLNy27Jsfza5hn9QugyMA0GCSqGSIb3DQEBAQUABIIBAH4Y3BBgZc1cJ4Og21AV
# grMmQ5vaVM1YPSb7BX4k6ywrP1VC2O8cZMUt6ZIAhBxEkeDrGPJaWf3Hku5h9TcM
# 6C6+TMPqc0xpAS8sJWPDDdkOQHJgRCUGD/dzSSxL9Fvrdo6Rin4M9rQ2YFhx/ar3
# PCEkLQ65OPRsc8iWfc4DmoQrZ5s94/+8dUzYJdtGIvEAExSLZewbU47zg/3DZuB9
# tC2xz/iipQxMYYpFeLLiEVGhMuFXe2kP+dkO8AGSE+tE/96nx+JLXOEVGnjCxID6
# TzMTfl6DNgf5agFji4YlPb9BRICrcU6Xetur2jByGPUCP6XJt72+8it7VgTn+32Y
# a+KhggJDMIICPwYJKoZIhvcNAQkGMYICMDCCAiwCAQEwgakwgZUxCzAJBgNVBAYT
# AlVTMQswCQYDVQQIEwJVVDEXMBUGA1UEBxMOU2FsdCBMYWtlIENpdHkxHjAcBgNV
# BAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEhMB8GA1UECxMYaHR0cDovL3d3dy51
# c2VydHJ1c3QuY29tMR0wGwYDVQQDExRVVE4tVVNFUkZpcnN0LU9iamVjdAIPFojw
# OSVeY45pFDkH5jMLMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0xNzA1MTcwNjA3NTFaMCMGCSqGSIb3DQEJBDEW
# BBRb/t3bgtU+sC8Y34gdlrmIXl8KlTANBgkqhkiG9w0BAQEFAASCAQCBJikE2qYC
# KodyVm1Fvk5iWK/oh3pO3lVZnaQvO1PMyBNsupv8Xa684PkuEr3VGVWOFBiMz/uu
# H5iJpo/emyTj+7oG6ep+cW9qsbqvg0PIbMf4fmbd1XlURLMzSI82smLJab3jFAJO
# SsBCct1scHMzak6Up/8TYhtZKcZh8zcZa3OlQXt+TOsywVQYx9jhCfmuzv5MVdz6
# sD0j1eMzGc/LK1yT/+OSS9PXPcRmpVlFdXl1rlEU054+8z7uNLD0/GHqiREzdK5s
# 8niKX5lLDJDHED4K8w7X8pHN5Vp2kXE7i6r2TrmEtQ5o/9ze6xr1CKCRIV+L3G1m
# UbJ5v7lEZ45Z
# SIG # End signature block
