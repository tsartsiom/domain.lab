﻿@{
	# Script module or binary module file associated with this manifest
	ModuleToProcess = 'GPWmiFilter.psm1'
	
	# Version number of this module.
	ModuleVersion = '1.0.5'
	
	# ID used to uniquely identify this module
	GUID = '7f95af7a-99e4-4a74-a4e6-9eb41b8f82f8'
	
	# Author of this module
	Author = 'Friedrich Weinmann'
	
	# Company or vendor of this module
	CompanyName = 'Microsoft'
	
	# Copyright statement for this module
	Copyright = 'Copyright (c) 2019 Friedrich Weinmann'
	
	# Description of the functionality provided by this module
	Description = 'Module to manage WMI Filter'
	
	# Minimum version of the Windows PowerShell engine required by this module
	PowerShellVersion = '5.0'
	
	# Modules that must be imported into the global environment prior to importing
	# this module
	RequiredModules = @(
		@{ ModuleName='PSFramework'; ModuleVersion='1.0.19' }
	)
	
	# Assemblies that must be loaded prior to importing this module
	# RequiredAssemblies = @('bin\GPWmiFilter.dll')
	
	# Type files (.ps1xml) to be loaded when importing this module
	# TypesToProcess = @('xml\GPWmiFilter.Types.ps1xml')
	
	# Format files (.ps1xml) to be loaded when importing this module
	FormatsToProcess = @('xml\GPWmiFilter.Format.ps1xml')
	
	# Functions to export from this module
	FunctionsToExport = @(
		'Clear-GPWmiFilterAssignment'
		'Get-GPWmiFilter'
		'New-GPWmiFilter'
		'Remove-GPWmiFilter'
		'Rename-GPWmiFilter'
		'Set-GPWmiFilter'
		'Set-GPWmiFilterAssignment'
	)
	
	# Cmdlets to export from this module
	CmdletsToExport = ''
	
	# Variables to export from this module
	VariablesToExport = ''
	
	# Aliases to export from this module
	AliasesToExport = ''
	
	# List of all modules packaged with this module
	ModuleList = @()
	
	# List of all files packaged with this module
	FileList = @()
	
	# Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
	PrivateData = @{
		
		#Support for PowerShellGet galleries.
		PSData = @{
			
			ExternalModuleDependencies = @(
				'ActiveDirectory'
			)
			
			# Tags applied to this module. These help with module discovery in online galleries.
			Tags = @('GroupPolicy', 'GPO', 'WmiFilter', 'Wmi')
			
			# A URL to the license for this module.
			# LicenseUri = ''
			
			# A URL to the main website for this project.
			# ProjectUri = ''
			
			# A URL to an icon representing this module.
			# IconUri = ''
			
			# ReleaseNotes of this module
			# ReleaseNotes = ''
			
		} # End of PSData hashtable
		
	} # End of PrivateData hashtable
}
