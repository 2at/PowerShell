﻿Set-StrictMode -Version 2.0

Function Import-WebModule {
	Param(
		[Parameter(Mandatory=$true)]
		$Uri
	)

	$tempfile = "$Env:TEMP\$(([Uri]$Uri).AbsolutePath.Replace('/','_'))"

	try {
		$h = if (Test-Path $tempfile) { @{ 'If-Modified-Since'=(Get-Item $tempfile).LastWriteTimeUtc.ToString([CultureInfo]::InvariantCulture) } }
		Invoke-WebRequest -Uri $Uri -OutFile $tempfile -Headers $h
		Add-Content $tempfile -Stream Zone.Identifier [ZoneTransfer]`r`nZoneId=3
		Import-Module $tempfile -Force -Verbose:$false
	} catch [System.Net.WebException] {
        if (!$h) { throw }
		
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotModified) {
            Write-Verbose "WebModule $Uri was not modified on server, using valid cache"
		} else { Write-Warning "WebModule $Uri could not be downloaded, using last downloaded file $($h.'If-Modified-Since')" }
        
        Import-Module $tempfile -Verbose:$false
	}
}

Import-WebModule http://ps.2at.nl/2017/04/2atGeneral.psm1

function execSql {
    [CmdletBinding()]
    param (
        [string]
        $ConnectionString,
        
        [Parameter(ValueFromPipeline)]
        [System.Data.SqlClient.SqlConnection]
        $SqlConnection,
        
        [Parameter(Position=0)]
        [ValidateNotNullorEmpty()]
        [string]
        $CommandText,
        
        [bool]
        $CommandIsQuery,
        
        [Parameter(Position=1)]
        [hashtable]
        $Parameters=@{},

        [scriptblock]
        $Script,

		[int]
		$Timeout
    )

    Write-Verbose "Executing SQL: $CommandText"

    if ($SqlConnection -and ![string]::IsNullOrEmpty($ConnectionString)) { Write-Warning "Both SqlConnection and ConnectionString set. Using SqlConnection and ignoring ConnectionString value." }

    if (!$SqlConnection)
    {
        if ([string]::IsNullOrEmpty($ConnectionString)) { throw "Either supply a SqlConnection object or a ConnectionString" }

        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $disposeConnection = $true
    }

    $SqlCmd = $SqlConnection.CreateCommand()
    $SqlCmd.CommandText = $CommandText
    if ($Timeout -ne -1) { $SqlCmd.CommandTimeout = $Timeout }
    if (!$CommandIsQuery) { $SqlCmd.CommandType = [System.Data.CommandType]'StoredProcedure' }

    foreach($p in $parameters.Keys)
    {
        if ($parameters[$p] -ne $null) { $v = $Parameters[$p] } else { $v = [DBNull]::Value } 
        Write-Verbose "  $p = $v"

        [void]$SqlCmd.Parameters.AddWithValue("@$p",$v)
    }

    if ($SqlConnection.State -eq [System.Data.ConnectionState]::Closed) { $SqlConnection.Open() }

    $script.Invoke($SqlCmd)

    $SqlCmd.Dispose()
    if ($disposeConnection) { $SqlConnection.Dispose() }
}

function Get-SqlData {
    [CmdletBinding()]
    param (
        [string]
        $ConnectionString,
        
        [Parameter(ValueFromPipeline)]
        [System.Data.SqlClient.SqlConnection]
        $SqlConnection,
        
        [Parameter(Position=0)]
        [ValidateNotNullorEmpty()]
        [string]
        $CommandText,
        
        [switch]
        $CommandIsQuery,
        
        [Parameter(Position=1)]
        [hashtable]
        $Parameters=@{},

		[int]
		$Timeout=-1
    )
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    execSql -ConnectionString $ConnectionString -SqlConnection $SqlConnection -CommandText $CommandText -CommandIsQuery $CommandIsQuery -Timeout $Timeout -Parameters $Parameters -Script {
        param ( [System.Data.SqlClient.SqlCommand]$SqlCmd )
        $dt=New-Object system.Data.DataTable
        [void](New-Object system.Data.SqlClient.SqlDataAdapter($SqlCmd)).fill($dt)
        $dt
    }
}

