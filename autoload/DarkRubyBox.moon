tr = aegisub.gettext

export script_name = tr"Dark Ruby Box2"
export script_description = tr"add furigana to kanji"
export script_author = "SuJiKiNen"
export script_version = "1"
export script_last_update = "2015/30/11"

DownloadManager = require "DM.DownloadManager"
clipboard = require "aegisub.clipboard"
re = require "re"
SLAXML = require "slaxdom"
require "karaskel"

elementText = (el) ->
	pieces = {}
	for _,n in ipairs el.kids
		if n.type == "element"
			pieces[ #pieces+1 ] = ElementText n
		elseif n.type == "text"
			pieces[ #pieces+1 ] = n.value
	return table.concat pieces
	
hasSubWordList = (word) ->
	for _,n in ipairs word.el
		if n.name == "SubWordList"
			return n.el
	return nil
	
getSurface = (word) ->
	for _,n in ipairs word.el
		if n.name == "Surface"
			return elementText n
	return ""
	
getFurigana = (word) ->
	for _,n in ipairs word.el
		if n.name == "Furigana"
			return elementText n
	return ""
	

rubySel = (subs, sel) ->
	
	urlHead = "http://jlp.yahooapis.jp/FuriganaService/V1/furigana?"
	appid = ""
	grade = "1"
	baseUrl = urlHead.."appid=#{appid}&".."grade=#{grade}&"
	
	base = aegisub.decode_path "?user/"
	dlm = DownloadManager!
	failedlines = {}
	
	processText = (text,lineNum) ->
		url = baseUrl.."sentence="..text
		filename = "tmp.xml"
		savePath = base..filename
		dl, err = dlm\addDownload url,savePath
		aegisub.debug.out url
		dlm\waitForFinish -> true
		if dl.error
			aegisub.debug.out "error while downloading\n"
			table.insert failedlines,lineNum
			return text
			
		file = io.open savePath,"r"
		xmlText = file\read "*a"
		file\close!
		doc = SLAXML\dom xmlText
		resultSet = doc.kids[2]
		result = resultSet.el[1]
		wordList = result.el[1].el
		count = 0
		resultStr = ""
		for _,word in ipairs wordList
			count += 1
			if hasSubWordList word
				subWordList = hasSubWordList word
				for __,sword in ipairs subWordList
					ssurface = getSurface sword
					sfurigana = getFurigana sword
					if sfurigana!="" and ssurface!=sfurigana
						resultStr ..= "{\\k1}"..ssurface.."|!"..sfurigana
					else
						resultStr ..= "{\\k1}"..ssurface
			else
				surface = getSurface word
				furigana = getFurigana word
				if furigana!=""
					resultStr ..= "{\\k1}"..surface.."|!"..furigana
				else
					resultStr ..= "{\\k1}"..surface
		
		return resultStr
	
	meta, styles = karaskel.collect_head subs
	
	firstline = -1
	for i=1,#subs 
		line = subs[i]
		if line.class == "dialogue" and firstline == -1
			firstline = i
	count = 0
	total = #sel
	for _,i in ipairs sel 
		line = subs[i]
		count = count + 1
		if line.class == "dialogue" and not line.comment and line.text~=""
			karaskel.preproc_line_text meta, styles, line
			line.text = processText line.text_stripped,i
			subs[i] = line
			aegisub.debug.out "Process line ".. tostring i-firstline+1 .." "..line.text_stripped.."\n"
			aegisub.progress.set count*100/total
			if aegisub.progress.is_cancelled!
				aegisub.cancel!
				return failedlines
	
	if #failedlines > 0
		aegisub.debug.out tostring #failedlines .." lines failed\n"
		aegisub.debug.out table.concat(failedlines,",").."\n"
		clipboard.set table.concat(failedlines,",")
		logfname = "failedlines.log"
		logfile = io.open base..logfname,"w"
		logfile\write table.concat(failedlines,",")
		logfile\close!
		aegisub.debug.out "failed lines numbers have written to log file"
	failedlines
	
	
rubyAll = (subs) ->
	sel = {}
	for i=1,#subs
		line = subs[i]
		if line.class == "dialogue" and not line.comment and line.text~=""
			table.insert sel,i
	rubySel subs,sel
	
	
getConfigDialog = ->
	configDialog = { 
		lineNumsLabel: { class: "label",label: "Paste failedlines:",x: 0, y: 0, width: 1,height:1 } 
		lineNums:      { class: "textbox",name: "lineNums",x: 0,y: 1,width: 20,height: 4,value: "",hint: "failed lines numbers must seperate by comma like this: 1,2,4"}
	}
	clipboardText = clipboard.get! or ""
	if string.match(clipboardText, "^[%d]+[,[%d]+]*,?")
		configDialog.lineNums.value = clipboardText
	return configDialog 
	
selFailed = (subs,sel) ->
	button, result = aegisub.dialog.display getConfigDialog!, {"OK","Cancel"}
	failedlines = {}
	if button == "OK"
		failedlines = re.split result.lineNums,","
		for i=1,#failedlines 
			failedlines[i] = tonumber failedlines[i]
	else
		aegisub.cancel!
	
	return failedlines
	
selFailedLog = (subs,sel) ->
	logfname = "failedlines.log"
	base = aegisub.decode_path "?user/"
	logfile = io.open base..logfname,"r"
	lineNums = logfile\read "*a"
	failedlines = re.split lineNums,","
	
	for i=1,#failedlines 
		failedlines[i] = tonumber failedlines[i]
	
	logfile\close!
	return failedlines
	
	
aegisub.register_macro "#{script_name}/Apply On Selected Lines", script_description, rubySel
aegisub.register_macro "#{script_name}/Apply On All Lines", script_description, rubyAll
aegisub.register_macro "#{script_name}/Select Failed Lines", script_description, selFailed
aegisub.register_macro "#{script_name}/Select Failed Lines From Log File", script_description, selFailedLog