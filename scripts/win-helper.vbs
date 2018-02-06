args = WScript.Arguments.Count

if args <> 3 then
  wscript.Quit
end if


UA = WScript.Arguments.Item(0)
URL = WScript.Arguments.Item(1)
OUTFILE = WScript.Arguments.Item(2)

Set xmlhttp = CreateObject("Microsoft.XmlHttp")  
xmlhttp.open "GET", URL, false
xmlhttp.setRequestHeader "User-Agent",  UA
xmlhttp.send

Set oStream = CreateObject("ADODB.Stream")
With oStream
	.Type = 1 'adTypeBinary
	.Open
	.Write xmlhttp.responseBody 'to save binary data
	.SaveToFile OUTFILE, 2 'adSaveCreateOverWrite
End With

Set oStream = Nothing
Set ret = Nothing