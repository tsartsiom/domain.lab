$script:ModuleRoot = $PSScriptRoot
$script:ModuleVersion = (Import-PowerShellDataFile -Path "$($script:ModuleRoot)\GPWmiFilter.psd1").ModuleVersion

# Detect whether at some level dotsourcing was enforced
$script:doDotSource = Get-PSFConfigValue -FullName GPWmiFilter.Import.DoDotSource -Fallback $false
if ($GPWmiFilter_dotsourcemodule) { $script:doDotSource = $true }

<#
Note on Resolve-Path:
All paths are sent through Resolve-Path/Resolve-PSFPath in order to convert them to the correct path separator.
This allows ignoring path separators throughout the import sequence, which could otherwise cause trouble depending on OS.
Resolve-Path can only be used for paths that already exist, Resolve-PSFPath can accept that the last leaf my not exist.
This is important when testing for paths.
#>

# Detect whether at some level loading individual module files, rather than the compiled module was enforced
$importIndividualFiles = Get-PSFConfigValue -FullName GPWmiFilter.Import.IndividualFiles -Fallback $false
if ($GPWmiFilter_importIndividualFiles) { $importIndividualFiles = $true }
if (Test-Path (Resolve-PSFPath -Path "$($script:ModuleRoot)\..\.git" -SingleItem -NewChild)) { $importIndividualFiles = $true }
if ("<was compiled>" -eq '<was not compiled>') { $importIndividualFiles = $true }
	
function Import-ModuleFile
{
	<#
		.SYNOPSIS
			Loads files into the module on module import.
		
		.DESCRIPTION
			This helper function is used during module initialization.
			It should always be dotsourced itself, in order to proper function.
			
			This provides a central location to react to files being imported, if later desired
		
		.PARAMETER Path
			The path to the file to load
		
		.EXAMPLE
			PS C:\> . Import-ModuleFile -File $function.FullName
	
			Imports the file stored in $function according to import policy
	#>
	[CmdletBinding()]
	Param (
		[string]
		$Path
	)
	
	if ($doDotSource) { . (Resolve-Path $Path).ProviderPath }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText((Resolve-Path $Path).ProviderPath))), $null, $null) }
}

#region Load individual files
if ($importIndividualFiles)
{
	# Execute Preimport actions
	. Import-ModuleFile -Path "$ModuleRoot\internal\scripts\preimport.ps1"
	
	# Import all internal functions
	foreach ($function in (Get-ChildItem "$ModuleRoot\internal\functions" -Filter "*.ps1" -Recurse -ErrorAction Ignore))
	{
		. Import-ModuleFile -Path $function.FullName
	}
	
	# Import all public functions
	foreach ($function in (Get-ChildItem "$ModuleRoot\functions" -Filter "*.ps1" -Recurse -ErrorAction Ignore))
	{
		. Import-ModuleFile -Path $function.FullName
	}
	
	# Execute Postimport actions
	. Import-ModuleFile -Path "$ModuleRoot\internal\scripts\postimport.ps1"
	
	# End it here, do not load compiled code below
	return
}
#endregion Load individual files

#region Load compiled code
function Get-DomainController
{
<#
	.SYNOPSIS
		Returns a specific domain controller.
	
	.DESCRIPTION
		Helper function that resolves the server parameter into a specific domain controller to operate against.
		If the server parameter is given an actual domain controller, it will try to contact it and return its name.
		If given a domain name, it will contact an arbitrary domain controller and return its name.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller or domain.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.EXAMPLE
		PS C:\> Get-DomainController -Server 'contoso.com'
	
		Returns a domain controller of the domain 'contoso.com'
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]
		$Server,
		
		[AllowNull()]
		[System.Management.Automation.PSCredential]
		$Credential
	)
	
	$adParameters = @{
		Server	    = $Server
		ErrorAction = 'Stop'
	}
	if ($Credential -and ($Credential -ne [System.Management.Automation.PSCredential]::Empty))
	{
		$adParameters['Credential'] = $Credential
	}
	
	try { $controller = (Get-ADDomainController @adParameters).HostName }
	catch { throw }
	Write-PSFMessage -Level Debug -String 'Get-DomainController.DCFound' -StringValues $Server, $controller
	$controller
}

