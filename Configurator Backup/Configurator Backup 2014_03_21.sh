#!/bin/bash

#New Configurator backup Script
#TSiemers 3-21-14
#Backup Configurator Data to an external device.  Log files created at within Jamf policy logs for computer 

: <<'END'
© 2014 Tyler Siemers. Sample scripts in this guide are not supported under any condition. The sample scripts are 
provided AS IS without warranty of any kind. I disclaim all implied warranties including, without limitation, any 
implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the 
use or performance of the sample scripts and documentation remains with you. In no event shall its authors, or 
anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever 
(including, without limitation, damages for loss of business profits, business interruption, loss of business 
information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation.
END

#####################################################################################
#
#				Script Global Variables

computerName=`jamf getComputerName | cut -d ">" -f2 | cut -d "<" -f1`
currentUser=`who | grep "console" | awk '{print $1}'`
file0=/Users/"$currentUser"/Library/Containers/com.apple.configurator/Data/Library/Application\ Support/com.apple.configurator/
file1=/Users/"$currentUser"/Library/Keychains
file2=/Users/"$currentUser"/Library/Containers/com.apple.configurator/Data/Library/Preferences/com.apple.configurator.plist
file3=/var/db/lockdown/
currentDateTime=`date +%a\ %b\ %d\ %l_%M%p`

#
#
#####################################################################################

# Zip files to tmp folder to evaluate size of zip to compare to external volume
# This is for future use if this process takes to long because of file sizes
# This would zip the files first to the tmp dir and then move the zip to the external
# only after comparing free space on the external volume to ensure it can fit.

#zip -r "/private/tmp/configSizeCheck.zip" "$file0" "$file1" "$file2" "$file3"

# Get the total size of files being copied in KiloBytes(KB)

filesKB=`du -c -k ${file0} ${file1} ${file2} ${file3} | grep "total" | awk '{print$1}'`

# Convert size of files from KB to GigaBytes(GB)

filesGB=`awk 'BEGIN{printf("%0.2f",('$filesKB')/'1024'/'1024')}'`

######################################################################################

# Prompt to ensure user has external source flash drive plugged in

	descrip=$(echo -e "Please plug in your flash drive where the Apple Configurator back up will be saved.")
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Configurator Back Up" -heading "Please ensure Flash Drive is inserted" -description "$descrip" -button1 "OK" -alignDescription left -timeout 30

######################################################################################

# AppleScript to grab all Volumes on the computer and present a list to end user via OSA
# Exclude the 'Macintosh HD' and 'Volumes' drives from being shown in the list
# Use the result as a variable to define the location to save the backup

extVolume=`su - "${currentUser}" -c '/usr/bin/osascript <<EndMigration
set x to true
repeat until x is false
	tell application "Finder"
		activate
		do shell script "find /Volumes/ -depth 1 ! -name \"Macintosh HD\" ! -name \"Volumes\" | cut -d \"/\" -f4"
		-- set _Result to the list items
		set _Result to the paragraphs of result
		if not _Result = {} then
			--stuff is selected
			set x to false
		else
			--no stuff is selected
			display dialog "Please Insert Flash Drive"
			set x to true
		end if
	end tell
end repeat

tell application "Finder"
	set theVolumeTemp to (choose from list _Result with prompt "Choose External Volume" without empty selection allowed)
	-- if user presses Cancel, close the dialog
	if theVolumeTemp is false then (display dialog "Please insert a flash drive and re-run")
	-- set theVolume to the actual path, e.g. /Volumes/Macintosh HD/
	set theVolume to "/Volumes/" & theVolumeTemp
end tell          
EndMigration'`

# Add a function to see if user canceled to exit right away (FUTURE USE)

######################################################################################

# Take external volume selected and get free space

extVolumeShortName=`echo $extVolume | cut -d "/" -f3`

volumeID=`diskutil list | grep "$extVolumeShortName" | awk '{print$6}'`

extVolumeFreeSpace=`diskutil info $volumeID | grep "Volume Free Space" | awk '{print$4}'`

echo External Volume free space is: $extVolumeFreeSpace

# Compare ext free space to size of files to be backed up

if (( $(echo "$filesGB < $extVolumeFreeSpace" | bc -l) )); then
	descrip=$(echo -e "Transferring $filesGB.GB to $extVolumeShortName\nDepending on the size of your back up this may take a while.\nPlease be patient and allow up to an 30mins for this to complete. ")
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Configurator Back Up" -heading "Configurator Back Up Started" -description "$descrip" -button1 "OK" -alignDescription left -timeout 30
	sleep 05
else
	descrip=$(echo -e "You do not have enough free space on your flash drive named: $extVolumeShortName \n Please insert a external drive that has $filesGB.GB free on it\nAnd re-run back up from Self Service")
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Configurator Back Up" -heading "Configurator Back Up Failure!" -description "$descrip" -button1 "OK" -alignDescription left -timeout 30
		exit 1
	echo "BACKUP FAILED; NOT ENOUGH SPACE ON EXTERNAL FLASH DRIVE"
fi

######################################################################################

# Make a new folder on the selected external volume to save backup to

mkdir -p "$extVolume/Configurator/Back Ups/$computerName/$currentDateTime"

# Create variable for ext volume path

backupPath="$extVolume/Configurator/Back Ups/$computerName/$currentDateTime"

echo $backupPath

######################################################################################

# Copy files to external volume as .zip format as a zip named "Configurator Back Up"

zip -r "$backupPath/$currentDateTime" "$file0" "$file1" "$file2" "$file3"
echo "FILES BEING ZIPPED"

######################################################################################
######################################################################################

# Ensure back up folder was created inside external drive and display success/failure message to end user

#complete path to file

completePath="$extVolume/Configurator/Back Ups/$computerName/$currentDateTime/$currentDateTime.zip"

if [[ -f $completePath ]]; then
	descrip=$(echo -e "Back up was saved to your flash drive named $extVolumeShortName\nIn a folder called Configurator/$computerName/$currentDateTime\n")
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Configurator Back Up" -heading "Configurator Back Up Complete!" -description "$descrip" -button1 "OK" -alignDescription left -timeout 30
		echo "Back up was a success.  Completed at $currentDateTime"
			exit 0
else 
	descrip=$(echo -e "There was a failure during the backing up process.\nPlease check your flash drive named: $extVolume for a back up with todays date and time\nIf this exists please delete that folder and re-run Configurator Back Up from Self Service\nIf failure happens again contact the Help Desk ext 7745")
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Configurator Back Up" -heading "Configurator Back Up Failure" -description "$descrip" -button1 "OK" -alignDescription left -timeout 30

		echo "Back up was a failure.  Failed at $currentDateTime during the zipping process."
			exit 1
fi






