$hostname = hostname
$month = (get-date).AddMonths(-1).ToString("MM")
$lastmonthfull = (get-date).AddMonths(-1).ToString("Y")
$year = (get-date).AddMonths(-1).Year
$DDMMYYY = Get-Date -format dd.MM.yyyy
$smtpServer = "mail.xy.com" # SMTP Server
$smtpFrom = "xy@xy.com" # Sender
$smtpTo = "xy@xy.com" # Empfaenger des Reportmails
$messageSubject = "ILV 401703 SMS FAX $lastmonthfull"
$securitycheck = "false"
$message = $null
$UnknownDomains = @()
$Zuweisungsgruppe = "OPE-INS-SCI" #SNOW Gruppe

# Destination folder
$sourcefolder = "D:\Temp\SCRIPTS\Log_Analyzer"
$sharefolder = "\\SERVER\Source"
$destinationFolder = "\\SERVER\Source\Import"
$ReportingFolder = "\\SERVER\Source\Verrechnungsfiles"

# Logfunktion 
$logfile = "{0}\{1}{2}{3}" -f $sharefolder, "\logs\logfile_", (Get-Date -Format "yyyyMMdd"), ".txt"
$logfilecheck = test-path $logfile

if ($logfilecheck -ne "true") {
new-item $logfile -itemtype file }

Function write-log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [String]
    $Message
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    Add-Content -Path $logfile -Value $Line
	write-host $line -foregroundcolor green
}

# Stammdaten - CSV einlesen

$Stammdaten = @{}
$Stammdaten = Import-Csv -path "$sourcefolder\Stammdaten.csv" -Delimiter ";"
#$Stammdaten | Add-Member -Name Menge -value 0 -MemberType NoteProperty
write-log -message "Stammdaten.csv wurde eingelesen"
$Stammdaten = [Collections.Generic.List[Object]]$Stammdaten
$Countingtable = Import-Csv -path "$sourcefolder\Stammdaten.csv" -Delimiter ";" | select Innenauftrag, Kostenstelle, Kundenauftrag, Auftragsposition -unique
$Countingtable | Add-Member -MemberType NoteProperty -Name Punkte -value 0

$Nichtverrechenbar = @{}

# Check if the script has already been executed this month
if ($securitycheck -eq "true") {
		$pathcheck = test-path "\\SAX10149\Source\Check\Check_$year$month.txt"
			if ($pathcheck -eq "true") {
			write-log -message "The script has already been executed this month. If you want to overrule this check, change the value of the ""securitycheck"" variable in the script settings to anything else than ""true""." -level "ERROR"
			Write-EventLog -LogName "Application" -Source "Application Error" -EventID 1 -Message "The eCall Verrechnungsscript has already been executed this month. If you want to overrule this check, change the value of the ""securitycheck"" variable in the script settings to anything else than ""true""." -EntryType Error
			throw "The script has already been executed this month. If you want to overrule this check, change the value of the ""securitycheck"" variable in the script settings to anything else than ""true""."
			} 
	new-item "\\SAX10149\Source\Check\Check_$year$month.txt" -itemtype file
	}
	
# Credentials
$email    = ""
$username = ""
$password = ""
 
# File extensions to download
$extensions = "zip"
 
# load the assembly
Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"

#Funktion aus System.IO.Compression.ZipFile laden
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
	param([string]$zipfile, [string]$outpath)

	[System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

# Create Exchange Service object
$s = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2016)
$s.Credentials = New-Object Net.NetworkCredential($username, $password)
$s.TraceEnabled = $true
write-log -message "Trying AutoDiscover... "
$s.AutodiscoverUrl($email, {$true})
 
if(!$s.Url) {
	Write-Log -message "AutoDiscover failed" -level "ERROR"
	Write-Error "AutoDiscover failed"
	return;
} else {
	write-log -message "AutoDiscover succeeded - $($s.Url)"
}
 