function Resolve-PolicyName
{
<#
	.SYNOPSIS
		Simple helper tool for parsing GPO object/name input.
	
	.DESCRIPTION
		Simple helper tool for parsing GPO object/name input.
		Returns name or id.
		ONLY use in pipeline.
	
	.PARAMETER InputObject
		The object to parse.
	
	.EXAMPLE
		PS C:\> $Policy | Resolve-PolicyName
	
		Returns IDs or Names of all policy items in $Policy
#>
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		$InputObject
	)
	
	process
	{
		if ($null -eq $InputObject) { return }
		if ($InputObject.GetType().FullName -eq 'Microsoft.GroupPolicy.Gpo') { return $InputObject.Id -as [string] }
		if ($InputObject.Id) { return $InputObject.Id -as [string] }
		if ($InputObject.DisplayName) { return $InputObject.DisplayName -as [string] }
		$InputObject -as [string]
	}
}

function Clear-GPWmiFilterAssignment
{
<#
	.SYNOPSIS
		Clears a GPO of its assigned WMI Filter.
	
	.DESCRIPTION
		Clears a GPO of its assigned WMI Filter.
	
	.PARAMETER Policy
		The name of the GPO to clear of its assigned WMI Filter.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		PS C:\> Get-GPO -All | Clear-GPWmiFilterAssignment
	
		Clear all WMI Filters from all GPOs.
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param (
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ValueFromPipeline = $true)]
		[Alias('Id', 'DisplayName')]
		$Policy,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Clear-GPWmiFilterAssignment.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
		
		$adParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Server, Credential
	}
	process
	{
		foreach ($policyItem in ($Policy | Resolve-PolicyName))
		{
			$gpoObject = Get-ADObject @adParameters -LDAPFilter "(&(objectClass=groupPolicyContainer)(|(cn=$($policyItem))(cn={$($policyItem)})(displayName=$($policyItem))))"
			
			if (-not $gpoObject)
			{
				Write-PSFMessage -Level Warning -String 'Clear-GPWmiFilterAssignment.GPONotFound' -StringValues $policyItem
				continue
			}
			
			Invoke-PSFProtectedCommand -ActionString 'Clear-GPWmiFilterAssignment.UpdatingGPO' -ActionStringValues $policyItem, $gpoObject -Target $policyItem -ScriptBlock {
				$gpoObject | Set-ADObject @adParameters -Clear 'gPCWQLFilter'
			} -Continue -PSCmdlet $PSCmdlet -EnableException $EnableException.ToBool()
		}
	}
}

