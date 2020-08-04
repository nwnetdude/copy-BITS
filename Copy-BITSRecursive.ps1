#requires -version 3.0
#Copy-BITSRecursive.ps1
<#
    .Synopsis
    Copy a directory and contents recusively with BITS low priority
    .DESCRIPTION
    start a crapload of bits jobs and let them finish whenever
    monitor for completed jobs and log them (also need to log jobs we can't start)
    .EXAMPLE
    Example of how to use this cmdlet
    .EXAMPLE
    Another example of how to use this cmdlet
    .NOTES
    2020-06-24 Tim Evans, USW IT, Seattle, WA office
    If there are no files in the $source root folder, it will not be created on $dest
    2020-06-25 add progress bar
    2020-07-06 v1 final (start each job and wait for it to finish before next one)
    2020-07-30 alternate approach. Start all bits jobs at once and wait for them to finish
    TODO
    get files/bytes total summary from each bits transfer for end summary
    make logname a parameter
#>
[CmdletBinding()]
Param (
  # source directory
  [Parameter(Mandatory=$true,Position=0)]
  [string]$Source,
  # destination directory
  [Parameter(Mandatory=$true,Position=1)]
  [string]$Dest
)

Begin {
  Try {
    Import-Module -Name BitsTransfer
  } Catch {
    Throw 'Required module BitsTransfer not found'
  }
  #make sure source path has trailing \
  if (!($Source.EndsWith('\'))) {
    $Source = $Source + '\'
  }
  Write-Verbose -Message "gathering folders"
  $folders = Get-ChildItem -Name -Path $source -Directory -Recurse
  $TotalFolders = $folders.count
  Write-Verbose -Message "Copying $($TotalFolders) total folders"
}
Process {
  $FolderCount = 0
  #start files in root folder
  Write-Verbose -Message 'starting BITS jobs'
  if (Test-Path -Path ('{0}\*.*' -f $Source) -PathType Leaf) {
    $bitsjob = Start-BitsTransfer -Source $Source\*.* -Destination $Dest -asynchronous -Priority low
    $bitsjob.Description = ('{0} -> {1}' -f ($Source), ($Dest))
  }
  #start files in subfolders
  $ErrFolders = @()
  foreach ($i in $folders) {
    if (!(Test-Path -Path $Dest\$i)) {
      $null = New-Item -Path $Dest\$i -ItemType Directory
    }
    Write-Verbose -Message "copying $i"
    $FolderCount++
    $Percentage = (($FolderCount/$TotalFolders)*100)
    Write-Progress -Activity ('Copying {0}{1}' -f $Source, $i) -Status "Started $($FolderCount) of $($TotalFolders) folders" -PercentComplete $Percentage
    if (Test-Path -Path ('{0}{1}\*.*' -f $Source, $i) -PathType Leaf) {
      $err = $false
      Try {
        $bitsjob = Start-BitsTransfer -Source $Source$i\*.* -Destination $Dest\$i -asynchronous -Priority low
      } catch {
        $err = $true
      }
      if ($err) {
        Write-Host ('ERROR: {0} - skipping {1}' -f $error[0].tostring(), $i) 
        ('ERROR: {0} - skipping {1}' -f $error[0].tostring(), $i) | Out-File -FilePath c:\server\errs.log -Append
        $ErrFolders +=  $i
      } else {
        $bitsjob.DisplayName = ('{0}' -f $i)
      } #job started & description saved
    }
  } #end loop to start jobs 
  Write-Verbose -Message ('{0} jobs errored on start' -f $ErrFolders.count)
  #clean up jobs as they finish
  Write-Verbose -Message 'waiting for BITS jobs to complete'
  $BitsJobs = Get-BitsTransfer
  $TotalJobs = $BitsJobs.count
  While ($BitsJobs) {
    $BitsCount = $BitsJobs.count
    $Percentage = ($TotalJobs - $BitsCount)/$TotalJobs
    Write-Progress -Activity ('Copying {0}{1}' -f $Source, $i) -Status "Started $($FolderCount) of $($TotalJobs) folders" -PercentComplete $Percentage
    foreach ($Job in $BitsJobs) {
      if ($Job.JobState.ToString() -eq 'Transferred') {
        #Log Fields: JobId, DisplayName,Description,ErrorContext,ErrorCondition,InternalErrorCode, BytesTotal, FilesTotal,CreationTime
        Write-Host $Job.CreationTime, $Job.DisplayName, $Job.BytesTotal , $Job.FilesTotal, $i
        $Job.CreationTime, $Job.DisplayName, $Job.BytesTotal , $Job.FilesTotal | Export-Csv -Path c:\server\bits.log -Append -NoTypeInformation
        Complete-BitsTransfer -BitsJob $Job
      }
    }
    $BitsJobs = Get-BitsTransfer
  }
  #Write-Host $bitsjob.CreationTime, $bitsjob.DisplayName, $bitsjob.BytesTotal , $bitsjob.FilesTotal
  <# while (($bitsjob.JobState.ToString() -eq 'Transferring') -or ($bitsjob.JobState.ToString() -eq 'Connecting')) {
      Start-Sleep -Seconds $delay
  } #>
}
End {
}

 