# Create destination folder
$destinationFolder = "{0}\{1}" -f $destinationFolder, (Get-Date -Format "yyyyMMdd HHmmss")
mkdir $destinationFolder | Out-Null
 
# get a handle to the inbox
$inbox = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($s,[Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox)
 
#create a property set (to let us access the body & other details not available from the FindItems call)
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$psPropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text;
 
# Find the items
$inc = 0;
$maxRepeat = 50;
do {
	$maxRepeat -= 1;
 
	write-log -message "Searching for items in mailbox... "
	$items = $inbox.FindItems(100)
	write-log -message "found $($items.items.Count) items in the inbox"
 
	foreach ($item in $items.Items)
	{
		# Create mail folder
		$inc += 1
		$mailFolder = "{0}\{1}" -f $destinationFolder, $inc;
		mkdir $mailFolder | Out-Null
 
		# load the property set to allow us to get to the body
		try {
			$item.load($psPropertySet)
			write-log -message ("$inc - $($item.Subject)")
 
			# save the metadata to a file
			$item | Export-Clixml ("{0}\metadata.xml" -f $mailFolder)
 
			# save all attachments
			foreach($attachment in $item.Attachments) {
				if(($attachment.Name -split "\." | select -last 1) -in $extensions) {
					$fileName = ("{0}\{1}" -f $mailFolder, $attachment.Name) -replace "/",""
					write-log -message "File has been downloaded: $filename - $([Math]::Round($attachment.Size / 1024))KB"
					$attachment.Load($fileName)
					
					#Entpacken der Files		
					 Try {
					 write-log -message "Unzipping $filename"
					 Unzip $filename $mailfolder 
					 }
					 catch [Exception] {
					 Write-Log -message "Unable to extract item: $filename" -level "ERROR"
					 Write-Error "Unable to extract item: $filename"
		}
				}
			}
 
			# delete the mail item
			$item.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::SoftDelete, $true)
			write-log -message "Moving processed items to the mailbox dumpster"
		} catch [Exception] {
			Write-Log -message "Unable to load item: $($_)" -level "ERROR"
			Write-Error "Unable to load item: $($_)"
		}	
	
	# CSV Import
	
	$searchinfolder = Get-ChildItem $mailFolder *.txt
		if ($searchinfolder.name -like "720672_*_Out-LogFile.txt")
		{
		write-log -message "Einlesen von CSV für OUT-File von Account 720672 wurde gestartet"
		$720672_Out_Logfile = @()
		$720672_Out_Logfile | Add-Member -MemberType NoteProperty -Name Punkte -value 0		
		$720672_Out_LogFile = Import-Csv `
								-path "$mailfolder\720672_*_Out-LogFile.txt" `
								-Delimiter ";"`
								-header "Referenz","Startdatum","Meldung","Resultatcode","Absender","Empfaengernummer","ExterneID","Punkte","Empfaengername" `
								| Select @{Name="Referenz";Expression={[decimal]$_.Referenz}}, @{Name="Startdatum";Expression={[datetime]$_.Startdatum}}, Meldung, `
								@{Name="Resultatcode";Expression={[decimal]$_.Resultatcode}}, Absender, @{Name="Empfaengernummer";Expression={[decimal]$_.Empfaengernummer}}, `
								ExterneID , @{Name="Punkte";Expression={[decimal]$_.Punkte}}, Empfaengername
								
								
		write-log -message "CSV für OUT-File von Account 720672 wurde eingelesen"
		}	
		
		if ($searchinfolder.name -like "720672_*_In-LogFile.txt")
		{
		write-log -message "Einlesen von CSV für IN-File von Account 720672 wurde gestartet"
		$720672_In_Logfile = @()
		$720672_In_Logfile | Add-Member -MemberType NoteProperty -Name Punkte -value 0
		$720672_In_LogFile = Import-Csv `
								-path "$mailfolder\720672_*_In-LogFile.txt" `
								-Delimiter ";"`
								-header "Referenz","Startdatum","GesendeteMeldung","EmpfangeneMeldung","Resultatcode","Empfaengernummer","eCallNummer","AntwortAdresse","AntwortInfo","ExterneID","Punkte" `
								| Select @{Name="Referenz";Expression={[decimal]$_.Referenz}}, @{Name="Startdatum";Expression={[datetime]$_.Startdatum}}, GesendeteMeldung, `
								EmpfangeneMeldung, @{Name="Resultatcode";Expression={[decimal]$_.Resultatcode}}, @{Name="Empfaengernummer";Expression={[decimal]$_.Empfaengernummer}}, `
								@{Name="eCallNummer";Expression={[decimal]$_.ecallNummer}} , Antwortadresse, Antwortinfo, ExterneID, @{Name="Punkte";Expression={[decimal]$_.Punkte}}	
								
		write-log -message "CSV für IN-File von Account 720672 wurde eingelesen"
		}
		
		if ($searchinfolder.name -like "79694_*_Out-LogFile.txt")
		{
		write-log -message "Einlesen von CSV für OUT-File von Account 79694 wurde gestartet"
		$79694_Out_LogFile = @()
		$79694_Out_LogFile | Add-Member -MemberType NoteProperty -Name Punkte -value 0
		$79694_Out_LogFile = Import-Csv `
								-path "$mailfolder\79694_*_Out-LogFile.txt" `
								-Delimiter ";"`
								-header "Referenz","Startdatum","Meldung","Resultatcode","Absender","Empfaengernummer","ExterneID","Punkte","Empfaengername" `
								| Select @{Name="Referenz";Expression={[decimal]$_.Referenz}}, @{Name="Startdatum";Expression={[datetime]$_.Startdatum}}, Meldung, `
								@{Name="Resultatcode";Expression={[decimal]$_.Resultatcode}}, Absender, @{Name="Empfaengernummer";Expression={[decimal]$_.Empfaengernummer}}, `
								ExterneID , @{Name="Punkte";Expression={[decimal]$_.Punkte}}, Empfaengername
								
								
		write-log -message "CSV für OUT-File von Account 79694 wurde eingelesen"
		}
		
		if ($searchinfolder.name -like "79694_*_In-LogFile.txt")
		{
		write-log -message "Einlesen von CSV für IN-File von Account 79694 wurde gestartet"
		$79694_In_LogFile = @()
		$79694_In_LogFile | Add-Member -MemberType NoteProperty -Name Punkte -value 0
		$79694_In_LogFile = Import-Csv `
								-path "$mailfolder\79694_*_In-LogFile.txt" `
								-Delimiter ";"`
								-header "Referenz","Startdatum","GesendeteMeldung","EmpfangeneMeldung","Resultatcode","Empfaengernummer","eCallNummer","AntwortAdresse","AntwortInfo","ExterneID","Punkte" `
								| Select @{Name="Referenz";Expression={[decimal]$_.Referenz}}, @{Name="Startdatum";Expression={[datetime]$_.Startdatum}}, GesendeteMeldung, `
								EmpfangeneMeldung, @{Name="Resultatcode";Expression={[decimal]$_.Resultatcode}}, @{Name="Empfaengernummer";Expression={[decimal]$_.Empfaengernummer}}, `
								@{Name="eCallNummer";Expression={[decimal]$_.ecallNummer}} , Antwortadresse, Antwortinfo, ExterneID, @{Name="Punkte";Expression={[decimal]$_.Punkte}}	
																
		write-log -message "CSV für IN-File von Account 79694 wurde eingelesen"
		}
		}
} while($items.MoreAvailable -and $maxRepeat -ge 0)

