<#

.SYNOPSIS
  This script checks the consumed memory and CPU utilisation of a single process.

.DESCRIPTION
  This powershell script reads the performance data from the WMI of a given Process and compares it with the given thresholds.
  The exit codes are equivalent to the nagios exit codes

.PARAMETER Mem
    The Mem parameter is only a switch to enable the two parameters MemWarn and MemCrit

.PARAMETER MemWarn
    The MemWarn parameter is the threshold in Megabytes to throw a "WARNING" error in memory consumption

.PARAMETER MemCrit
    The MemCrit parameter is the threshold in Megabytes to throw a "CRITICAL" error in memory consumption

.PARAMETER CPU
    The CPU parameter is only a switch to enable the two parameters CPUWarn and CPUCrit

.PARAMETER CPUWarn
    The CPUWarn parameter is the threshold in percent to throw a "WARNING" error in CPU consumption

 .PARAMETER CPUCrit
    The CPUCrit parameter is the threshold in percent to throw a "CRITICAL" error in CPU consumption
 
.PARAMETER Count
    The Count parameter is to count the amount of processes are running

.PARAMETER CountWarn
    The CountWarn parameter is the threshold in INT to throw a "WARNING" error in process counting

.PARAMETER CountCrit
    The CountCrit parameter is the threshold in INT to throw a "CRITICAL" error in process counting

.PARAMETER Version
    The CountCrit parameter writes the Version of this script

.INPUTS
  None

.OUTPUTS
  Log file stored in C:\temp\Get-ProcessRessources.log
  Can be changed in the Write-Log function

.NOTES
  Copyright 2016 RealStuff Informatik AG

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; version 2
  of the License.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.


  Version:        1.3.2 (do also edit in $global:ScriptVersion)
  Author:         Bruno Fernandez, RealStuff Informatik AG, CH
  Creation Date:  20160909
  Purpose/Change: 20160909 Initial script development
                  20160915 Added output for Nagios (Write-Host)
                  20160916 Changed memory input and output from Kbyte to Mbyte
                  20160916 Correction of output when both switches are selected
                  20160916 Disable logging, added Copyright
                  20160916 Removed new line from Write-Host
				  20170306 Added the count parameter to count processes, also added Version switch
				  20170307 Added the possibility only to set the cound flag
                  20170313 Textmessage Output modified (rhu)

.EXAMPLE
  .\Get-ProcessRessources.ps1 -Process taskmgr -Mem -MemWarn 1024 -MemCrit 2048
  
  With this command you set the warn level of memory consumption to 1024MB and critical level to 2048MB

.EXAMPLE
  .\Get-ProcessRessources.ps1 -Process taskmgr -CPU -CPUWarn 15 -CPUCrit 25

  With this command you set the warn level of CPU consumption to 15% and the critical level to 25%

.EXAMPLE
  .\Get-ProcessRessources.ps1 -Process taskmgr -Mem -MemWarn 1024 -MemCrit 2048 -CPU -CPUWarn 10 -CPUCrit 25
  
  With this command you set the warn level for CPU and memory at the same time

.EXAMPLE
  .\Get-ProcessRessources.ps1 -Process taskmgr -Mem -MemWarn 1024 -MemCrit 2048 -CPU -CPUWarn 10 -CPUCrit 25 -Count -CountWarn 1 CountCrit 5

  With this command you set the warn revel for CPU and memory at the same time. Additionally you count the running processes

#>


#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Requires -Version 2.0

param (
    [Parameter(Mandatory=$true)][string]$Process,
    [switch]$Mem,
    [UInt64]$MemWarn,
    [UInt64]$MemCrit,
    [switch]$CPU,
    [Int]$CPUWarn,
	[Int]$CPUCrit,
	[switch]$Count,
	[Int]$CountWarn,
	[Int]$CountCrit,
	[switch]$Version
)


#----------------------------------------------------------[Declarations]----------------------------------------------------------


