$incompatible = 'monterey','mesa'
$locations = 'SACRAMENTO','STOCKTON','OAKLAND','SANDIEGO','YUBA','LIVERMORE'
$modules = 'Building','Planning','Engineering','PublicWorks','Licenses','Enforcement','Enforce','Fire','Health','OperatingPermit','Permits','Police'
# $modules = 'Building', 'Planning', 'Engineering', 'OperatingPermit'
$keyword = 'tesla'
$start = (Get-Date).AddDays(-7).ToShortDateString()
$counter = 0
$counter2 = 0

function ArrayAttr {
	param($obj,$attrName)
	for($i=0; $i -lt $obj.Count; $i++) {
		if($obj[$i][0] -eq $attrName) {
			return ($obj[$i][1])
		}
	}
}
foreach($loc in $locations) {
	$urls = @()
	$page = Invoke-WebRequest "https://aca.accela.com/$loc/Welcome.aspx" -UseBasicParsing
	if($page.Content -match '__Tab\.TabItems=(.*);') {
		$tabs = ConvertFrom-Json ($matches[1] -replace '"','\"' -replace "'",'"' -replace ',\]',',null]')
		$list = $tabs[0][1]
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
		for($i=0; $i -lt $list.Count; $i++) {
			$urls += (New-Object System.Uri([System.Uri]"https://aca.accela.com/$loc/Welcome.aspx", (ArrayAttr $list[$i] 'URL'))).AbsoluteUri
		}
		$counter2 += $urls.Count
		foreach($url in $urls) {
			if($url -notmatch '[&?]module=([a-z]+)') {# -or $matches[1] -notin $modules) {
				continue
			}
			$module = $matches[1]
			$result = Invoke-WebRequest $url -UseBasicParsing
			$formTags = [regex]::matches($result.Content, '<form [^>]*action="(?<action>[^>"]+)"[^>]*>(?<contents>.+)</form>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
			if($formTags.Count) {
				$action = $formTags[0].Groups['action'].Value -replace '&amp;','&'
				$action = (New-Object System.Uri([System.Uri]$url, $action)).AbsoluteUri
				$params = @( )
				$params += [System.Net.WebUtility]::UrlEncode('ctl$100ScriptMananger1') + '=' + [System.Net.WebUtility]::UrlEncode('ctl00$PlaceHolderMain$updatePanel|ctl00$PlaceHolderMain$btnNewSearch')
				$inputTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<(input|button) (value="(?<value>[^>"]*)"|[^>])*name="(?<name>[^>"]+)"(value="(?<value>[^>"]*)"|[^>])*>',[System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture)
				$invalid = $true
				foreach($input in $inputTags) {
					$name = $input.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"'
					if($input.Groups['value'].Success) {
						$value = $input.Groups['value'].Value -replace '&amp;','&' -replace '&quot;','"'
					} else {
						$value = ''
					}
					switch -exact ($input.Groups['name'].Value) {
						'ctl00$PlaceHolderMain$generalSearchForm$txtGSProjectName' {
							$value = '*' + $keyword
							$invalid = $false
						} 'ctl00$PlaceHolderMain$generalSearchForm$txtGSStartDate' {
							$value = $start
						} '__EVENTTARGET' {
							$value = 'ctl00$PlaceHolderMain$btnNewSearch'
						} 'txtSearchCondition' {
							$value = ''
						}
					}
					$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode($value)
				}
				if($invalid) {
					continue
				}
				$selectTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<select [^>]*name="(?<name>[^>"]+)"[^>]*>(?<contents>(?:(?!</select>).)*)</select>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
				foreach($select in $selectTags) {
					$name = $select.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"'
					$optionTags = [regex]::matches($select.Groups['contents'].Value, '<option((value="(?<value>[^>"]*)")|[^>])*>(?<contents>(?:(?!</option>).)*)</option>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
					if($optionTags.Count) {
						if($optionTags[0].Groups['value'].Success) {
							$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode(($optionTags[0].Groups['value'].Value -replace '&amp;','&' -replace '&quot;','"'))
						} else {
							$params += [System.Net.WebUtility]::UrlEncode($name) + '=' + [System.Net.WebUtility]::UrlEncode(($optionTags[0].Groups['contents'].Value -replace '&amp;','&' -replace '&quot;','"'))
						}
					}
				}
				$textTags = [regex]::matches($formTags[0].Groups['contents'].Value, '<textarea [^>]*name="(?<name>[^>"]+)"[^>]*>(?<contents>(?:(?!</textarea>).)*)</textarea>',[System.Text.RegularExpressions.RegexOptions]::Singleline)
				foreach($text in $textTags) {
					$params += [System.Net.WebUtility]::UrlEncode(($text.Groups['name'].Value -replace '&amp;','&' -replace '&quot;','"')) + '=' + [System.Net.WebUtility]::UrlEncode(($text.Groups['contents'].Value -replace '&amp;','&' -replace '&quot;','"'))
				}
				$result2 = Invoke-WebRequest $action -UseBasicParsing -Method Post -Body ($params -join '&') -Headers @{ 'Content-type' = 'application/x-www-form-urlencoded'; 'Referer' = $url; 'Origin' = $url }
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
				$counter++
				$success = $result2.Content -notmatch 'ctl00_PlaceHolderMain_RecordSearchResultInfo_noDataMessageForSearchResultList_messageBar'
				if($success) {
					$wshell = New-Object -ComObject Wscript.Shell -ErrorAction Stop
					if($result2.Content -match 'Showing \d+-\d+ of (\d+)' -and $matches[1] -ne '1') {
						$result = $wshell.Popup("Found $($matches[1]) '$keyword' permits (module $module) in $loc! Click OK to visit search page.",0,"Accela",49)
					} else {
						$formTags = [regex]::matches($result2.Content, '<form [^>]*action="(?<action>[^>"]+)"[^>]*>')
						if($formTags.Count) {
							$url = (New-Object System.Uri([System.Uri]$url, ($formTags[0].Groups['action'].Value -replace '&amp;','&'))).AbsoluteUri
							$result = $wshell.Popup("Found a '$keyword' permit (module $module) in $loc! Click OK to visit permit page.",0,"Accela",49)
						} else {
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
Write-Host "Performed $counter searches and skipped $($counter2 - $counter) incompatible forms."
Start-Sleep 3