# Import Leistungsarten

$Leistungsarten = Import-Csv -path "$sourcefolder\Leistungsarten.csv" -Delimiter ";"
write-log -message "Leistungsarten.csv wurde eingelesen"

#Nicht gefundene Domains ermitteln
<# $720672_Absender = $720672_Out_LogFile | select Absender -unique | where-object {$_.Absender -ne ""}
foreach ($720672_Absender_Unique in $720672_Absender) {
	if ($Stammdaten_720672.Domain -notcontains $720672_Absender_Unique.Absender) {
			write-log -message "Domain nicht verrechenbar ($720672_Absender_Unique.Absender wurde nicht in den Stammdaten gefunden)"
			$messageBody += "Fehler! Die folgende Domain konnte keiner Verrechnungsnummer zugewiesen werden: $720672_Absender_Unique.Absender"
	}
}

	
$unknowndomains79694 = @()
foreach ($entry in $79694_Out_LogFile)
	{
	$Antwortdomain79694 = ($entry.Absender -replace '\s','' -split '@')[1]
		if ($Stammdaten_79694.Domain -contains $Antwortdomain79694)
		{write-host $Antwortdomain79694}
		elseif ($Stammdaten_79694.Domain -contains $entry.ExterneID)
		{write-host $entry.externeID}
		elseif ($entry.ExterneID -like "eCallURL*")
		{write-host $entry.ExterneID}
		else {
		$unknowndomains79694 += $Antwortdomain79694
		$unknowndomainsunique79694 = $unknowndomains79694 | get-unique
		$unknowndomainfound79694 = $true
		}
	}
		if ($unknowndomainfound79694 -eq $true) {
		#INFO an Mailempfänger! - Logeintrag 
		write-log -message "Domain nicht verrechenbar ($unknowndomainsunique79694 wurde nicht in den Stammdaten gefunden)"
		$messageBody += "Fehler! Die folgende Domain konnte keiner Verrechnungsnummer zugewiesen werden: $unknowndomainsunique79694"
		} #>


