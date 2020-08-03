#Copy-BITSRecursive.ps1
<#
    .Synopsis
    Copy a directory and contents recusively with BITS low priority
    .DESCRIPTION
    Long description
    .EXAMPLE
    Example of how to use this cmdlet
    .EXAMPLE
    Another example of how to use this cmdlet
    .NOTES
    2020-06-24 Tim Evans, USW IT, Seattle, WA office
    If there are no files in the $source root folder, it will not be created on $dest
    2020-06-25 add progress bar
    2020-07-06 v1 final (start each job and wait for it to finish before next one)
    2020-07-15 V2 just start a crapload of bits jobs and let them finish whenever
    TODO
    wrap in a workflow so entire script will survive a reboot
    -alternate approach: just start a crapload of bits jobs and let them finish whenever
    --monitor for completed jobs and log them (also need to log jobs we can't start)
    get files/bytes total summary from each bits transfer for end summary
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
    Import-Module BitsTransfer
  } Catch {
    Throw 'Required module BitsTransfer not found'
  }
  #make sure source path has trailing \
  if (!($Source.EndsWith('\'))) {
    $Source = $Source + '\'
  }
  Write-Verbose "gathering folders"
  $folders = Get-ChildItem -Name -Path $source -Directory -Recurse
  $delay = 4
  $TotalFolders = $folders.count
  Write-Verbose "Copying $($TotalFolders) total folders"
}
Process {
  $FolderCount = 0
  $ErrFolders = @()
  Write-Verbose "Starting BITS jobs"
  #Start root folder
  if (Test-Path -Path ('{0}\*.*' -f $Source) -PathType Leaf) {
    $bitsjob = Start-BitsTransfer -Source $Source\*.* -Destination $Dest -asynchronous -Priority low
    $bitsjob.Description = ('{0} -> {1}' -f ($Source), ($Dest))
    <#    while (($bitsjob.JobState.ToString() -eq 'Transferring') -or ($bitsjob.JobState.ToString() -eq 'Connecting')){
        Start-Sleep -Seconds $delay
        }
        Complete-BitsTransfer -BitsJob $bitsjob
    #>
  }
  #Start BITS jobs for subfolders
  foreach ($i in $folders) {
    if (!(Test-Path -Path $Dest\$i)) {
      $null = New-Item -Path $Dest\$i -ItemType Directory
    }
    Write-Verbose "copying $i"
    $FolderCount++
    $Percentage = (($FolderCount/$TotalFolders)*100)
    Write-Progress -Activity ('Copying {0}{1}' -f $Source, $i) -Status "copied $($FolderCount) of $($TotalFolders) folders" -PercentComplete $Percentage
    if (Test-Path -Path ('{0}{1}\*.*' -f $Source, $i) -PathType Leaf) {
      $err = $false
      Try {
        $bitsjob = Start-BitsTransfer -Source $Source$i\*.* -Destination $Dest\$i -asynchronous -Priority low
      } catch {
        $err = $true
        $ErrFolders += $i
      }
      if ($err) {
        Write-Host ('ERROR: {0} - skipping' -f $error[0].tostring()) 
        ('ERROR: {0} - skipping {1}' -f $error[0].tostring(), $i) | Out-File c:\server\errs.log -Append
      } else {
        $bitsjob.Description = ('{0}' -f $i)
        <#        while (($bitsjob.JobState.ToString() -eq 'Transferring') -or ($bitsjob.JobState.ToString() -eq 'Connecting')) {
            Start-Sleep -Seconds $delay
            }
            #Log Fields: JobId, DisplayName,Description,ErrorContext,ErrorCondition,InternalErrorCode, BytesTotal, FilesTotal,CreationTime
            Write-Host $bitsjob.CreationTime, $bitsjob.Description, $bitsjob.BytesTotal , $bitsjob.FilesTotal, $i
            $bitsjob.CreationTime, $bitsjob.Description, $bitsjob.BytesTotal , $bitsjob.FilesTotal | Export-Csv c:\server\bits.log -Append -NoTypeInformation
            Complete-BitsTransfer -BitsJob $bitsjob
        #>
      }
    }
  } #Start all BITSjobs
  $FolderCount = 0
  $BITSJobs = Get-BitsTransfer
  While ($BITSJobs) {
    $Percentage = (($FolderCount/$TotalFolders)*100)
    Write-Progress -Activity ('Running BITSJobs') -Status "Completed $($FolderCount) of $($TotalFolders) jobss" -PercentComplete $Percentage
    foreach ($Job in $BITSJobs) {
      if ($Job.JobState.ToString() -eq 'Complete') {
        Write-Host $Job.CreationTime, $Job.Description, $Job.BytesTotal , $Job.FilesTotal
        Complete-BitsTransfer -BitsJob $Job
        $FolderCount++
      }
    } #Processe all completed jobs
    $BITSJobs = Get-BitsTransfer
  }
}
End {
}

 
