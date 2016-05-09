<# Inspiration from
        http://blogs.msdn.com/b/opticalstorage/archive/2010/08/13/writing-optical-discs-using-imapi-2-in-powershell.aspx
    and
        http://tools.start-automating.com/Install-ExportISOCommand/
    with help from
        http://stackoverflow.com/a/9802807/223837 #>

$writeDVDScriptBlock = {
    
    param (
        [Parameter(Mandatory)]
        [System.Object[]] $Path,
        
        [Parameter()] [ValidateNotNullOrEmpty()]
        [System.String] $DestinationPath = "$(Get-Location -PSProvider FileSystem)\$((Get-Date).ToString('yyyyMMdd')).iso",

        [Parameter()] [ValidateNotNullOrEmpty()]
        [System.String] $VolumeName = 'New-ISO',
        
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()]
        [System.String] $DebugPreference,
        
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()]
        [System.String] $VerbosePreference,
        
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()]
        [System.String] $WarningPreference,
        
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()]
        [System.String] $ErrorActionPreference
    )
    
    function WriteIStreamToFile {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [__ComObject] $IStream,
            
            [Parameter(Mandatory)]
            [System.String] $DestinationPath
        )
        process {
            # NOTE: We cannot use [System.Runtime.InteropServices.ComTypes.IStream],
            # since PowerShell apparently cannot convert an IStream COM object to this
            # Powershell type.  (See http://stackoverflow.com/a/9037299/223837 for
            # details.)
            #
            # It turns out that .NET/CLR _can_ do this conversion.
            #
            # That is the reason why method FileUtil.WriteIStreamToFile(), below,
            # takes an object, and casts it to an IStream, instead of directly
            # taking an IStream inputStream argument.

            $compilerParameters = New-Object -TypeName 'CodeDom.Compiler.CompilerParameters';
            $compilerParameters.CompilerOptions = '/unsafe';
            $compilerParameters.WarningLevel = 4;
            $compilerParameters.TreatWarningsAsErrors = $true;

            if (-not ('FileUtil' -as [System.Type])) { 

                Add-Type -CompilerParameters $compilerParameters -TypeDefinition @'
                    using System;
                    using System.IO;
                    using System.Runtime.InteropServices.ComTypes;

                    namespace My
                    {

                        public static class FileUtil {
                            public static void WriteIStreamToFile(object i, string fileName) {
                                IStream inputStream = i as IStream;
                                FileStream outputFileStream = File.OpenWrite(fileName);
                                int bytesRead = 0;
                                int offset = 0;
                                byte[] data;
                                do {
                                    data = Read(inputStream, 2048, out bytesRead);  
                                    outputFileStream.Write(data, 0, bytesRead);
                                    offset += bytesRead;
                                } while (bytesRead == 2048);
                                outputFileStream.Flush();
                                outputFileStream.Close();
                            }

                            unsafe static private byte[] Read(IStream stream, int toRead, out int read) {
                                byte[] buffer = new byte[toRead];
                                int bytesRead = 0;
                                int* ptr = &bytesRead;
                                stream.Read(buffer, toRead, (IntPtr)ptr);   
                                read = bytesRead;
                                return buffer;
                            } 
                        }

                    }
'@
            }
        
            if (-not (Test-Path -Path $DestinationPath -IsValid)) {
                throw ($localized.InvalidDestinationPathError -f $DestinationPath);
            }
            [My.FileUtil]::WriteIStreamToFile($IStream, $DestinationPath);

        } #end process
    } #end function WriteIStreamToFile

    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage;
    $fsi.VolumeName = $VolumeName;
    $fsi.ChooseImageDefaultsForMediaType(12);
    
    foreach ($pathItem in $Path) {
        if ($pathItem -is [System.String]) {
            $pathItem = Get-Item -Path $pathItem;
        }
        
        if ($pathItem -is [System.IO.FileInfo]) {
            Write-Verbose ("Adding file '{0}'." -f $pathItem.FullName);
            $fsi.Root.AddTree($pathItem.FullName, $true);
        }
        elseif ($pathItem -is [System.IO.DirectoryInfo]) {
            Get-ChildItem -Path $pathItem.FullName | ForEach-Object {
                Write-Verbose ("Adding directory '{0}." -f $PSItem.FullName);
                $fsi.Root.AddTree($PSItem.FullName, $true);
            }
        }
    } #end foreach item
    
    Write-Verbose ("Writing ISO '{0}'." -f $DestinationPath);
    WriteIStreamToFile -IStream $fsi.CreateResultImage().ImageStream -DestinationPath $DestinationPath;
    return Get-Item -Path $DestinationPath;

} #end writeDVDScriptBlock

function New-LabISO {
<#
    .SYNOPSIS
        Creates the Lability Bootstrap ISO.
#>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        ## Direct
        [Parameter(Mandatory, ValueFromPipeline)]
        [System.Object[]] $Path,

        [Parameter(ValueFromPipelineByPropertyName)]
        [System.String] $DestinationPath = "$(Get-Location -PSProvider FileSystem)\$((Get-Date).ToString('yyyyMMdd')).iso",

        [Parameter()] [ValidateNotNullOrEmpty()]
        [System.String] $VolumeName = 'New-ISO',
        
        [Parameter()]
        [System.Management.Automation.SwitchParameter] $AsJob
    )
    
    begin {
        $pathObjects = @()
    }
    
    process {
        $pathObjects += $Path;
    }
    
    end {
        $startJobParams = @{
            ScriptBlock = $writeDVDScriptBlock;
            ArgumentList = @($pathObjects, $DestinationPath, $VolumeName, $DebugPreference, $VerbosePreference, $WarningPreference, $ErrorActionPreference);
        }
        $job = Start-Job @startJobParams;
        $activity = $localized.WritingDvdProgress;
        
        if (-not $AsJob) {
            while ($Job.HasMoreData -or $Job.State -eq 'Running') {     
                $percentComplete++;
                if ($percentComplete -gt 100) {
                    $percentComplete = 0;
                }
                Write-Progress -Id $job.Id -Activity $activity -Status $DestinationPath -PercentComplete $percentComplete;
                Receive-Job -Job $Job 
                Start-Sleep -Milliseconds 500;
            }

            Write-Progress -Id $job.Id -Activity $activity -Completed;
            $job | Receive-Job;
        }
        else {
            return $job;
        }
    }
} #end function New-LabISO