$720672_Absender = $720672_Out_LogFile | select Absender -unique | where-object {$_.Absender -ne ""}
$720672_Antwortadresse = $720672_In_LogFile | select AntwortAdresse -unique | where-object {$_.AntwortAdresse -ne ""}

$79694_Absender = $79694_Out_LogFile | select Absender -unique | where-object {$_.Absender -ne ""}
$79694_Domain_Out =  foreach ($item in $79694_Absender.Absender) {($item -replace '\s','' -split '@')[1]}
$79694_Domain_Out_Unique = $79694_Domain_Out | select -unique

$79694_Antwortadresse = $79694_In_LogFile | select Antwortadresse -unique #| where-object {$_.Antwortadresse -ne ""} DEAKTIVIERT, weil sonst unzuweisbare (leere) Adressen nicht abgerufen werden können.
$79694_Domain_In =  foreach ($item in $79694_Antwortadresse.Antwortadresse) {($item -replace '\s','' -split '@')[1]}
$79694_Domain_In_Unique = $79694_Domain_In | select -unique
$79694_Domain_In_Unique += "" #Leere Domain einfügen, damit diese auch geprüft wird.

#Start Absender und AntwortAdresse

foreach ($720672_Absender_Unique_Out in $720672_Absender)
	{
	write-host $720672_Absender_Unique_Out.Absender
	
	$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $720672_Absender_Unique_Out.Absender} )
	
	if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
	
	$Punkte = ""		
	$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_Out_LogFile | where {$_.Absender -eq $720672_Absender_Unique_Out.Absender}
		).Punkte
	)
	$Kostenstelle = $Stammdaten[$Index].Kostenstelle
	$Innenauftrag = $Stammdaten[$Index].Innenauftrag
	$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
	$Auftragsposition = $Stammdaten[$Index].Auftragsposition
	
	write-host $Innenauftrag
	write-host $Kostenstelle
	write-host $Kundenauftrag
	write-host $Auftragsposition
	$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
	write-host $Punkte
	}

