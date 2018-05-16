$UserNameUnencoded = Read-Host -Prompt 'User name'
$pwdUnencoded = Read-Host -AsSecureString -Prompt 'Password' 
$searchString = Read-Host -Prompt 'File search string eg. A_069' 
$encKey=Read-Host -Prompt 'Encryption key (anything you like)'
$outPath="$(get-location)\" #"C:\Temp\"
$UserName=[System.Net.WebUtility]::UrlEncode($UserNameUnencoded) 
$pwd=[System.Net.WebUtility]::UrlEncode([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwdUnencoded))) 
$requestLabel = Read-Host -Prompt 'Label (anything)'
$dataset = "EGAD00001001925"
write-host "Starting..." -ForegroundColor DarkGreen

# Log in
write-host "Logging in..." -ForegroundColor DarkGreen
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/users/$($UserName)?pass=$($pwd)"
$hdrs = @{}
$hdrs.Add("Accept","application/json")
$hdrsDld = @{}
$hdrsDld.Add("Accept","application/octet-stream")
$response = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
$status=$response.response.result[0]
$session=$response.response.result[1]
write-host "Status=$($status) SessionId=$($session)"

#list datasets
$datasetAllowed = $false
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/datasets?session=$($session)"
$response = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
$response.response.result | foreach {if ($_ -eq $dataset) {$datasetAllowed = $true}}
write-host "User allowed to see the dataset : $($datasetAllowed)" -ForegroundColor DarkGreen

# list files
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/datasets/$($dataset)/files?session=$($session)"
$FileList = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
$MatchedFiles = @()
$FileList.response.result | foreach {
	if ($_.fileName -like "*$($searchString)*"){write-host $_.fileName; $MatchedFiles += @(@{fileId=$_.fileId; fileName=$_.fileName})}
	}

$MatchedFiles | foreach {
	write-host "Create a request for a file...$($_.fileId) : $($_.fileName)" -ForegroundColor DarkGreen
	$Fields=@{downloadRequest="{rekey:`"$($encKey)`"; downloadType:`"STREAM`"; descriptor:`"$($requestLabel)`"}"}
	$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/requests/new/files/$($_.fileId)?session=$($session)"
	$response = Invoke-RestMethod -Uri $uri -ContentType 'multipart/form-data' -Method Post -Headers $hdrs -Body $Fields
	write-host $response.header.userMessage
}
Start-sleep 10 #pause it a while to let the server do something

write-host "List tickets in the request-label $($requestLabel)..." -ForegroundColor DarkGreen
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/requests/$($requestLabel)?session=$($session)"
$ticketResponse = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
$ticketResponse.response.result| foreach {write-host "TicketId: $($_.ticket) FileName: $($_.fileName)"}

#Do the actual downloads!
$ticketResponse.response.result | foreach {
	$TicketId=$_.ticket
	write-host "Download $($TicketId)..."
	$uri="http://ega.ebi.ac.uk/ega/rest/download/v2/downloads/$($TicketId)"
	write-host "$($outPath)$($_.fileName -replace('/', '_'))" -ForegroundColor Yellow
	Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/octet-stream' -Headers $hdrsDld -OutFile "$($outPath)$($_.fileName -replace('/', '_'))"
}


# delete the request 
write-host "Delete the request..." -ForegroundColor DarkGreen
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/requests/delete/$($requestLabel)?session=$($session)"
$response = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
if ($response.header.code -eq "200"){write-host "Deleted ok"} else {write-host "error : $($response.header.code)"}

# Log out
$uri="https://ega.ebi.ac.uk/ega/rest/access/v2/users/logout?session=$($session)"
$response = Invoke-RestMethod -Uri $uri -Method Get -ContentType 'application/json' -Headers $hdrs
write-host $response.response.result[0]