function Get-GPWmiFilter
{
<#
	.SYNOPSIS
		Get a WMI filter in current domain
	
	.DESCRIPTION
		The Get-GPWmiFilter function query WMI filter(s) in current domain with specific name or GUID.
	
	.PARAMETER Name
		The name of WMI filter you want to query out.
		Default Value: '*'
	
	.PARAMETER Guid
		The guid of WMI filter you want to query out.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.EXAMPLE
		PS C:\> Get-GPWmiFilter -Name 'Virtual Machines'
		
		Get WMI filter(s) with the name 'Virtual Machines'
	
	.EXAMPLE
		PS C:\> Get-GPWmiFilter
		
		Get all WMI filters in current domain
#>
	[CmdletBinding(DefaultParameterSetName = 'ByName')]
	param
	(
		[Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = "ByName")]
		[ValidateNotNull()]
		[string[]]
		$Name = "*",
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByGUID")]
		[ValidateNotNull()]
		[Guid[]]
		$Guid,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Get-GPWmiFilter.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
		
		$parameters = @{
			Properties = "msWMI-Name", "msWMI-Parm1", "msWMI-Parm2", "msWMI-Author", "msWMI-ID", "Modified", 'nTSecurityDescriptor'
			Server = $PSBoundParameters.Server
		}
		if (Test-PSFParameterBinding -ParameterName Credential) { $parameters['Credential'] = $Credential }
		
		$selectProperties = @(
			'"msWMI-Name" as Name'
			'"msWMI-Author" as Author'
			'"msWMI-Parm1" as Description'
			'"msWMI-ID".Trim("{}") to GUID as ID'
			'Modified'
			'"msWMI-Parm2" as Filter'
			'DistinguishedName'
			'nTSecurityDescriptor.Owner as SecOwner'
			'nTSecurityDescriptor.Access as SecAccess'
			'nTSecurityDescriptor as SecACL'
		)
		[System.Collections.ArrayList]$foundPolicies = @()
	}
	process
	{
		if (Test-PSFFunctionInterrupt) { return }
		
		if ($Guid)
		{
			foreach ($guidItem in $Guid)
			{
				Write-PSFMessage -String 'Get-GPWmiFilter.SearchGuid' -StringValues $guidItem -Level Debug
				$ldapFilter = "(&(objectClass=msWMI-Som)(Name={$guidItem}))"
				Get-ADObject @parameters -LDAPFilter $ldapFilter | Select-PSFObject -Property $selectProperties -TypeName 'GroupPolicy.WMIFilter' | Where-Object {
					if ($foundPolicies -notcontains $_.ID)
					{
						$null = $foundPolicies.Add($_.ID)
						return $true
					}
				}
			}
		}
		elseif ($Name)
		{
			foreach ($nameItem in $Name)
			{
				Write-PSFMessage -String 'Get-GPWmiFilter.SearchName' -StringValues $nameItem -Level Debug
				$ldapFilter = "(&(objectClass=msWMI-Som)(msWMI-Name=$nameItem))"
				Get-ADObject @parameters -LDAPFilter $ldapFilter | Select-PSFObject -Property $selectProperties -TypeName 'GroupPolicy.WMIFilter' | Where-Object {
					if ($foundPolicies -notcontains $_.ID)
					{
						$null = $foundPolicies.Add($_.ID)
						return $true
					}
				}
			}
		}
	}
}