function Set-SqlData {
    [CmdletBinding()]
    param (
        [string]
        $ConnectionString,
        
        [Parameter(ValueFromPipeline)]
        [System.Data.SqlClient.SqlConnection]
        $SqlConnection,
        
        [Parameter(Position=0)]
        [ValidateNotNullorEmpty()]
        [string]
        $CommandText,
        
        [switch]
        $CommandIsQuery,

        [Parameter(Position=1)]        
        [hashtable]
        $Parameters=@{},

		[int]
		$Timeout=-1
    )
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    execSql -ConnectionString $ConnectionString -SqlConnection $SqlConnection -CommandText $CommandText -CommandIsQuery $CommandIsQuery -Timeout $Timeout -Parameters $Parameters -Script {
        param ( [System.Data.SqlClient.SqlCommand]$SqlCmd )
        [void]$SqlCmd.ExecuteNonQuery()
    }
}

Export-ModuleMember -Function Get-*
Export-ModuleMember -Function Set-*



# SIG # Begin signature block
# MIIapQYJKoZIhvcNAQcCoIIaljCCGpICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQ3xJx6CHeNHYPMV+5BTjepD6
# Xt2gghWUMIIEmTCCA4GgAwIBAgIPFojwOSVeY45pFDkH5jMLMA0GCSqGSIb3DQEB
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
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFJanCHCn
# OtpQA/3HDcy5HwphaLuEMA0GCSqGSIb3DQEBAQUABIIBACnb1Pih+H+nS/WoQSK8
# jYx77PLAzTNHM82ooTVhM9hcqATZMfzwOWNZFwECfdUn865WbWXcbldBjkEipDeW
# SRqMLbeYC62C1ItzU/b5sPKehFx4zqiMGcvJDmBaotPb5UoeNYpOzlZMYM2WVHHA
# CeVlJtFp+SpqNYewVdh0Lv1G7oTJkpdavC2okHzc7de/XEG4lrJuG5537jgzW2Uy
# 5A19/ttqKuXGqIBR9ONeWuH7khQXwTMvcO+r+b8qLxmFXVPClctZTFWcku6gZk1D
# laM7rynAHTLXPoGgTK+rSmwiXQA6letgVxtyj3/ob8DT4mZ5yPPWRqv4FN47BFAP
# 9RuhggJDMIICPwYJKoZIhvcNAQkGMYICMDCCAiwCAQEwgakwgZUxCzAJBgNVBAYT
# AlVTMQswCQYDVQQIEwJVVDEXMBUGA1UEBxMOU2FsdCBMYWtlIENpdHkxHjAcBgNV
# BAoTFVRoZSBVU0VSVFJVU1QgTmV0d29yazEhMB8GA1UECxMYaHR0cDovL3d3dy51
# c2VydHJ1c3QuY29tMR0wGwYDVQQDExRVVE4tVVNFUkZpcnN0LU9iamVjdAIPFojw
# OSVeY45pFDkH5jMLMAkGBSsOAwIaBQCgXTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0xNzEyMDQxMTIxMjRaMCMGCSqGSIb3DQEJBDEW
# BBSl7fr1Wh4UVsF6BeseZ9b+P2ytcjANBgkqhkiG9w0BAQEFAASCAQAmgFKIZCzz
# p6EFNOPm7X/x8A5iT1CZNhE8AFmeK5YftemSYy46BvQBwz+W5I7sC/W42/kzaJTb
# gdQlk7FrbO7XGG08W5pfdoIk4KC5b1pXB6AV6uFM+IJVY6zmONqP8KrRcMc+dWBD
# GjrGhZmtXgEHgycf9kXAKHC1IxhHgAB0W6RXdcjNNMTUYK0T/xvbiX00EFodov4q
# KjEIm7MapnoxD21s6fcf8KFztOHmV6gm0AIWeuauvSznWbgfNMP/uWosOAagUFRq
# V+pY8eD41aR6CNe5gxfFlpPUSwkPPzw6lrd9Qn6NXNLCDYZ2W8hEjlYCIBZ1+0tw
# anCTflcOFOH+
# SIG # End signature block
