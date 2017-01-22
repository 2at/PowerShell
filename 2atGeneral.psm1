#requires -Version 2.0

Set-StrictMode -Version 2.0

Function Get-CallerPreference
{
	<#
	.SYNOPSIS
		Fetches "Preference" variable values from the caller's scope.
	.DESCRIPTION
		Script module functions do not automatically inherit their caller's variables, but they can be obtained through the $PSCmdlet variable in Advanced Functions.  This function is a helper function for any script module Advanced Function; by passing in the values of $ExecutionContext.SessionState and $PSCmdlet, Get-CallerPreference will set the caller's preference variables locally.
	.PARAMETER Cmdlet
		The $PSCmdlet object from a script module Advanced Function.
	.PARAMETER SessionState
		The $ExecutionContext.SessionState object from a script module Advanced Function.  This is how the Get-CallerPreference function sets variables in its callers' scope, even if that caller is in a different script module.
	.EXAMPLE
		Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

		Imports the default PowerShell preference variables from the caller into the local scope.
	.LINK
		about_Preference_Variables
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
        [ValidateScript({ $_.GetType().FullName -eq 'System.Management.Automation.PSScriptCmdlet' })]
		$Cmdlet,

		[Parameter(Mandatory = $true)]
		[System.Management.Automation.SessionState]
		$SessionState
	)

	@('ErrorActionPreference', 'DebugPreference', 'ConfirmPreference', 'WhatIfPreference', 'VerbosePreference', 'WarningPreference') | %{
		$SessionState.PSVariable.Set($_, $Cmdlet.SessionState.PSVariable.Get($_).Value)
	}
}

Function Get-StoredCredential{
	<#
	.SYNOPSIS
		TODO
	.OUTPUTS
		System.Management.Automation.PSCredential
	#>
	[CmdletBinding()]
	Param(
		[string]
		#Specifies what username to look for in the stored credentials. If ommitted the first credentials found in the file will be returned.
		$UserName,
		
		[string]
		[ValidateScript({Test-Path $_ -IsValid -PathType Leaf})]
		#Specifies in what file to store the credentials. If ommitted the credentials will be stored in a file with the same name as the calling script with .cred added 
		$FilePath = "$($MyInvocation.PSCommandPath).cred",
		
		[switch]
		#Indicates that if a valid credential can not be found the user will not be prompted to enter credentials.
		$DoNotPromptUser,
		
		[switch]
		#Indicates that an existing file may be overwritten if a parse error occurs.
		$OverwriteFileOnError
	)
	Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
	
	$fileError = $false
	$creds = $null
	$credStore = @{}
	$fileExists = Test-Path $FilePath -PathType Leaf
	
	if ($fileExists) {
		try {
			$credStore = [HashTable](Import-CliXml $FilePath)
			if ($UserName) {
				if ($credStore[$UserName]) { return New-Object PSCredential $UserName, ($credStore[$UserName] | ConvertTo-SecureString) }
			} else {
				$credStore.Keys | Select -First 1 | %{ return New-Object PSCredential $_, ($credStore[$_] | ConvertTo-SecureString) }
			}
		} catch {
			Write-Warning "Error retrieving credentials from existing file. $($_.Exception.Message)"
			$fileError=$true
		}
	}

	if ($DoNotPromptUser) {
		throw 'No valid credential was found and -DoNotPromptUser was specified'
	}
	
	$cred = Get-Credential $UserName

	$credStore[$cred.UserName] = ($cred.Password | ConvertFrom-SecureString)

	if ($OverwriteFileOnError -or -not $fileError) {
		try {
			$credStore | Export-CliXml $FilePath -NoClobber:$OverwriteFileOnError
		} catch {
			Write-Warning "Error writing credentials to file '$FilePath'. $($_.Exception.Message)"
		}
	}
	
	return $cred
}