function New-GPWmiFilter
{
<#
	.SYNOPSIS
		Create a new WMI filter for Group Policy with given name, WQL query and description.
	
	.DESCRIPTION
		The New-GPWmiFilter function create an AD object for WMI filter with specific name, WQL query expressions and description.
		With -PassThru switch, it output the WMIFilter instance which can be assigned to GPO.WMIFilter property.
	
	.PARAMETER Name
		The name of new WMI filter.
	
	.PARAMETER Filter
		The wmi filter query to use as condition for the filter.

	.PARAMETER Namespace
		The namespace of the wmi filter query.
		Defaults to: 'root\CIMv2'
		Note: This parameter is ignored for individual filter conditions that include their own namespace (<namespace>;<filter>).
	
	.PARAMETER Expression
		The expression(s) of WQL query in new WMI filter. Pass an array to this parameter if multiple WQL queries applied.
	
	.PARAMETER Description
		The description text of the WMI filter (optional).
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		New-GPWmiFilter -Name 'Virtual Machines' -Filter 'SELECT * FROM Win32_ComputerSystem WHERE Model = "Virtual Machine"' -Description 'Only apply on virtual machines'
		
		Create a WMI filter to apply GPO only on virtual machines
	
	.EXAMPLE
		Get-GPWmiFilter -Server contoso.com | New-GPWmiFilter -Server fabrikam.com
	
		Copies all WMI Filters from the domain contoso.com to the domain fabrikam.com
	
	.EXAMPLE
		$filter = New-GPWmiFilter -Name 'Workstation 32-bit' -Expression 'SELECT * FROM WIN32_OperatingSystem WHERE ProductType=1', 'SELECT * FROM Win32_Processor WHERE AddressWidth = "32"' -PassThru
		$gpo = New-GPO -Name "Test GPO"
		$gpo.WmiFilter = $filter
		
		Create a WMI filter for 32-bit work station and link it to a new GPO named "Test GPO".
#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
		[ValidateNotNull()]
		[string]
		$Name,
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 1)]
		[ValidateNotNull()]
		[Alias('Expression')]
		[string[]]
		$Filter,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[string]
		$Namespace = 'root\CIMv2',
		
		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[string]
		$Description,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		$adParameters = @{
			Server	    = $Server
			ErrorAction = 'Stop'
		}
		if (Test-PSFParameterBinding -ParameterName Credential) { $adParameters['Credential'] = $Credential }
		
		try
		{
			$namingContext = (Get-ADRootDSE @adParameters).DefaultNamingContext
			# Resolve to dedicated server to ensure repeated calls are executed against same machine
			$adParameters.Server = (Get-ADDomainController @adParameters).HostName
		}
		catch
		{
			Stop-PSFFunction -String 'New-GPWmiFilter.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
	}
	process
	{
		if (Test-PSFFunctionInterrupt) { return }
		if ($Filter.Count -lt 1)
		{
			Stop-PSFFunction -String 'New-GPWmiFilter.NoFilter' -EnableException $EnableException
			return
		}
		
		$wmiGuid = "{$([System.Guid]::NewGuid())}"
		$creationDate = (Get-Date).ToUniversalTime().ToString("yyyyMMddhhmmss.ffffff-000")
		$filterString = "{0};" -f $Filter.Count.ToString()
		$Filter | ForEach-Object {
			if ($_ -match '^root\\.+?;|^root;') { $filterString += "3;{0};{1};WQL;{2};" -f ($_ -split ";",2)[0].Length, ($_ -split ";",2)[1].Length, $_ }
			else { $filterString += "3;$($Namespace.Length);{0};WQL;$Namespace;{1};" -f $_.Length, $_ }
		}
		$attributes = @{
			"showInAdvancedViewOnly" = "TRUE"
			"msWMI-Name"			 = $Name
			"msWMI-Parm2"		     = $filterString
			"msWMI-Author"		     = (Get-PSFConfigValue -FullName 'GPWmiFilter.Author' -Fallback "$($env:USERNAME)@$($env:USERDNSDOMAIN)")
			"msWMI-ID"			     = $wmiGuid
			"instanceType"		     = 4
			"distinguishedname"	     = "CN=$wmiGuid,CN=SOM,CN=WMIPolicy,CN=System,$namingContext"
			"msWMI-ChangeDate"	     = $creationDate
			"msWMI-CreationDate"	 = $creationDate
		}
		if ($Description) {
			 $attributes."msWMI-Parm1" = $Description
		}
		
		$paramNewADObject = @{
			OtherAttributes = $attributes
			Name		    = $wmiGuid
			Type		    = "msWMI-Som"
			Path		    = "CN=SOM,CN=WMIPolicy,CN=System,$namingContext"
		}
		$paramNewADObject += $adParameters
		Invoke-PSFProtectedCommand -ActionString 'New-GPWmiFilter.CreatingFilter' -ActionStringValues $Name -ScriptBlock {
			New-ADObject @paramNewADObject
			Get-GPWmiFilter -Guid $wmiGuid @adParameters
		} -Target $Name -EnableException $EnableException.ToBool() -PSCmdlet $PSCmdlet
	}
}

function Remove-GPWmiFilter
{
<#
	.SYNOPSIS
		Remove a WMI filter from current domain
	
	.DESCRIPTION
		The Remove-GPWmiFilter function remove WMI filter(s) in current domain with specific name or GUID.
	
	.PARAMETER Guid
		The guid of WMI filter you want to remove.
	
	.PARAMETER Name
		The name of WMI filter you want to remove.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		Remove-GPWmiFilter -Name 'Virtual Machines'
		
		Remove the WMI filter with name 'Virtual Machines'
#>
	[CmdletBinding(DefaultParametersetName = "ByName", SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = "ByGUID")]
		[ValidateNotNull()]
		[Guid[]]
		$Guid,
		
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = "ByName")]
		[ValidateNotNull()]
		[string[]]
		$Name,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Remove-GPWmiFilter.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
		
		$adParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Server, Credential
	}
	process
	{
		if (Test-PSFFunctionInterrupt) { return }
		$getParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Guid, Name, Server, Credential
		foreach ($wmiFilter in (Get-GPWmiFilter @getParameters))
		{
			Invoke-PSFProtectedCommand -ActionString Remove-GPWmiFilter.Delete -ActionStringValues $wmiFilter.Name -Target $wmiFilter.ID -ScriptBlock {
				Remove-ADObject -Identity $wmiFilter.DistinguishedName @adParameters -Confirm:$false -ErrorAction Stop
			} -EnableException $EnableException.ToBool() -Continue -PSCmdlet $PSCmdlet
		}
	}
}


