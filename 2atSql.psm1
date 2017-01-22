Set-StrictMode -Version 2.0

Import-Module "$PSScriptRoot\2atGeneral.psm1" -Force -Verbose:$false

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