$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xWebAdministrationHelper.psm1 -Verbose:$false -ErrorAction Stop

function ImportWebAdministrationModule
{
    try
    {
        if(!(Get-Module 'WebAdministration'))
        {
            Write-Verbose 'Importing WebAdministration module'
            $CurrentVerbose = $VerbosePreference
            $VerbosePreference = 'SilentlyContinue'
            $null = Import-Module 'WebAdministration' -ErrorAction Stop
            $VerbosePreference = $CurrentVerbose
            $true
        }
        else
        {
            $true
        }
    }
    catch
    {
        $VerbosePreference = $CurrentVerbose
        Write-Verbose 'Failed importing WebAdministration module'
        $false
    }
}


function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name
	)

    if(ImportWebAdministrationModule)
    {
        $WebAppPool = Get-Item -Path "IIS:\AppPools\$Name" -ErrorAction SilentlyContinue
        if($WebAppPool)
        {
            $IdentityType = $WebAppPool.processModel.identityType
            if($IdentityType -eq "SpecificUser")
            {
                $IdentityUserName = $WebAppPool.processModel.username
            }
            else
            {
                $IdentityUserName = $null
            }
        }
        else
        {
            throw New-TerminatingError -ErrorType AppPoolNotFound -FormatArgs @($Name)
        }
    }
    else
    {
		$IdentityType = $null
		$IdentityUserName = $null
    }

	$returnValue = @{
		Name = $Name
		IdentityType = $IdentityType
		IdentityUserName = $IdentityUserName
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[ValidateSet("LocalSystem","LocalService","NetworkService","SpecificUser","ApplicationPoolIdentity")]
		[System.String]
		$IdentityType = "ApplicationPoolIdentity",

		[System.Management.Automation.PSCredential]
		$IdentityCredential
	)

    if(($IdentityType -eq 'SpecificUser') -and !$PSBoundParameters.ContainsKey('IdentityCredential'))
    {
        throw New-TerminatingError -ErrorType IdentityCredRequired    
    }
    
    if(ImportWebAdministrationModule)
    {
        $WebAppPool = Get-Item -Path "IIS:\AppPools\$Name" -ErrorAction SilentlyContinue
        if($WebAppPool)
        {
            $WebAppPool.processModel.IdentityType = $IdentityType
            $WebAppPool.processModel.userName = $IdentityCredential.UserName
            $WebAppPool.processModel.password = $IdentityCredential.GetNetworkCredential().Password
            $WebAppPool | Set-Item
            Write-Verbose "Recycling application pool $Name"
            $WebAppPool.Recycle()
        }
    }

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[ValidateSet("LocalSystem","LocalService","NetworkService","SpecificUser","ApplicationPoolIdentity")]
		[System.String]
		$IdentityType = "ApplicationPoolIdentity",

		[System.Management.Automation.PSCredential]
		$IdentityCredential
	)

    $WebAppPoolIdentity = Get-TargetResource -Name $Name

    if($WebAppPoolIdentity.IdentityType -eq $IdentityType)
    {
        if($WebAppPoolIdentity.IdentityType -eq "SpecificUser")
        {
            if($WebAppPoolIdentity.IdentityUserName -eq $IdentityCredential.UserName)
            {
                $result = $true
            }
            else
            {
                Write-Verbose "Identity user is $($WebAppPoolIdentity.IdentityUserName) but should be $($IdentityCredential.UserName)."
                $result = $false
            }
        }
        else
        {
            $result = $true
        }
    }
    else
    {
        Write-Verbose "Identity type is $($WebAppPoolIdentity.IdentityType) but should be $IdentityType."
        $result = $false
    }

	$result
}


Export-ModuleMember -Function *-TargetResource