function Rename-GPWmiFilter
{
<#
	.SYNOPSIS
		Get a WMI filter in current domain and rename it
	
	.DESCRIPTION
		The Rename-GPWmiFilter function query WMI filter in current domain with specific name or GUID and then change it to a new name.
	
	.PARAMETER Name
		The name of WMI filter you want to query out.
	
	.PARAMETER Guid
		The guid of WMI filter you want to query out.
	
	.PARAMETER NewName
		The new name of WMI filter.
	
	.PARAMETER PassThru
		Output the renamed WMI filter instance with this switch.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		Rename-GPWmiFilter -Name 'Workstations' -NewName 'Client Machines'
		
		Rename WMI filter "Workstations" to "Client Machines"
#>
	[CmdletBinding(DefaultParameterSetName = 'ByName', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = "ByName")]
		[ValidateNotNull()]
		[string[]]
		$Name,
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByGUID")]
		[ValidateNotNull()]
		[Guid[]]
		$Guid,
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 1)]
		[ValidateNotNull()]
		[string]
		$NewName,
		
		[switch]
		$PassThru,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Rename-GPWmiFilter.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
	}
	process
	{
		#region Validation and Prepare
		if (Test-PSFFunctionInterrupt) { return }
		
		$parameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Name, Guid, Credential, Server
		#endregion Validation and Prepare
		
		foreach ($wmiFilter in (Get-GPWmiFilter @parameters))
		{
			Write-PSFMessage -String 'Rename-GPWmiFilter.RenamingFilter' -StringValues $wmiFilter.Name, $NewName, $wmiFilter.DistinguishedName -Target $wmiFilter.ID
			
			#region Validate Necessity
			if ($wmiFilter.Name -eq $NewName)
			{
				Write-PSFMessage -String 'Rename-GPWmiFilter.NoChangeNeeded' -StringValues $wmiFilter.Name, $NewName, $wmiFilter.DistinguishedName
				if ($PassThru) { $wmiFilter }
				continue
			}
			#endregion Validate Necessity
			
			#region Calculate AD Attribute Updates
			$adAttributes = @{
				"msWMI-Author" = (Get-PSFConfigValue -FullName 'GPWmiFilter.Author' -Fallback "$($env:USERNAME)@$($env:USERDNSDOMAIN)")
				"msWMI-ChangeDate" = (Get-Date).ToUniversalTime().ToString("yyyyMMddhhmmss.ffffff-000")
				"msWMI-Name"   = $NewName
			}
			#endregion Calculate AD Attribute Updates
			
			#region Perform Change
			$adParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Server, Credential
			Invoke-PSFProtectedCommand -ActionString 'Rename-GPWmiFilter.PerformingRename' -ActionStringValues $wmiFilter.Name, $NewName, $wmiFilter.DistinguishedName -ScriptBlock {
				Set-ADObject @adParameters -Identity $wmiFilter.DistinguishedName -Replace $adAttributes -ErrorAction Stop
			} -Target $wmiFilter.ID -EnableException $EnableException.ToBool() -PSCmdlet $PSCmdlet -Continue
			
			if ($PassThru)
			{
				$getParameters = $adParameters.Clone()
				$getParameters['Guid'] = $wmiFilter.ID
				Get-GPWmiFilter @getParameters
			}
			#endregion Perform Change
		}
	}
}