foreach ($720672_Antwortadresse_Unique_In in $720672_Antwortadresse)
	{
	write-host $720672_Antwortadresse_Unique_In.AntwortAdresse
	
	$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $720672_Antwortadresse_Unique_In.Antwortadresse} )
	
	if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
	
	$Punkte = ""
	$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_In_LogFile | where {$_.Antwortadresse -eq $720672_Antwortadresse_Unique_In.AntwortAdresse}
		).Punkte
	)
	
	$Kostenstelle = $Stammdaten[$Index].Kostenstelle
	$Innenauftrag = $Stammdaten[$Index].Innenauftrag
	$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
	$Auftragsposition = $Stammdaten[$Index].Auftragsposition
	
	
	write-host $Innenauftrag
	write-host $Kostenstelle
	write-host $Kundenauftrag
	write-host $Auftragsposition
	$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
	write-host $Punkte
	}	
	
foreach ($79694_Domain_Out_SingleItem in $79694_Domain_Out_Unique)
	{
	write-host $79694_Domain_Out_SingleItem
	
	$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $79694_Domain_Out_SingleItem} )
	
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
	
		$Punkte = ""	
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$79694_Out_LogFile | where {$_.Absender -like "*$79694_Domain_Out_SingleItem*"}
		).Punkte
		)
	
	$Kostenstelle = $Stammdaten[$Index].Kostenstelle
	$Innenauftrag = $Stammdaten[$Index].Innenauftrag
	$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
	$Auftragsposition = $Stammdaten[$Index].Auftragsposition
	
	write-host $Innenauftrag
	write-host $Kostenstelle
	write-host $Kundenauftrag
	write-host $Auftragsposition
	$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
	write-host $Punkte
	}
		
foreach ($79694_Domain_In_SingleItem in $79694_Domain_In_Unique)
	{
	write-host $79694_Domain_In_SingleItem
	
	$Index = $Stammdaten.findindex( {$args[0].Antwortadresse -eq $79694_Domain_Out_SingleItem} )
		
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
		
		if 
			($79694_Domain_In_SingleItem -ne "") {
			$Punkte = ""
			$Punkte = [Linq.Enumerable]::Sum(
			[decimal[]] (
			$79694_In_LogFile | where {$_.Antwortadresse -like "*$79694_Domain_In_SingleItem*"}
			).Punkte
			)
			$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
			
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		#$Stammdaten[$Index].Punkte = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
			
		}
		else 
		{
			write-host $79694_Domain_In_SingleItem
			$Punkte = ""
			$Punkte = [Linq.Enumerable]::Sum(
			[decimal[]] (
			$79694_In_LogFile | where {$_.Antwortadresse -eq ""}
			).Punkte
			)
			$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )		
			
			$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
			
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		#$Stammdaten[$Index].Punkte = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
		}
	}
		
#Start ExterneID Verrechnung

$720672_ExterneID_Out = $720672_Out_LogFile | select ExterneID -unique | where-object {$_.ExterneID -ne "" -and $_.ExterneID -notlike "*ecallURL*"}
$720672_ExterneID_In = $720672_In_LogFile | select ExterneID -unique | where-object {$_.ExterneID -ne "" -and $_.ExterneID -notlike "*ecallURL*"}

$79694_ExterneID_Out = $79694_Out_LogFile | select ExterneID -unique | where-object {$_.ExterneID -ne "" -and $_.ExterneID -notlike "*ecallURL*"}
$79694_ExterneID_In = $79694_In_LogFile | select ExterneID -unique | where-object {$_.ExterneID -ne "" -and $_.ExterneID -notlike "*ecallURL*"}

foreach ($720672_ExterneID_Unique_Out in $720672_ExterneID_Out)
	{
		write-host $720672_ExterneID_Unique_Out.ExterneID -foregroundcolor green
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $720672_ExterneID_Unique_Out.ExterneID} )
		
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
		
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_Out_LogFile | where {$_.ExterneID -eq $720672_ExterneID_Unique_Out.ExterneID}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
		}
		
#eCall URL Punkte addieren 720672_Out_LogFile		
		write-host "eCallURL Addition" -foregroundcolor yellow
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "eCallURL"} )
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_Out_LogFile | where {$_.ExterneID -like "eCallURL*"}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		write-host $Punkte
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge

foreach ($720672_ExterneID_Unique_In in $720672_ExterneID_In)
		{
		write-host $720672_ExterneID_Unique_In.ExterneID -foregroundcolor green
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $720672_ExterneID_Unique_In.ExterneID} )
		
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
		
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_In_LogFile | where {$_.ExterneID -eq $720672_ExterneID_Unique_In.ExterneID}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
		}

		#eCall URL Punkte addieren 720672_In_LogFile	
		write-host "eCallURL Addition" -foregroundcolor yellow
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "eCallURL"} )
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] @(
		$720672_In_LogFile | where {$_.ExterneID -like "eCallURL*"}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte		
	
foreach ($79694_ExterneID_Unique_Out in $79694_ExterneID_Out)
	{
		write-host $79694_ExterneID_Unique_Out.ExterneID -foregroundcolor green
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $79694_ExterneID_Unique_Out.ExterneID} )
		
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
		
		$Punkte = ""		
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$79694_Out_LogFile | where {$_.ExterneID -eq $79694_ExterneID_Unique_Out.ExterneID}
		).Punkte
		)

		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
		}

	
		#eCall URL Punkte addieren 79694_Out_LogFile	
		write-host "eCallURL Addition" -foregroundcolor yellow
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "eCallURL"} )
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] @(
		$79694_Out_LogFile | where {$_.ExterneID -like "eCallURL*"}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte		
	
foreach ($79694_ExterneID_Unique_In in $79694_ExterneID_In)
	{
		write-host $79694_ExterneID_Unique_In.ExterneID -foregroundcolor green
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq $79694_ExterneID_Unique_In.ExterneID} )
		
		if ($Index -eq "-1")
		{
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )
		}
		
		$Punkte = ""		
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$79694_In_LogFile | where {$_.ExterneID -eq $79694_ExterneID_Unique_In.ExterneID}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte
		}
	
		#eCall URL Punkte addieren 79694_In_LogFile	
		write-host "eCallURL Addition" -foregroundcolor yellow
		
		$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "eCallURL"} )
		$Punkte = ""
		$Punkte = [Linq.Enumerable]::Sum(
		[decimal[]] @(
		$79694_In_LogFile | where {$_.ExterneID -like "eCallURL*"}
		).Punkte
		)
		
		$Kostenstelle = $Stammdaten[$Index].Kostenstelle
		$Innenauftrag = $Stammdaten[$Index].Innenauftrag
		$Kundenauftrag = $Stammdaten[$Index].Kundenauftrag
		$Auftragsposition = $Stammdaten[$Index].Auftragsposition
		
		write-host $Innenauftrag
		write-host $Kostenstelle
		write-host $Kundenauftrag
		write-host $Auftragsposition
		$Stammdaten[$Index].Menge = $Punkte + $Stammdaten[$Index].Menge
		write-host $Punkte		
	
#Gesamtcheck Punkte

		$Gesamtpunkte720672Out = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_Out_LogFile
		).Punkte
		)		

		$Gesamtpunkte720672In = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$720672_In_LogFile
		).Punkte
		)		

		$Gesamtpunkte79694In = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$79694_In_LogFile
		).Punkte
		)		
		
		$Gesamtpunkte79694Out = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$79694_Out_LogFile
		).Punkte
		)	
		
$Gesamtpunkte = $Gesamtpunkte720672Out + $Gesamtpunkte720672In + $Gesamtpunkte79694In + $Gesamtpunkte79694Out
$Punktzahl720672 = $Gesamtpunkte720672Out + $Gesamtpunkte720672In
$Punktezahl79694 = $Gesamtpunkte79694Out + $Gesamtpunkte79694In

write-host $Gesamtpunkte -foregroundcolor yellow
		
		
#Vergleich mit Script-Punkten
		
		$Scriptpunkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$Stammdaten
		).Menge
		)	
		
write-host $Scriptpunkte -foregroundcolor yellow

$stammdaten | ft

