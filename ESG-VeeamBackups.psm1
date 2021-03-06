Function Start-ESGJob ()
{
    [Cmdletbinding()]
    Param(

        [Parameter(Mandatory=$true,
        HelpMessage="Name of the VM")]
        [string]$Name,
        [Parameter(Mandatory=$false,
        HelpMessage="Execute and job and return immediately")]
        [switch]$RunAsync

    )
    <#
    .SYNOPSIS
    Executes the ESG Veeam backup jobs.

    .DESCRIPTION
    Start-ESGJob is a custom function that loads the Veeam Snapins and
    imports the Veeam modules, then executes the job.

    The intent of this function is to make running Veeam job easier.

    .PARAMETER Name
    This is the name of the job or virtual machine

    .PARAMETER RunAsync
    This is a switch, telling the job to execute and not wait for completion.

    .INPUTS
    None. You cannot pipe objects to Start-ESGJob

    .OUTPUTS
    none.

    .EXAMPLE
    C:\PS> Start-ESGJob -Name <jobname>

    .EXAMPLE
    C:\PS> Start-ESGJob -Name <jobname> -RunAsync

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    #>

    If (get-command Get-VBRCredentials -ErrorAction silentlycontinue)
    {
        Write-Output "Veeam snapin loaded"
    }
    else
    {
        Write-Output "attempting to load veeam snapins"
        Import-Module veeam*
    }

    Add-PSSnapin VeeamPSSnapin -ErrorAction Ignore

    If ($runasync)
    {
        Start-VBRJob $Name -runasync
    }
    else
    {
        Start-VBRJob $Name
    }
}
function Connect-ESGVeeam ()
{
    <#
    .SYNOPSIS
    Connects to vCenter and creates the credential objects
    required to create and update jobs.

    .DESCRIPTION
    Connect-ESGVeeam load the credential objects based on the
    credential files.

    The intent of this function is be called from other functions.

    .PARAMETER None

    .INPUTS
    None. You cannot pipe objects to Invoke-ESGVeeamJobs.

    .OUTPUTS
    none.

    .EXAMPLE
    C:\PS> Connect-ESGVeeam

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    #>
    # We need to change into the correct directory to pick up the credentials.
    $dir = "c:\batch\zabbix\veeambackups"
    set-location $dir

    If (get-command Get-VBRCredentials -ErrorAction silentlycontinue)
    {
        Write-Output "Veeam snapin loaded"
    }
    else
    {
        Write-Output "attempting to load veeam snapins"
        Import-Module veeam*

        try
        {
            Add-PSSnapin VeeamPSSnapin -ErrorAction Stop
        }
        catch
        {
            $error[0]
        }
    }
    

    # set credentials
    $User = Get-Content .\account.txt
    $pw = convertto-securestring (get-content .\encrypt.txt) -key (Get-Content .\10112017.key)
    $Creds = New-Object System.Management.Automation.PSCredential($User,$pw)
    $veeamcreds = Get-VBRCredentials -Name $User
    $viserver = "vcsa.$($domainfqdn1)"

    # connect to vmware
    if (Get-VIServer -Server $viserver -Credential $Creds)
    {
        Write-Output "Connected to viserver vcsa"
    }
    else
    {
        Write-Output "Not connected, attempting to connect"
        Connect-VIServer -Server $viserver -Credential $Creds 
    }
}

function Send-ESGVeeamEmail ()
{
    [Cmdletbinding()]
    Param(

        [Parameter(Mandatory=$true,
        HelpMessage="Name of the VM")]
        [string]$Name

    )
    <#
    .SYNOPSIS
    Sends ESG Specific email based on job creation results.

    .DESCRIPTION
    Send-ESGVeeamEmail is designed to be programatically called
    from other functions.  It will send a static email message
    to recipients based on the Invoke-ESGVeeamJobs function.

    The intent of this function is be called from other functions.

    .PARAMETER Name
    Name is the name of the job that was created.

    .INPUTS
    None. You cannot pipe objects to Invoke-ESGVeeamJobs.

    .OUTPUTS
    none.

    .EXAMPLE
    C:\PS> Send-ESGVeeamEmail -Name <jobname>

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    .LINK
    Set-Item
    #>
    # variables
    $destination = "alert-itops@$($domain2).com"
    $smtpserver = "smtp.$($domainfqdn1)"

    Send-MailMessage -To $destination `
    -From "$($env:computername)@$($domain2).com" `
    -smtpServer $smtpserver `
    -Subject "Veeam Job created for $Name with default retention of 3 days." `
    -Body "A VMware guest virtual machine was found with no backup job. `n
    A job was created with the default backup retention on $env:Computername.  
    `n
    Please update the VMware tags to change the retention period. 
    `n
    This Message is being generated from $env:computername with function $($MyInvocation.MyCommand)
    "

}