function Set-GPWmiFilter
{
<#
	.SYNOPSIS
		Update the settings of a WMI filter.
	
	.DESCRIPTION
		Update the settings of a WMI filter.
	
	.PARAMETER Name
		The name of WMI filter you want to query out.
	
	.PARAMETER Guid
		The guid of WMI filter you want to query out.
	
	.PARAMETER Filter
		The expression(s) of WQL query in new WMI filter. Pass an array to this parameter if multiple WQL queries applied.

	.PARAMETER Namespace
		The namespace of the wmi filter query.
		Defaults to: 'root\CIMv2'
		Note: This parameter is ignored for individual filter conditions that include their own namespace (<namespace>;<filter>).
	
	.PARAMETER Description
		The description text of the WMI filter.
	
	.PARAMETER PassThru
		Output the updated WMI filter instance with this switch.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.PARAMETER Confirm
		If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
	
	.PARAMETER WhatIf
		If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
	
	.EXAMPLE
		Set-GPWmiFilter -Name 'Workstations' -Filter 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = "1"'
		
		Set WMI filter named with "Workstations" to specific WQL query
	
	.EXAMPLE
		Get-GPWmiFilter -Server contoso.com | Set-GPWmiFilter -Server fabrikam.com
	
		Updates changes made to the wmi filters in the domain contoso.com to the wmi filters in the domain fabrikam.com.
#>
	[CmdletBinding(DefaultParameterSetName = 'ByName', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
	param
	(
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0, ParameterSetName = "ByName")]
		[string[]]
		$Name,
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = "ByGUID")]
		[Guid[]]
		$Guid,
		
		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[Alias('Expression')]
		[string[]]
		$Filter,

		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[string]
		$Namespace = 'root\CIMv2',
		
		[Parameter(ValueFromPipelineByPropertyName = $true)]
		[string]
		$Description,
		
		[switch]
		$PassThru,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Set-GPWmiFilter.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
	}
	process
	{
		#region Validation and Prepare
		if (Test-PSFFunctionInterrupt) { return }
		
		if (Test-PSFParameterBinding -ParameterName Filter, Description -Not)
		{
			Stop-PSFFunction -String 'Set-GPWmiFilter.NoChangeParameters' -StringValues 'Filter', 'Description' -EnableException $EnableException -Cmdlet $PSCmdlet -Category InvalidArgument
			return
		}
		
		$parameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Name, Guid, Credential, Server
		#endregion Validation and Prepare
		
		foreach ($wmiFilter in (Get-GPWmiFilter @parameters))
		{
			Write-PSFMessage -String 'Set-GPWmiFilter.UpdatingFilter' -StringValues $wmiFilter.Name, $wmiFilter.DistinguishedName -Target $wmiFilter.ID
			#region Calculate AD Attribute Updates
			$adAttributes = @{
				"msWMI-Author"	   = (Get-PSFConfigValue -FullName 'GPWmiFilter.Author' -Fallback "$($env:USERNAME)@$($env:USERDNSDOMAIN)")
				"msWMI-ChangeDate" = (Get-Date).ToUniversalTime().ToString("yyyyMMddhhmmss.ffffff-000")
			}
			$changeHappened = $false
			
			#region Calculating Filter
			if ($Filter)
			{
				# If receiving a fully valid filter string (e.g.: When updating from one Forest to another)
				if ($Filter -match '3;10;\d+;WQL')
				{
					$adAttributes['msWMI-Parm2'] = $Filter
				}
				else
				{
					$filterString = '{0};' -f $Filter.Count
					foreach ($filterItem in $Filter)
					{
						if ($filterItem -match '^root\\.+?;|^root;') { $filterString += "3;{0};{1};WQL;{2};" -f ($filterItem -split ";",2)[0].Length, ($filterItem -split ";",2)[1].Length, $filterItem }
						else { $filterString += "3;$($Namespace.Length);{0};WQL;$Namespace;{1};" -f $filterItem.Length, $filterItem }
					}
					$adAttributes['msWMI-Parm2'] = $filterString
				}
				if ($adAttributes['msWMI-Parm2'] -ne $wmiFilter.Filter) { $changeHappened = $true }
			}
			#endregion Calculating Filter
			#region Adding Description
			if ($Description)
			{
				$adAttributes['msWMI-Parm1'] = $Description
				if ($Description -ne $wmiFilter.Description) { $changeHappened = $true }
			}
			#endregion Adding Description
			#endregion Calculate AD Attribute Updates
			
			#region Validate Necessity
			if (-not $changeHappened)
			{
				Write-PSFMessage -String 'Set-GPWmiFilter.NoChangeNeeded' -StringValues $wmiFilter.Name, $wmiFilter.DistinguishedName
				if ($PassThru) { $wmiFilter }
				continue
			}
			#endregion Validate Necessity
			
			#region Perform Change
			$adParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Server, Credential
			Invoke-PSFProtectedCommand -ActionString 'Set-GPWmiFilter.PerformingUpdate' -ActionStringValues $wmiFilter.Name, $wmiFilter.DistinguishedName -ScriptBlock {
				Set-ADObject @adParameters -Identity $wmiFilter.DistinguishedName -Replace $adAttributes -ErrorAction Stop
			} -Target $wmiFilter.ID -EnableException $EnableException.ToBool() -PSCmdlet $PSCmdlet -Continue
			
			if ($PassThru)
			{
				$getParameters = $adParameters.Clone()
				$getParameters['Guid'] = $wmiFilter.ID
				Get-GPWmiFilter @getParameters
			}
			#endregion Perform Change
		}
	}
}


