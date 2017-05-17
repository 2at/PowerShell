Set-StrictMode -Version 2.0

Add-Type -Assembly System.Net.Http
Import-Module "$PSScriptRoot\2atGeneral.psm1" -Force -Verbose:$false

Function HashTableToDictionary {
	Param(
		[Parameter(Mandatory=$true)]
		[HashTable]$HashTable
	)
	
	$Dictionary = New-Object 'System.Collections.Generic.Dictionary[string,string]'
	$HashTable.Keys | %{ $Dictionary.Add($_, $HashTable[$_]) }
	$Dictionary
}

Function Get-WebResponseString {
	Param(
		[Parameter(Mandatory=$true)]
		[PSCustomObject]$WebResponse
	)
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

	$headers = ($WebResponse.ResponseHeaders | %{ "$($_): $($WebResponse.ResponseHeaders[$_])" }) -join [Environment]::NewLine
	
	"HTTP/$($WebResponse.ProtocolVersion) $([int]$WebResponse.HTTPStatus) $($WebResponse.HTTPStatusDescription)
$headers

$($WebResponse.ResponseBody)"
}

Function Get-WebResponse {
	Param(
		[Parameter(Mandatory=$true)]
		[ValidateScript({(New-Object System.Uri $_)})]
		[string]$Url,

		[System.Net.CookieContainer]$CookieContainer,
		
		[string]$Method = 'GET',
		
		[object]$FormData,
		
		[System.Net.WebProxy]$Proxy,
		
		[System.Net.ICredentials]$Credentials,
		
		[string]$UserAgent
	)
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	if ($FormData -And -Not ($FormData -is [HashTable] -or $FormData -is [System.Collections.Generic.Dictionary[string,string]])) { throw 'FormData must be either a HashTable or a Dictionary[string,string]' }

	$o = [ordered]@{
		DateTime=Get-Date
		Url=$Url
		Method=$Method
		FormData=$null
		WebRequestStatus=[System.Net.WebExceptionStatus]::Success
		WebRequestStatusDescription=$null
		ProtocolVersion=$null
		HTTPStatus=$null
		HTTPStatusDescription=$null
		ResponseHeaders=$null
		ResponseBody=$null
	}
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

	$req = [System.Net.WebRequest]::Create($Url)
	$req.AllowAutoRedirect = $false
	$req.UserAgent = $UserAgent
	$req.CookieContainer = $CookieContainer
	$req.Method = $Method
	$req.Proxy = $Proxy
	$req.Credentials = $Credentials
	
	$c = $null
	if ($FormData) {
		if ($FormData -is [HashTable]) { $FormData = HashTableToDictionary $FormData }
		
		$o.FormData=$FormData
		$c = New-Object System.Net.Http.FormUrlEncodedContent $FormData
		$req.ContentType = $c.Headers.ContentType.MediaType
	}
	
	$reader = $null
	$resp = $null
	try {
		$o.TotalTime = Measure-Command {
			$o.TimeToFirstByte = Measure-Command {
				try {
					if ($c) {
						Wait-Job $c.CopyToAsync($req.GetRequestStream())
					}
					$resp = $req.GetResponse()
				} catch [System.Net.WebException] {
					$e = $_.Exception
					
					Write-Warning "$Method $Url : $($e.Status) - $($e.Message)"

					$resp = $e.Response
					$o.WebRequestStatus = $e.Status
					$o.WebRequestStatusDescription = $e.Message
				}
			}
			if ($resp) {
				$reader = New-Object System.IO.StreamReader $resp.GetResponseStream(), ([System.Text.Encoding]::GetEncoding($resp.CharacterSet))
				$o.ResponseBody = $reader.ReadToEnd()
			}
		}

		if ($resp) {
			$o.ProtocolVersion = $resp.ProtocolVersion
			$o.ResponseHeaders = $resp.Headers
			$o.HTTPStatus = $resp.StatusCode
			$o.HTTPStatusDescription = $resp.StatusDescription
		}

		[PSCustomObject]$o
	} finally {
		if ($reader) { $reader.Dispose() }
		if ($resp) { $resp.Dispose() }
	}
}

Export-ModuleMember -Function Get-*
Export-ModuleMember -Function Set-*