function Invoke-ESGVeeamJobs ()
{
    <#
    .SYNOPSIS
    Connects to VMWare Vsphere through PowerShell and
    creates backup jobs in Veeam.

    .DESCRIPTION
    Using PowerCLI and Veeam Powershell snapins, the function
    connects to VMWare, get a list of Virtual Machines,
    filters the VMs based on name and tag.  It then creates
    backup jobs in Veeam based on Vsphere tags on the VM.

    The intent of this function is be run through a system
    scheduled task.

    .PARAMETER None
    At the time of creation, there are no parameters for this function.

    .INPUTS
    None. You cannot pipe objects to Invoke-ESGVeeamJobs.

    .OUTPUTS
    System.String. If run interactively, this function will
    output logging details to the screen.

    .EXAMPLE
    C:\PS> Invoke-ESGVeeamJobs

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    .LINK
    Set-Item
    #>

    # Set the directory for logging
    $dir = "c:\batch\zabbix\veeambackups"
    set-location $dir

    Start-Transcript -Path .\log.log -Force
    Write-output "My directory is $dir"

    Connect-ESGVeeam

    # General variables that are dictacted by physical localtion
    $site = $env:COMPUTERNAME.substring(0,5)
    if ($site -eq "USBOI")
    {
        # Have to put in a bandaid due to legacy naming convention
        # The datacenter name can not be changed due to citrix is bound to the legacy name
        $site = "Involta"
    }
    Write-Output "loction is $Site"

    $backupserver = $env:COMPUTERNAME
    Write-Output "backupserver is $backupserver"

    # get the location in vmware (aka datacenter)
    $Datacenter = @()
    Get-VM -name $env:computername* | Get-View | ForEach-Object{
    $row = "" | Select-Object Name, Path
    $row.Name = $_.Name
    $current = Get-View $_.Parent
    $path = $_.Name
    do {
        $parent = $current
        if($parent.Name -ne "vm"){$path =  $parent.Name}
        $current = Get-View $current.Parent
    } while ($current.Parent -ne $null)
    $row.Path = $path
    $Datacenter += $row
    }
    # confirm we gathered the 'datacenter' object from vmware.
    if ($Datacenter)
    {
        Write-Output "Datacenter identified from child VM:  $Datacenter"
        # get all of the other virtual machines\guests in the datacenter object from vmware
        [System.Collections.ArrayList]$VMs = get-vm -Location $Datacenter.path |
            Where-Object {$_.powerstate -eq 'PoweredOn'} |
            Where-Object {$_.name -notlike "Template*"} |
            Where-Object {$_.name -notmatch "d[\d\d]"} |
            Where-Object {$_.name -notlike "*bkup*"} |
            Where-Object {$_.name -notlike "*test*"} |
            Where-Object {$_.name -notlike "*usboixenp*"} |
            Where-Object {$_.name -notlike "esgboi-*vm*"} |
            Where-Object {$_.name -notlike "*esx*"} 
        
        
        $VMStoRemove = $VMs | Where-Object {(Get-TagAssignment -Entity $_ | Select-Object -ExpandProperty Tag) -like "*NoBackup*"}

        $VMs.Remove($VMStoRemove)
        
        Write-Verbose "The following VM(s) (Count: $(($VMs | measure-object).count)) were found: `n $($VMs | Select-Object name)"


        # Loop through the virtual machines, starting powershell jobs up to the maximum concurrent
        $VMs = $VMs | Sort-Object name
        foreach($virtmachine in $VMs)
        {
            # set the variables we use later in the script.
            $VMName = $virtmachine.name
            $shortname = (($VMName).split(' '))[0]
            $jobtest = Get-VBRJob -Name $shortname -erroraction silentlycontinue
            if ($jobtest)
            {
                Write-Output "Job found for $shortname.  Running consistency check for retention settings."
                $tags = Get-TagAssignment $virtmachine
                $NoBackupTest = (($tags).tag.name | Where-Object {$_ -like "*NoBackup*"})
                If ($NoBackupTest)
                {}else{

                    Update-ESGJob -Name $shortname
                }
            }
            else
            {
                #create the job
                Write-Output "Job not found, creating new job for $shortname"
                Add-ESGJob -Name $shortname


            }
        }
    }
    else
    {
        write-output "Datacenter value missing"
    }

    Stop-Transcript
}