function Set-GPWmiFilterAssignment
{
<#
	.SYNOPSIS
		Assigns WMI Filters to GPOs.
	
	.DESCRIPTION
		Assigns WMI Filters to GPOs.
	
	.PARAMETER Policy
		The Group Policy Object to modify.
	
	.PARAMETER Filter
		The Filter to Apply.
	
	.PARAMETER Server
		The server to contact.
		Specify the DNS Name of a Domain Controller.
	
	.PARAMETER Credential
		The credentials to use to contact the targeted server.
	
	.PARAMETER EnableException
		This parameters disables user-friendly warnings and enables the throwing of exceptions.
		This is less user friendly, but allows catching exceptions in calling scripts.
	
	.EXAMPLE
		PS C:\> Get-GPO -Name '01_A_OU_1' | Set-GPWmiFilterAssignment -Filter 'Windows 10'
	
		Assigns the WMI Filter "WIndows 10" to the GPO "01_A_OU_1"
#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
		[Alias('Id', 'DisplayName')]
		$Policy,
		
		[Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
		$Filter,
		
		[string]
		$Server = $env:USERDNSDOMAIN,
		
		[System.Management.Automation.PSCredential]
		$Credential,
		
		[switch]
		$EnableException
	)
	
	begin
	{
		#region Resolve Server
		try { $PSBoundParameters.Server = Get-DomainController -Server $Server -Credential $Credential }
		catch
		{
			Stop-PSFFunction -String 'Set-GPWmiFilterAssignment.FailedADAccess' -StringValues $Server -EnableException $EnableException -ErrorRecord $_
			return
		}
		#endregion Resolve Server
		
		$adParameters = $PSBoundParameters | ConvertTo-PSFHashtable -Include Server, Credential
		$domainName = (Get-ADDomain @adParameters).DNSRoot
		
		#region Handle Explicit Filter input
		$filterExplicit = $false
		if (Test-PSFParameterBinding -Mode Explicit -ParameterName 'Filter')
		{
			if ($Filter.PSObject.TypeNames -eq 'GroupPolicy.WMIFilter')
			{
				$filterObject = $Filter
			}
			elseif ($Filter -as [System.Guid])
			{
				$filterObject = Get-GPWmiFilter @adParameters -Guid $Filter
			}
			else { $filterObject = Get-GPWmiFilter @adParameters -Name $Filter }
			
			if (-not $filterObject)
			{
				Stop-PSFFunction -String 'Set-GPWmiFilterAssignment.NoFilter' -StringValues $Filter -EnableException $EnableException
				return
			}
			if ($filterObject.Count -gt 1)
			{
				Stop-PSFFunction -String 'Set-GPWmiFilterAssignment.TooManyFilter' -StringValues $Filter -EnableException $EnableException
				return
			}
			$filterExplicit = $true
			$filterString = '[{0};{{{1}}};0]' -f $domainName, $filterObject.ID.ToString().ToUpper()
		}
		#endregion Handle Explicit Filter input
	}
	process
	{
		if (Test-PSFFunctionInterrupt) { return }
		
		#region Piped Filter Input
		if (-not $filterExplicit)
		{
			if ($Filter.PSObject.TypeNames -eq 'GroupPolicy.WMIFilter')
			{
				$filterObject = $Filter
			}
			elseif ($Filter -as [System.Guid])
			{
				$filterObject = Get-GPWmiFilter @adParameters -Guid $Filter
			}
			else { $filterObject = Get-GPWmiFilter @adParameters -Name $Filter }
			
			if (-not $filterObject)
			{
				Stop-PSFFunction -String 'Set-GPWmiFilterAssignment.NoFilter' -StringValues $Filter -EnableException $EnableException
				return
			}
			if ($filterObject.Count -gt 1)
			{
				Stop-PSFFunction -String 'Set-GPWmiFilterAssignment.TooManyFilter' -StringValues $Filter -EnableException $EnableException
				return
			}
			$filterString = '[{0};{{{1}}};0]' -f $domainName, $filterObject.ID.ToString().ToUpper()
		}
		#endregion Piped Filter Input
		
		foreach ($policyItem in ($Policy | Resolve-PolicyName))
		{
			$gpoObject = Get-ADObject @adParameters -LDAPFilter "(&(objectClass=groupPolicyContainer)(|(cn=$($policyItem))(cn={$($policyItem)})(displayName=$($policyItem))))"
			
			if (-not $gpoObject)
			{
				Write-PSFMessage -Level Warning -String 'Set-GPWmiFilterAssignment.GPONotFound' -StringValues $policyItem
				continue
			}
			
			Invoke-PSFProtectedCommand -ActionString 'Set-GPWmiFilterAssignment.UpdatingGPO' -ActionStringValues $filterObject.Name, $policyItem, $gpoObject -Target $policyItem -ScriptBlock {
				$gpoObject | Set-ADObject @adParameters -Replace @{ gPCWQLFilter = $filterString }
			} -Continue -PSCmdlet $PSCmdlet -EnableException $EnableException.ToBool()
		}
	}
}