#Global Vars
$global:ProcessList = $null
$global:FilteredProcessList = $null
$global:CPUInUse = $null
[UInt64]$global:MemoryInuse = $null
$global:ScriptVersion = "1.3.2"

#Nagios exit codes
$ExitCodes = 
@{
    "UNKNOWN"    = 3;
    "CRITICAL"   = 2;
    "WARNING"    = 1;
    "OK"         = 0
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Write-Version
{
	if ($Version)
	{
		Write-Host -NoNewline -ForegroundColor Yellow "Version: "$global:ScriptVersion
		exit 0
	}
	
}

#Write-Log function by @wasserja
#https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0
#Customized by Bruno Fernandez, RealStuff Informatik AG, CH
function Write-Log 
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path='C:\temp\Get-ProcessRessources.log', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden. 
        $VerbosePreference = 'SilentlyContinue'

        # Set WarningPreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden.
        $WarningPreference = 'SilentlyContinue'
        
        # Set ErrorActionPreference to Continue or SilentlyContinue so that verbose messages are displayed or hidden.
        $ErrorActionPreference = "SilentlyContinue"
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End 
    { 
    }
}


#This function creates an ArrayList of all running processes on the system by querying the WMI
Function Get-Processes {
    $global:ProcessList = Get-WmiObject Win32_PerfFormattedData_PerfProc_Process
    if (!$global:ProcessList){
        #Write-Log -Level Warn -Message "No processes found"
        Write-Host -NoNewline ("UNKNOWN - Process " + $Process + " not found")
        exit $ExitCodes["UNKNOWN"]
        }
    else {
        #Write-Log -Level Info -Message "Process List has content"
    }
}

#This function searches in the process Arraylist for the given process name
Function Filter-Processes($global:ProcessList, $Process){
    #Write-Log -Level Info -Message "Filtering ProcessList for $Process"
    $global:FilteredProcessList = @($global:ProcessList | ?{$_.Name -match "$Process"})

    #If no process is found, the script will end here with a warning in the log and exit code UNKNOWN
    if ($global:FilteredProcessList.Count -eq 0 ){
        #Write-Log -Level Warn -Message "Could not find any process with the process name $Process"
        #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["UNKNOWN"])
        Write-Host -NoNewline ("UNKNOWN - Process " + $Process + " not found")
        exit $ExitCodes["UNKNOWN"]
    }
    if ($global:FilteredProcessList.Count -ge 1 ){
        #Write-Log -Level Info -Message ("Found " + $global:FilteredProcessList.Count + " process(es)")
    }
}


#This function counts the memory consumption in MB of the process and child processes
Function Count-MemoryUtilization($global:FilteredProcessList){
    #Write-Log -Level Info -Message "Counting the Memory utilization for all processes"
    Foreach ($SingleProcess in $global:FilteredProcessList){
        $global:MemoryInuse += $SingleProcess.WorkingSetPrivate/1024/1024
        #Write-Log -Level Info -Message ( "$global:MemoryInuse MB of memory is in use")
    }
    #Write-Log -Level Info -Message ("We have a total of " + $global:MemoryInuse + " MB of memory in use")
}

#This function counts the CPU consumption in % of the process and child processes
Function Count-CPUUitlization($global:FilteredProcessList){
    #Write-Log -Level Info -Message "Counting the CPU utilization for all processes"
    Foreach ($SingleProcess in $global:FilteredProcessList){
        $global:CPUInUse += $SingleProcess.PercentProcessorTime
        #Write-Log -Level Info -Message ( "$global:CPUInUse % of CPU is in use")
    }
    #Write-Log -Level Info -Message ("We have a total of " + $global:CPUInUse + " % of CPU is in use")
}