function Add-ESGJob
{
    [Cmdletbinding()]
    Param(

        [Parameter(Mandatory=$true,
        HelpMessage="Name of the VM")]
        [string]$Name

    )
<#
    .SYNOPSIS
    Adds a new job to the Veeam Backup server.

    .DESCRIPTION
    Adds a new job to the Veeam Backup server, setting the repository
    and retention through tags from VMware.  The application awareness
    settings are set based on the domain name of the Virtual Machine.

    The intent of this function is be called from other functions.

    .PARAMETER Name
    Name of the Virtual Machine aka Job.

    .INPUTS
    None. You cannot pipe objects to Invoke-ESGVeeamJobs.

    .OUTPUTS
    none.

    .EXAMPLE
    C:\PS> Add-ESGJob -Name <Virtual Machine Name>

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    #>
    
    #Variables
    $fqdn1 = Get-Content -Path .\domainfqdn1.txt
    $fqdn2 = Get-Content -Path .\domainfqdn2.txt
    $domainshort1 = Get-Content -Path .\domain1.txt
    $domainshort2 = Get-Content -Path .\domain2.txt
    $shortname = $Name


    Connect-ESGVeeam

    
    $site = $env:COMPUTERNAME.substring(0,5)
    if ($site -eq "USBOI")
    {
        # Have to put in a bandaid due to legacy naming convention
        # The datacenter name can not be changed due to citrix is bound to the legacy name
        $site = "Involta"
    }

    $virtmachine = Get-VM "$($Name)*" -erroraction Stop
    # get all of the tags associated with the machine
    $tags = Get-TagAssignment $virtmachine
    # create new objects based on the tags that match the variables

    $backuppathserver = (($tags).tag.name | Where-Object {$_ -like "BackupPath*"}).split(":")[1]
    # Logic to validate the Backup tag was found in vmware
    
    $Altertnate = ($tags).tag.name | Where-Object {$_ -like "*BackupLocation2*"}

    if ($Altertnate)
    {
        $folder = "backups2"
    }
    else
    {
        $folder = "backups"
    }

    if ($backuppathserver)
    {

    }
    else
    {
        Write-Output "BackupPath tag not set in vmware for $shortname"
        if ($site -eq 'Involta')
        {
            #this needs to change per site....
            
            $backupserverarray = "eccosan01","eccosan02"
            $Backuppathserver = Get-Random -inputobject $backupserverarray
        }else{
            $Backuppathserver = "$($Site)bkupp01"
        }
        Write-Output "Setting Backup Server Tag for $shortname"
        $virtmachine | New-TagAssignment "BackupPath:$Backuppathserver"
    }

    $backuppath = "\\$($backuppathserver)\$($folder)\Veeam"

    $retention = (($tags).tag.name | Where-Object {$_ -like "VeeamZip*"}).split(":")[1]
    If ($retention)
    {
        Switch ($retention){
            "In6Months" {$retention = "180"}
            "In3Months" {$retention = "90"}
            "In2Months" {$retention = "60"}
            "In1Month" {$retention = "30"}
            "TomorrowNight" {$retention = "2"}
            "In3Days" {$retention = "3"}
            "Never" {$retention = "9999"}
            "In2Weeks" {$retention = "14"}
            "In1Week" {$retention = "7"}
            "In1Year" {$retention = "365"}
            "NoBackup" {$retention = $null}
            "Default" {$retention = "3"}
        }
    }
    else
    {
        # since no one set a retention tag on this server or we did not find a match, we will default it to 3 days
        Write-Output "Retention tag not set in vmware for $shortname.  Setting default retention of 3 days."
        $retention = "3"
        Write-Output "Setting Retention tag in vmware for $shortname"
        $virtmachine | New-TagAssignment "VeeamZip:In3Days"
        $NoRetentionFound = $True
    }

    Try
    {
        # validate that the backup repository is defined in Veeam.  If not, create it.
        If (Get-VBRBackupRepository -Name $backuppathserver)
        {
            $repository = Get-VBRBackupRepository -Name $backuppathserver
        }
        else
        {
            Write-Output "Repository for backup missing, creating Backup Repository"
            Add-VBRBackupRepository -Name $backuppathserver -Credentials (Get-VBRCredentials -Name $User) -Folder $backuppath -Type CifsShare -LimitConcurrentJobs -MaxConcurrentJobs 6 -ErrorAction Stop
            Start-Sleep 10
            $repository = Get-VBRBackupRepository -Name $backuppathserver
        }
        # get the VM from Veeam's perspective
        $VM = Find-VBRViEntity -Name $VMName
        # get the encryption key
        $enc = Get-VBREncryptionKey -Description encryption20190121
        # JOB - create the job
        Write-Host "Creating Backup Job $shortname" -foregroundcolor green
        Add-VBRViBackupJob -Name $shortname -Entity $VM -BackupRepository $repository | out-null

        # SCHEDULE - update the job with a schedule.  Randomly select a time to create the job.
        $BackupTimeArray = '18:00','19:00','20:00','21:00','22:00','23:00','01:00','02:00','03:00','04:00','05:00'
        $backuptime = Get-Random -inputobject $backuptimearray
        Write-Output "setting backup time:  $backuptime"
        Start-sleep 2
        Write-Output "Creating backup schedule......"
        Get-VBRJob -Name $shortname | Set-VBRJobSchedule -Daily -At $backuptime -DailyKind Everyday -Verbose | Enable-VBRJobSchedule

        # RETENTION - get the Veeam Job Options and set the retention
        $JobOptions = $shortname | Get-VBRJobOptions
        $JobOptions.BackupStorageOptions.RetainCycles = $retention
        Write-Output "Setting retention limit at:  $retention"
        Set-VBRJobOptions -Job $shortname -Options $JobOptions -Verbose
        # set the retain days value and disable synthetic fulls.
        Get-VBRJob -Name $shortname | Set-VBRJobAdvancedOptions -RetainDays $retention -TransformFullToSyntethic $false -Verbose
        Get-VBRJob -Name $shortname | Set-VBRJobAdvancedStorageOptions -EnableEncryption $true -EncryptionKey $enc


        # If windows, update vss settings (based on domain name)
        If ($virtmachine.guest -like "*Win*")
        {
            # set the credential based on the defined domain names
            If ($virtmachine.guest.hostname -like "*$($domain2)*")
            {
                $User2 = Get-Content -Path Get-Content .\account2.txt
                $VeeamAppCred = Get-VBRCredentials -Name $User2
            }
            elseif ($virtmachine.guest.hostname -like "*$($domainfqdn1)*")
            {
                $VeeamAppCred = Get-VBRCredentials -Name $User
            }
            else
            {
                return
            }
            If ($VeeamAppCred)
            {
                $Job = Get-VBRJob -Name $shortname
                $job | Enable-VBRJobVSSIntegration
                Set-VBRJobVssOptions -Job $Job -Credentials $VeeamAppCred
            }
        }
        else
        {
            # disable application aware processing....
            If ((Get-VBRJob -name $shortname | Get-VBRJobVSSOptions).enabled -eq "True")
            {
                get-vbrjob -Name $shortname | Disable-VBRJobVSSIntegration
            }
        }
        # if there was no retention set, we need to email the staff.
        If ($NoRetentionFound)
        {
            Send-ESGVeeamEmail -Name $shortname
        }
    }
    Catch
    {
        $timestamp = Get-Date -Format o | ForEach-Object {$_ -replace ":", "."}
        $error[0] | out-file ".\logs\$($shortname)_$($timestamp).log"
        "Failed to create job: $($shortname)"| Out-File .\logs\jobcreatefail.log -Append
        Start-Sleep 5
    }
}