<#
This is an example configuration file

By default, it is enough to have a single one of them,
however if you have enough configuration settings to justify having multiple copies of it,
feel totally free to split them into multiple files.
#>

<#
# Example Configuration
Set-PSFConfig -Module 'GPWmiFilter' -Name 'Example.Setting' -Value 10 -Initialize -Validation 'integer' -Handler { } -Description "Example configuration setting. Your module can then use the setting using 'Get-PSFConfigValue'"
#>

Set-PSFConfig -Module 'GPWmiFilter' -Name 'Import.DoDotSource' -Value $false -Initialize -Validation 'bool' -Description "Whether the module files should be dotsourced on import. By default, the files of this module are read as string value and invoked, which is faster but worse on debugging."
Set-PSFConfig -Module 'GPWmiFilter' -Name 'Import.IndividualFiles' -Value $false -Initialize -Validation 'bool' -Description "Whether the module files should be imported individually. During the module build, all module code is compiled into few files, which are imported instead by default. Loading the compiled versions is faster, using the individual files is easier for debugging and testing out adjustments."

Set-PSFConfig -Module 'GPWmiFilter' -Name 'Author' -Value "$($env:USERNAME)@$($env:USERDNSDOMAIN)" -Initialize -Validation 'string' -Description 'The name to use as Author when updating a WMI Filter.'

Register-PSFTeppScriptblock -Name 'GPWmiFilter.Filter' -ScriptBlock {
	$adParameters = @{ }
	if ($fakeBoundParameter.Server) { $adParameters['Server'] = $fakeBoundParameter.Server }
	if ($fakeBoundParameter.Credential) { $adParameters['Credential'] = $fakeBoundParameter.Credential }
	
	(Get-GPWmiFilter @adParameters).Name
}


Register-PSFTeppArgumentCompleter -Command Get-GPWmiFilter -Parameter Name -Name 'GPWmiFilter.Filter'
Register-PSFTeppArgumentCompleter -Command Remove-GPWmiFilter -Parameter Name -Name 'GPWmiFilter.Filter'
Register-PSFTeppArgumentCompleter -Command Rename-GPWmiFilter -Parameter Name -Name 'GPWmiFilter.Filter'
Register-PSFTeppArgumentCompleter -Command Set-GPWmiFilter -Parameter Name -Name 'GPWmiFilter.Filter'

Register-PSFTeppArgumentCompleter -Command Set-GPWmiFilterAssignment -Parameter Filter -Name 'GPWmiFilter.Filter'

New-PSFLicense -Product 'GPWmiFilter' -Manufacturer 'Friedrich Weinmann' -ProductVersion $script:ModuleVersion -ProductType Module -Name MIT -Version "1.0.0.0" -Date (Get-Date "2019-01-10") -Text @"
Copyright (c) 2019 Friedrich Weinmann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
#endregion Load compiled code
