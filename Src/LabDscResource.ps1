function Copy-LabDscResource {
<#
    .SYNOPSIS
        Copies the Lability PowerShell DSC resource modules.
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        ## Specifies a PowerShell DSC configuration document (.psd1) containing the lab configuration.
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $ConfigurationData,

        ## Lability bootstrap path
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [System.String] $DestinationPath
    )
    begin {
        [System.Collections.Hashtable] $ConfigurationData = ConvertToConfigurationData -ConfigurationData $ConfigurationData;
    }
    process {

        $scriptBlock = {
            param (
                [System.Collections.Hashtable[]] $Module,
                [System.String] $DestinationPath
            )
            ExpandModuleCache -Module $Module -DestinationPath $DestinationPath;
        }

        if ($null -ne $ConfigurationData.NonNodeData.Lability.DSCResource) {

            $modulesPath = Join-Path -Path $DestinationPath -ChildPath $defaults.ModulesPath;
            Write-Verbose -Message ($localized.CopyingDscResourceModules -f $modulesPath);

            if ($PSCmdlet.ShouldProcess($modulesPath, $localized.CopyDscModulesConfirmation)) {
                & $lability $scriptBlock -Module $ConfigurationData.NonNodeData.Lability.DSCResource -DestinationPath $modulesPath;
            }

        }

    } #end process
} #end function Copy-LabDscResource