function Update-ESGJob
{
    [Cmdletbinding()]
    Param(

        [Parameter(Mandatory=$true,
        HelpMessage="Name of the VM")]
        [string]$Name

    )
<#
    .SYNOPSIS
    Updates an existing job on the Veeam Backup server.

    .DESCRIPTION
    Updates an existing job on the Veeam Backup server, checking the 
    retention limit tag and comparing to the retention of the 
    existing job.

    The intent of this function is be called from other functions.

    .PARAMETER Name
    Name of the Virtual Machine aka Job.

    .INPUTS
    None. You cannot pipe objects to Invoke-ESGVeeamJobs.

    .OUTPUTS
    none.

    .EXAMPLE
    C:\PS> Update-ESGJob -Name <Virtual Machine Name>

    .LINK
    \\$($domainfqdn1)\global\servers$\Server_Files\C\batch\zabbix\VeeamBackups

    #>
    If ($creds -or $veeamcreds)
    {
    }
    else
    {
        Connect-ESGVeeam
    }

    # get the retention value from from the tag in vmware.
    try
    {
        $virtmachine = Get-VM "$($Name)*" -erroraction Stop
        $shortname = $Name
        $tags = Get-TagAssignment $virtmachine
        $retention = (($tags).tag.name | Where-Object {$_ -like "VeeamZip*"}).split(":")[1]
    }
    catch
    {
        return
    }

    # check the retention value has been set and convert from VeeamZip values, if not....
    If ($retention)
    {
        Switch ($retention){
            "In6Months" {$retention = "180"}
            "In3Months" {$retention = "90"}
            "In2Months" {$retention = "60"}
            "In1Month" {$retention = "30"}
            "TomorrowNight" {$retention = "2"}
            "In3Days" {$retention = "3"}
            "Never" {$retention = "9999"}
            "In2Weeks" {$retention = "14"}
            "In1Week" {$retention = "7"}
            "In1Year" {$retention = "365"}
            "NoBackup" {$retention = $null}
            "Default" {$retention = "3"}
        }
    }
    else
    {
        # The retention should have been set, but in case it was removed from the VMware guest object....
        $retention = "3"
    }

    # Retention validation
    if ($retention -ne "NoBackup")
    {
        #double check retention has not changed
        $job1 = get-vbrjob -Name $shortname
        $retaincycles = $job1.Options.options.rootnode.RetainCycles
        $retaindays = $job1.Options.options.rootnode.RetainDays
        If (($retention -ne $retaincycles) -or ($retention -ne $retaindays))
        {
            Write-Output "Retention has changed - updating job."
            $JobOptions = $shortname | Get-VBRJobOptions
            $JobOptions.BackupStorageOptions.RetainCycles = $retention
            Set-VBRJobOptions -Job $shortname -Options $JobOptions
            Get-VBRJob -Name $shortname | Set-VBRJobAdvancedOptions -RetainDays $retention
        }
        else
        {
            Write-Output "Retention settings are valid."
        }
    }
    
    # Encryption enabled check
    Write-Verbose "Checking Encryption status for $Shortname"
    $vbrjob = get-vbrjob -name $shortname
    # dot sourcing the objecting
    $EncryptionEnabled = ($vbrjob).options.backupstorageoptions.storageencryptionenabled
    Write-Verbose "Encryption status:  $($EncryptionEnabled)"
    If ($EncryptionEnabled -eq $True)
    {}
    else
    {
        # get the encryption key
        Write-Verbose "Getting Encryption key"
        $enc = Get-VBREncryptionKey -Description encryption20190121
        # change the job variable.
        $vbrjob| Set-VBRJobAdvancedStorageOptions -EnableEncryption $true -EncryptionKey $enc -Verbose
    }

}