$Punktedifferenz = $Gesamtpunkte - 	$Scriptpunkte

write-host "Punktedifferenz: $Punktedifferenz" -foregroundcolor yellow
		
#Differenz an YourCompany zuweisen

$Index = $Stammdaten.findindex( {$args[0].Buchungstext -eq "YourCompany.ch"} )		
$Stammdaten[$Index].Menge = $Punktedifferenz + $Stammdaten[$Index].Menge

		$Scriptpunkte = [Linq.Enumerable]::Sum(
		[decimal[]] (
		$Stammdaten
		).Menge
		)	

$PunktedifferenzNEU = $Gesamtpunkte - 	$Scriptpunkte

write-host "Punktedifferenz NEU: $PunktedifferenzNEU" -foregroundcolor green

# Verrechnungs - CSV "Metadaten" einfügen
new-item "$reportingfolder\ILV_401703_SMS_FAX_$year$month.csv" -itemtype file -force -value "SKST;4017 Communication Services
Modul;401703 SMS/FAX
Erstellung;$DDMMYYY
Leistungsart;Leistungsgroessen
$($Leistungsarten.Leistungsart[0]);$($Leistungsarten.Bezeichnung[0])
$($Leistungsarten.Leistungsart[1]);$($Leistungsarten.Bezeichnung[1])
$($Leistungsarten.Leistungsart[2]);$($Leistungsarten.Bezeichnung[2])
$($Leistungsarten.Leistungsart[3]);$($Leistungsarten.Bezeichnung[3])
"

$Stammdaten | Export-Csv "$reportingfolder\Temp\Stammdaten_$year$month.csv" ";" -NoTypeInformation
$Stammdaten_Werte = get-content "$reportingfolder\Temp\Stammdaten_$year$month.csv"

# Verrechnungs - CSV erstellen
add-content -Path "$reportingfolder\ILV_401703_SMS_FAX_$year$month.csv" -Value $Stammdaten_Werte

# Adding Script-Metadata to MessageBody
$messagebody = 
"<h1 style='color: #5e9ca0;'>ILV 401703 Periode <span style='color: #2b2301;'>$lastmonthfull</span></h1>
<h2 style='color: #2e6c80;'>Quick-Infos:</h2>
<table style='height: 105px; width: 606px;' border='2'>
<tbody>
<tr>
<td style='width: 265px;'><strong>Auslösedatum</strong></td>
<td style='width: 337px;'>$DDMMYYY</td>
</tr>
<tr>
<td style='width: 265px;'><strong>Generierender Server</strong></td>
<td style='width: 337px;'>$hostname</td>
</tr>
<tr>
<td style='width: 265px;'><strong>Punktezahl Gesamt</strong></td>
<td style='width: 337px;'>$Gesamtpunkte</td>
</tr>
<tr>
<td style='width: 265px;'><strong>Punktezahl Account 720672</strong></td>
<td style='width: 337px;'>$Punktzahl720672</td>
</tr>
<tr>
<td style='width: 265px;'><strong>Punktezahl Account 79694</strong></td>
<td style='width: 337px;'>$Punktezahl79694</td>
</tr>
<tr>
<td style='width: 265px;'><strong>Probleme?</strong></td>
<td style='width: 337px;'>Bitte einen <a href='https://YourCompany.service-now.com/incident.do?sys_id=-1&amp;sysparm_query=active=true&amp;sysparm_stack=incident_list.do?sysparm_query=active=true'>Incident eröffnen</a> und der Zuweisungsgruppe $Zuweisungsgruppe zuweisen.</td>
</tr>
</tbody>
</table>
<h2 style='color: #2e6c80;'> </h2>"

#Sending Email
Send-MailMessage -To $smtpTo -From $smtpFrom -Subject $messageSubject -Body $messageBody -BodyAsHTML -SmtpServer $smtpServer -encoding UTF8 -attachments $logfile, "$reportingfolder\ILV_401703_SMS_FAX_$year$month.csv"