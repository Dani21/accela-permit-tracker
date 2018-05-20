# Cities to search for permits:
$locations = 'SACRAMENTO','STOCKTON','OAKLAND','SANDIEGO','YUBA','LIVERMORE'
# Keyword to search for permits:
$keyword = 'tesla'
# Start date to search for permits from:
$start = (Get-Date).AddDays(-7).ToShortDateString()

# TODO: Add better logging, remote Invoke-WebRequest unnecessary af PS message overlays, add better error handling
# Function to return an attribute from the fucking dumb menu array structure
function ArrayAttr {
	param($obj,$attrName)
	for($i=0; $i -lt $obj.Count; $i++) {
		if($obj[$i][0] -eq $attrName) {
			return ($obj[$i][1])
		}
	}
}
# Uncompatible examples that use a separate "Search" menu:
# $incompatible = 'monterey','mesa'
# Unused:
# $modules = 'Building','Planning','Engineering','PublicWorks','Licenses','Enforcement','Enforce','Fire','Health','OperatingPermit','Permits','Police'
# $modules = 'Building', 'Planning', 'Engineering', 'OperatingPermit'
# Force improved security because screw MITM script kiddies
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Used for message at end
$counter = 0
$counter2 = 0
# Loop through each city's pages
foreach($loc in $locations) {
	# First download the homepage of the city to identify URL's in the dumbass menu JS structure
	$urls = @()
	$page = Invoke-WebRequest "https://aca.accela.com/$loc/Welcome.aspx" -UseBasicParsing
	# Verify the page even has the JS structure:
	if($page.Content -match '__Tab\.TabItems=(.*);') {
		# Reformat individual characters in JS array because PowerShell's ConvertFrom-Json commandlet is inflexible as shit
		# It apparently doesn't understand JS uses both quotes for strings just like PS? And the same thing with trailing commas in arrays like wtf???
		$tabs = ConvertFrom-Json ($matches[1] -replace '"','\"' -replace "'",'"' -replace ',\]',',null]')
		$list = $tabs[0][1]
		# Counter is used because enumeration doesn't work with objects converted from JSON for some reason... Whoever wrote this module should be fired from MS
		for($i=0; $i -lt $list.Count; $i++) {
			if((ArrayAttr $list[$i] 'Label') -eq 'Home') {
				$list = @(ArrayAttr $list[$i] 'Links')
				break
			}
		}
		for($i=0; $i -lt $list.Count; $i++) {
			if((ArrayAttr $list[$i] 'Label') -eq 'Advanced Search') {
				$list = @(ArrayAttr $list[$i] 'Links')
				break
			}
		}
		for($i=0; $i -lt $list.Count; $i++) {
			if((ArrayAttr $list[$i] 'Label') -eq 'Search Records/Applications') {
				$list = @(ArrayAttr $list[$i] 'Links')
				break
			}
		}
		# Now convert relative URLs to absolute URLs based on the page it was downloaded from
		# Why in the flying shit do I have to cast a string to a URL in order to pass it into a constructor? Holy fucking hell MSDN could use some work.
		for($i=0; $i -lt $list.Count; $i++) {
			$urls += (New-Object System.Uri([System.Uri]"https://aca.accela.com/$loc/Welcome.aspx", (ArrayAttr $list[$i] 'URL'))).AbsoluteUri
		}
		# $counter2 is for the total URL count
		$counter2 += $urls.Count
		foreach($url in $urls) {
			# TODO: Replace this with better logic to match all appropriate search pages in navigation
			if($url -notmatch '[&?]module=([a-z]+)') {# -or $matches[1] -notin $modules) {
				continue
			}
			# Get module name to provide better details when alerting user of matched permits
			$module = $matches[1]
			# Download URL
			$result = Invoke-WebRequest $url -UseBasicParsing
			$formTags = [regex]::matches($result.Content, '<form [^>]*action="(?<action>[^>"]+)"[^>]*>(?<contents>.+)</form>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
			if($formTags.Count) {
				# Get form URL to submit to
				# TODO: Proper HTML decoding
				$action = $formTags[0].Groups['action'].Value -replace '&amp;','&'
				# Resolve relative URL
				$action = (New-Object System.Uri([System.Uri]$url, $action)).AbsoluteUri
				$params = @()
				# Manually add JS-created form parameter
				$params += [System.Net.WebUtility]::UrlEncode('ctl$100ScriptMananger1') + '=' + [System.Net.WebUtility]::UrlEncode('ctl00$PlaceHolderMain$updatePanel|ctl00$PlaceHolderMain$btnNewSearch')
				# Use $invalid to identify if a search form doesn't have a parameter for "Project Name" which is used for our keyword
				# TODO: Find out which modules don't have a "Project Name" and determine if they're relevant
				$invalid = $true
				# Loop through <input> tags
				$inputTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<(input|button) (value="(?<value>[^>"]*)"|[^>])*name="(?<name>[^>"]+)"(value="(?<value>[^>"]*)"|[^>])*>',[System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture)
				foreach($input in $inputTags) {
					$name = $input.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"'
					if($input.Groups['value'].Success) {
						$value = $input.Groups['value'].Value -replace '&amp;','&' -replace '&quot;','"'
					} else {
						$value = ''
					}
					# Update form parameters to perform search
					switch -exact ($input.Groups['name'].Value) {
						'ctl00$PlaceHolderMain$generalSearchForm$txtGSProjectName' {
							# Keyword is inserted here, apparently % can be used as a wildcard but * seems to work exactly the same way and most people already know it as the wildcard
							$value = "*$keyword"
							$invalid = $false
						} 'ctl00$PlaceHolderMain$generalSearchForm$txtGSStartDate' {
							# Insert start date to search permits from
							$value = $start
						} '__EVENTTARGET' {
							# JS assigned form parameter
							$value = 'ctl00$PlaceHolderMain$btnNewSearch'
						} 'txtSearchCondition' {
							# Idek remember why but this is another JS-specified form parameter
							$value = ''
						}
						# TODO: Check that no other parameters need to be modified for each module's search form
					}
					# Add parameter to list
					# I verified the UrlEncode function is correct for encoding form parameters only and fully understand the HTTP spec
					# Don't fucking dare replace the UrlEncode function used here
					$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode($value)
				}
				if($invalid) {
					# Skip this URL if we didn't add in the keyword
					continue
				}
				# Loop through <select> tags
				$selectTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<select [^>]*name="(?<name>[^>"]+)"[^>]*>(?<contents>(?:(?!</select>).)*)</select>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
				foreach($select in $selectTags) {
					$name = $select.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"'
					# Search option tags
					# TODO: Super low priority but find option that's selected="selected" or some shit
					# ----- May be hard to do because technically "selected" could be used and "selected" could appear in other HTML attributes
					# ----- Thank god Accela doesn't appear to use multiselected options
					$optionTags = [regex]::matches($select.Groups['contents'].Value, '<option((value="(?<value>[^>"]*)")|[^>])*>(?<contents>(?:(?!</option>).)*)</option>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
					if($optionTags.Count) {
						# Assume no <option> is selected and use first one as default
						if($optionTags[0].Groups['value'].Success) {
							# Use hidden value parameter if it's specified
							$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode(($optionTags[0].Groups['value'].Value -replace '&amp;','&' -replace '&quot;','"'))
						} else {
							# Otherwise use <option> contents if no value is specified
							# TODO: Check if HTML or whitespace is stripped
							$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode(($optionTags[0].Groups['contents'].Value -replace '&amp;','&' -replace '&quot;','"'))
						}
					}
				}
				# Loop through <textarea> tags in case if Accela is anal about our form parameters
				$textTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<textarea [^>]*name="(?<name>[^>"]+)"[^>]*>(?<contents>(?:(?!</textarea>).)*)</textarea>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
				foreach($text in $textTags) {
					# Finally something that's simple as shit
					$params += [System.Net.WebUtility]::UrlEncode(($text.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"')) + '=' + [System.Net.WebUtility]::UrlEncode(($text.Groups['contents'].Value -replace '&amp;','&' -replace '&quot;','"'))
				}
				# Submit the parameters to form URL, apparently referrer and origin HTTP parameters are required by Accela to prevent CSRF
				# Btw "Referer" is NOT a misspelling below, just don't touch it
				$result2 = Invoke-WebRequest $action -UseBasicParsing -Method Post -Body ($params -join '&') -Headers @{ 'Content-type' = 'application/x-www-form-urlencoded'; 'Referer' = $url; 'Origin' = $url }
				# TODO: Remove this later, apparently isn't needed
				# Don't ask
				<#$piper = '^(?<len>\d+)\|(?<p1>[^|]*)\|(?<p2>[^|]*)\|'
				$rem = $result2.Content
				$success = $true
				for($i=0; $i -lt 3; $i++) {
					$head = [regex]::matches($rem, $piper)
					if($head.Count) {
						$count = [int]::Parse($head[0].Groups['len'])
						$cur = $rem.Substring($head[0].Length, $count)
						$rem = $rem.Substring($head[0].Length + $count)
						if($cur -match '<div id="ctl00_PlaceHolderMain_RecordSearchResultInfo_updatePanel">' -and $cur -match 'ctl00_PlaceHolderMain_RecordSearchResultInfo_noDataMessageForSearchResultList_messageBar') {
							$success = $false
							break
						}
					} else {
						$wshell = New-Object -ComObject Wscript.Shell -ErrorAction Stop
						$wshell.Popup("Pipe format did not match!",0,"Accela",16)
						$success = $false
						Break
					}
					if(-not $rem -or $rem -eq '|') {
						break
					}
					if($rem[0] -eq '|') {
						$rem = $rem.Substring(1)
					} else {
						$wshell = New-Object -ComObject Wscript.Shell -ErrorAction Stop
						$wshell.Popup("Pipe format did not match!",0,"Accela",16)
						$success = $false
						Break
					}
				}#>
				# Increment counter for total submitted forms
				$counter++
				# This is an easy way to identify the "no results" message
				$success = $result2.Content -notmatch 'ctl00_PlaceHolderMain_RecordSearchResultInfo_noDataMessageForSearchResultList_messageBar'
				if($success) {
					$wshell = New-Object -ComObject Wscript.Shell -ErrorAction Stop
					# See if there are multiple results
					# TODO: Test this more
					# TODO: Replace VBScript alerts with better representation of results, especially ones that don't interrupt script execution. I know, I just got lazy at this point. Same with keeping this comment short
					if($result2.Content -match 'Showing \d+-\d+ of (\d+)' -and $matches[1] -ne '1') {
						$result = $wshell.Popup("Found $($matches[1]) '$keyword' permits (module $module) in $loc! Click OK to visit search page.",0,"Accela",49)
					} else {
						# Apparently if a single result is returned, the form's submission URL is the URL of the result
						$formTags = [regex]::matches($result2.Content, '<form [^>]*action="(?<action>[^>"]+)"[^>]*>')
						if($formTags.Count) {
							$url = (New-Object System.Uri([System.Uri]$url, ($formTags[0].Groups['action'].Value -replace '&amp;','&'))).AbsoluteUri
							$result = $wshell.Popup("Found a '$keyword' permit (module $module) in $loc! Click OK to visit permit page.",0,"Accela",49)
						} else {
							# Just in case
							$result = $wshell.Popup("Found a '$keyword' permit (module $module) in $loc! Click OK to visit search page.",0,"Accela",49)
						}
					}
					if($result -eq 1) {
						Start-Process $url
					}
				}
			}
		}
	}
}
# Log message of overall number of searches performed
Write-Host "Performed $counter searches and skipped $($counter2 - $counter) incompatible forms."
Start-Sleep 3