#This function compares the effective consumption with the given thresholds
Function Check-Thresholds { 
    #Write-Log -Level Info -Message "Checking Thresholds"
	#Check only memory threshold if memory switch is set
	###################################################################
	#
	#
	#####New part here
	#
	#go here only if Count flag is set
	
	if ($Count)
	{
		if ($Mem -and !$CPU)
		{
			#Write-Log -Level Info -Message "Mem switch was set but CPU not"
			#Write-Log -Level Info -Message "Checking if Mem thresholds are exceeded"
			
			if ($global:MemoryInuse -ge $MemWarn)
			{
				#Write-Log -Level Warn -Message "Memory thresholds are exeeded...Checking if critical or warning"
				if ($global:MemoryInuse -ge $MemCrit)
				{
					if (($global:FilteredProcessList).count -ge $CountCrit)
					{
						Write-Host -NoNewline ("CRITICAL - (C)Mem=" + $global:MemoryInUse + "MB, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
					elseif (($global:FilteredProcessList).count -ge $CountWarn)
					{
						Write-Host -NoNewline ("CRITICAL - (C)Mem=" + $global:MemoryInUse + "MB, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
					#Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["CRITICAL"])
					else {
						Write-Host -NoNewline ("CRITICAL - (C)Mem=" + $global:MemoryInUse + "MB, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
			}
			#Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
				if (($global:FilteredProcessList).count -ge $CountCrit)
				{
					Write-Host -NoNewline ("CRITICAL - (W)Mem=" + $global:MemoryInUse + "MB, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["CRITICAL"]
				}
				elseif (($global:FilteredProcessList).count -ge $CountWarn)
				{
					Write-Host -NoNewline ("WARNING - (W)Mem=" + $global:MemoryInUse + "MB, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["WARNING"]
				}
				else
				{
					Write-Host -NoNewline ("WARNING - (W)Mem=" + $global:MemoryInUse + "MB, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["WARNING"]
				}
			}
			#Write-Log -Level Info -Message "Memory thresholds are not exeeded"
			#Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
			if (($global:FilteredProcessList).count -ge $CountCrit)
			{
				Write-Host -NoNewline ("CRITICAL - Mem=" + $global:MemoryInUse + "MB, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["CRITICAL"]
			}
			elseif (($global:FilteredProcessList).count -ge $CountWarn)
			{
				Write-Host -NoNewline ("WARNING - Mem=" + $global:MemoryInUse + "MB, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["WARNING"]
			}
			else
			{
				Write-Host -NoNewline ("OK - Mem=" + $global:MemoryInUse + "MB, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["OK"]
			}

		}
		#Check only cpu threshold if cpu switch is set
		if ($CPU -and !$Mem)
		{
			#Write-Log -Level Info -Message "CPU switch was set but Mem not"
			#Write-Log -Level Info -Message "Checking if CPU thresholds are exceeded"
			if ($global:CPUInUse -ge $CPUWarn)
			{
				#Write-Log -Level Warn -Message "CPU threshold are exeeded...Checking if critical or warning"
				if ($global:CPUInuse -ge $CPUCrit)
				{
					if (($global:FilteredProcessList).count -ge $CountCrit)
					{
						Write-Host -NoNewline ("CRITICAL - (C)CPU=" + $global:CPUInUse + "%, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
					elseif (($global:FilteredProcessList).count -ge $CountWarn)
					{
						Write-Host -NoNewline ("CRITICAL - (C)CPU=" + $global:CPUInUse + "%, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
					else
					{
						Write-Host -NoNewline ("CRITICAL - (C)CPU=" + $global:CPUInUse + "%, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
						exit $ExitCodes["CRITICAL"]
					}
					#Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["CRITICAL"])
				}
				#Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
				if (($global:FilteredProcessList).count -ge $CountCrit)
				{
					Write-Host -NoNewline ("CRITICAL - (W)CPU=" + $global:CPUInUse + "%, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["CRITICAL"]
				}
				elseif (($global:FilteredProcessList).count -ge $CountWarn)
				{
					Write-Host -NoNewline ("WARNING - (W)CPU=" + $global:CPUInUse + "%, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["WARNING"]
				}
				else
				{
					Write-Host -NoNewline ("WARNING - (W)CPU=" + $global:CPUInUse + "%, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
					exit $ExitCodes["WARNING"]
				}
				
			}
			#Write-Log -Level Info -Message "CPU thresholds are not exeeded"
			#Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
			if (($global:FilteredProcessList).count -ge $CountCrit)
			{
				Write-Host -NoNewline ("CRITICAL - CPU=" + $global:CPUInUse + "%, (C)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["CRITICAL"]
			}
			elseif (($global:FilteredProcessList).count -ge $CountWarn)
			{
				Write-Host -NoNewline ("WARNING - CPU=" + $global:CPUInUse + "%, (W)Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["WARNING"]
			}
			else
			{
				Write-Host -NoNewline ("OK - CPU=" + $global:CPUInUse + "%, Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["OK"]
			}
		}
		#Check memory and cpu thresholds if both switches are set
		if ($CPU -and $Mem)
		{
			#Write-Log -Level Info -Message "CPU  and Mem switches were set"
			#Write-Log -Level Info -Message "Checking if CPU or Memory thresholds are exceeded"
			###Checking CPU exit code
			if ($global:CPUInUse -ge $CPUCrit)
			{
				#Write-Log -Level Warn -Message "CPU critical threshold is exeeded"
				$CPUTempExitCode = $ExitCodes["CRITICAL"]
                $CPUTempSwitch = "(C)"
			}
			elseif ($global:CPUInUse -ge $CPUWarn)
			{
				#Write-Log -Level Warn -Message "CPU warning threshold is exeeded"
				$CPUTempExitCode = $ExitCodes["WARNING"]
                $CPUTempSwitch = "(W)"
			}
			elseif ($global:CPUInUse -lt $CPUWarn)
			{
				#Write-Log -Level Info -Message "CPU warning threshold is NOT exeeded"
				$CPUTempExitCode = $ExitCodes["OK"]
                $CPUTempSwitch = ""
			}
			
			###Checking Memory exit code
			if ($global:MemoryInUse -ge $MemCrit)
			{
				#Write-Log -Level Warn -Message "Memory critical threshold is exeeded"
				$MemTempExitCode = $ExitCodes["CRITICAL"]
                $MemTempSwitch = "(C)"
			}
			elseif ($global:MemoryInUse -ge $MemWarn)
			{
				#Write-Log -Level Warn -Message "Memory warning threshold is exeeded"
				$MemTempExitCode = $ExitCodes["WARNING"]
                $MemTempSwitch = "(W)"
			}
			elseif ($global:MemoryInUse -lt $MemWarn)
			{
				#Write-Log -Level Info -Message "Memory warning threshold is NOT exeeded"
				$MemTempExitCode = $ExitCodes["OK"]
                $MemTempSwitch = ""
			}
			
			
			
			###Checking Process count exit code
			if (($global:FilteredProcessList).count -ge $CountCrit)
			{
				#Write-Log -Level Warn -Message "CPU critical threshold is exeeded"
				$ProcessTempExitCode = $ExitCodes["CRITICAL"]
                $ProcessTempSwitch = "(C)"
			}
			elseif (($global:FilteredProcessList).count -ge $CountWarn)
			{
				#Write-Log -Level Warn -Message "CPU warning threshold is exeeded"
				$ProcessTempExitCode = $ExitCodes["WARNING"]
                $ProcessTempSwitch = "(W)"
			}
			elseif (($global:FilteredProcessList).count -lt $CountWarn)
			{
				#Write-Log -Level Info -Message "CPU warning threshold is NOT exeeded"
				$ProcessTempExitCode = $ExitCodes["OK"]
                $ProcessTempSwitch = ""
			}
			
			######Checking exit code
			if ($CPUTempExitCode -eq 2 -or $MemTempExitCode -eq 2 -or $ProcessTempExitCode -eq 2)
			{
				$TempExitCode = "CRITICAL"
				#Write-Log -Level Warn -Message "Exit code was set to CRITICAL"
			}
			elseif ($CPUTempExitCode -eq 1 -or $MemTempExitCode -eq 1 -or $ProcessTempExitCode -eq 1)
			{
				$TempExitCode = "WARNING"
				#Write-Log -Level Warn -Message "Exit code was set to WARNING"
			}
			elseif ($CPUTempExitCode -eq 0 -and $MemTempExitCode -eq 0 -or $ProcessTempExitCode -eq 0)
			{
				$TempExitCode = "OK"
				#Write-Log -Level Info -Message "Exit code was set to OK"
			}
			#Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes[$TempExitCode])
			Write-Host -NoNewline ($TempExitCode + " - " + $MemTempSwitch + "Mem=" + $global:MemoryInUse + "MB, " + $CPUTempSwitch + "CPU=" + $global:CPUInUse + "%, " + $ProcessTempSwitch + "Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
			exit $ExitCodes[$TempExitCode]
		}
		
		if (!$CPU -and !$Mem)
		{
			if (($global:FilteredProcessList).count -ge $CountCrit)
			{
				Write-Host -NoNewline ("CRITICAL - Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["CRITICAL"]
			}
			elseif (($global:FilteredProcessList).count -ge $CountWarn)
			{
				Write-Host -NoNewline ("WARNING - Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["WARNING"]
			}
			else
			{
				Write-Host -NoNewline ("OK - Proc=" + ($global:FilteredProcessList).count + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
				exit $ExitCodes["OK"]
			}
		}
	}
	#
	#
	###################################################################
	
	
    if ($Mem -and !$CPU){
        #Write-Log -Level Info -Message "Mem switch was set but CPU not"
        #Write-Log -Level Info -Message "Checking if Mem thresholds are exceeded"
        
        if($global:MemoryInuse -ge $MemWarn){
            #Write-Log -Level Warn -Message "Memory thresholds are exeeded...Checking if critical or warning"
            if($global:MemoryInuse -ge $MemCrit){
                #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["CRITICAL"])
                Write-Host -NoNewline ("CRITICAL - Mem=" + $global:MemoryInUse + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
                exit $ExitCodes["CRITICAL"]
            }
            #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
            Write-Host -NoNewline ("WARNING - Mem=" + $global:MemoryInUse + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
            exit $ExitCodes["WARNING"]
        }
        #Write-Log -Level Info -Message "Memory thresholds are not exeeded"
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
        Write-Host -NoNewline ("OK - Mem=" + $global:MemoryInUse + " | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
        exit $ExitCodes["OK"]
    }
    #Check only cpu threshold if cpu switch is set
    if ($CPU -and !$Mem){
        #Write-Log -Level Info -Message "CPU switch was set but Mem not"
        #Write-Log -Level Info -Message "Checking if CPU thresholds are exceeded"
        if($global:CPUInUse -ge $CPUWarn){
            #Write-Log -Level Warn -Message "CPU threshold are exeeded...Checking if critical or warning"
            if($global:CPUInuse -ge $CPUCrit){
                #Write-Log -Level Warn -Message ("Script ended with exit code " + ExitCodes["CRITICAL"])
                Write-Host -NoNewline ("CRITICAL - CPU=" + $global:CPUInUse + "% | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
                exit $ExitCodes["CRITICAL"]
            }
            #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["WARNING"])
            Write-Host -NoNewline ("WARNING - CPU=" + $global:CPUInUse + "% | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
            exit $ExitCodes["WARNING"]
        }
        #Write-Log -Level Info -Message "CPU thresholds are not exeeded"
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes["OK"])
        Write-Host -NoNewline ("OK - CPU=" + $global:CPUInUse + "% | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
        exit $ExitCodes["OK"]
    }
    #Check memory and cpu thresholds if both switches are set
    if ($CPU -and $Mem){
        #Write-Log -Level Info -Message "CPU  and Mem switches were set"
        #Write-Log -Level Info -Message "Checking if CPU or Memory thresholds are exceeded"
        if($global:CPUInUse -ge $CPUCrit){
            #Write-Log -Level Warn -Message "CPU critical threshold is exeeded"
            $CPUTempExitCode = $ExitCodes["CRITICAL"]
            $CPUTempSwitch = "(C)"
        }
        elseif($global:CPUInUse -ge $CPUWarn){
            #Write-Log -Level Warn -Message "CPU warning threshold is exeeded"
            $CPUTempExitCode = $ExitCodes["WARNING"]
            $CPUTempSwitch = "(W)"
        }
        elseif($global:CPUInUse -lt $CPUWarn){
            #Write-Log -Level Info -Message "CPU warning threshold is NOT exeeded"
            $CPUTempExitCode = $ExitCodes["OK"]
            $CPUTempSwitch = ""
        }
        if($global:MemoryInUse -ge $MemCrit){
            #Write-Log -Level Warn -Message "Memory critical threshold is exeeded"
            $MemTempExitCode = $ExitCodes["CRITICAL"]
            $MemTempSwitch = "(C)"
        }
        elseif($global:MemoryInUse -ge $MemWarn){
            #Write-Log -Level Warn -Message "Memory warning threshold is exeeded"
            $MemTempExitCode = $ExitCodes["WARNING"]
            $MemTempSwitch = "(W)"
        }
        elseif($global:MemoryInUse -lt $MemWarn){
            #Write-Log -Level Info -Message "Memory warning threshold is NOT exeeded"
            $MemTempExitCode = $ExitCodes["OK"]
            $MemTempSwitch = ""
        }
        if($CPUTempExitCode -eq 2 -or $MemTempExitCode -eq 2){
            $TempExitCode = "CRITICAL"
            #Write-Log -Level Warn -Message "Exit code was set to CRITICAL"
        }
        if($CPUTempExitCode -eq 1 -or $MemTempExitCode -eq 1){
            $TempExitCode = "WARNING"
            #Write-Log -Level Warn -Message "Exit code was set to WARNING"
        }
        if($CPUTempExitCode -eq 0 -and $MemTempExitCode -eq 0){
            $TempExitCode = "OK"
            #Write-Log -Level Info -Message "Exit code was set to OK"
        }
        #Write-Log -Level Info -Message ("Script ended with exit code " + $ExitCodes[$TempExitCode])
        Write-Host -NoNewline ($TempExitCode + " - " +$MemTempSwitch + "Mem=" + $global:MemoryInUse + "MB, " + $CPUTempSwitch + "CPU=" + $global:CPUInUse + "% | mem=" + $global:MemoryInuse + ";" + $MemWarn + ";" + $MemCrit + " cpu=" + $global:CPUInUse + ";" + $CPUWarn + ";" + $CPUCrit + " proc=" + (($global:FilteredProcessList).count) + ";" + $CountWarn + ";" + $CountCrit)
        exit $ExitCodes[$TempExitCode]
    }
    #Don't check if no switch was set
	if (!$CPU -and !$Mem -and !$Count){
    #Write-Log -Level Warn -Message "No switch was set. Please select at least one of both"
    #Write-Log -Level Warn -Message ("Script ended with exit code " + $ExitCodes["UNKNOWN"])
    Write-Host -NoNewline ("UNKNOWN - No switch was set. Please select at least one of both")
    exit $ExitCodes["UNKNOWN"]
	}
}

#-----------------------------------------------------------[Main]------------------------------------------------------------

#Write-Log -Level Info -Message "Running Write-Version"

Write-Version

#Write-Log -Level Info -Message "Running Get-Processes"

Get-Processes

#Write-Log -Level Info -Message "Running Filter-Processes"

Filter-Processes $global:ProcessList $Process

#Write-Log -Level Info -Message "Running Count-MemoryUtilization"

Count-MemoryUtilization $global:FilteredProcessList

#Write-Log -Level Info -Message "Running Count-CPUUtilization"

Count-CPUUitlization $global:FilteredProcessList


#Write-Log -Level Info -Message "Running Check-Thresholds"

Check-Thresholds
