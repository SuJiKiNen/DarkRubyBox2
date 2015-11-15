tr = aegisub.gettext

export script_name = tr"Dark Ruby Box"
export script_description = tr"add furigana to lines"
export script_author = "SuJiKiNen"
export script_version = "1"
export script_last_update = "2015/15/11"

DownloadManager = require "DM.DownloadManager"
XmlParser = require "xmlSimple"
require "karaskel"

rubySel = (subs, sel) ->
	
	baseUrl = "http://jlp.yahooapis.jp/FuriganaService/V1/furigana?appid=&grade=1&sentence="
	base = aegisub.decode_path "?user/"
	dlm = DownloadManager!
	failedlines = {}
	
	processText = (text,lineNum) ->
		myParser = XmlParser\newParser!
		url = baseUrl..text
		filename = "tmp.xml"
		savePath = base..filename
		dl, err = dlm\addDownload url,savePath
		
		dlm\waitForFinish -> true
		if dl.error
			aegisub.debug.out "error while downloading\n"
			table.insert failedlines,lineNum
			return text
			
		file = io.open savePath,"r"
		xmlText = file\read "*a"
		
		xml = myParser\ParseXmlText xmlText
		
		wordNum =  xml.ResultSet.Result.WordList\numChildren!
		
		resultStr = ""
		
		for i=1,wordNum 
			surface =  ""
			
			if wordNum > 1
				surface = xml.ResultSet.Result.WordList.Word[ i ].Surface\value!
			else
				surface = xml.ResultSet.Result.WordList.Word.Surface\value!
				
			furigana = ""
				
			wordChildNum = 0
			
			if wordNum > 1
				wordChildNum = xml.ResultSet.Result.WordList.Word[ i ]\numChildren!
			else
				wordChildNum = xml.ResultSet.Result.WordList.Word\numChildren!
			
			hasFuri = false
			hasSubWord = false
			for j=1,wordChildNum
			
				wordChildName = ""
				
				if wordNum > 1
					wordChildName = xml.ResultSet.Result.WordList.Word[ i ]\children![j]\name!
				else
					wordChildName = xml.ResultSet.Result.WordList.Word\children![j]\name!
				
				if wordChildName == "Furigana"
					hasFuri = true
				if wordChildName == "SubWordList"
					hasSubWord = true
			
			if hasFuri
				if wordNum > 1
					furigana = xml.ResultSet.Result.WordList.Word[ i ].Furigana\value!
				else
					furigana = xml.ResultSet.Result.WordList.Word.Furigana\value!
			
			if hasSubWord
				subWordNum = 0
				if wordNum > 1
					subWordNum = xml.ResultSet.Result.WordList.Word[ i ].SubWordList\numChildren!
				else
					subWordNum = xml.ResultSet.Result.WordList.Word.SubWordList\numChildren!
				
				for k=1,subWordNum
					ssurface = ""
					if wordNum > 1
						ssurface = xml.ResultSet.Result.WordList.Word[ i ].SubWordList.SubWord[ k ].Surface\value!
					else
						ssurface = xml.ResultSet.Result.WordList.Word.SubWordList.SubWord[ k ].Surface\value!
					
					sfurigana = ""
					subWordChildNum = 0
					
					if wordNum > 1
						subWordChildNum = xml.ResultSet.Result.WordList.Word[ i ].SubWordList.SubWord[ k ]\numChildren!
					else
						subWordChildNum	= xml.ResultSet.Result.WordList.Word.SubWordList.SubWord[ k ]\numChildren!
					
					for l=1,subWordChildNum
						subWordChildName = ""
						
						if wordNum > 1
							subWordChildName = xml.ResultSet.Result.WordList.Word[ i ].SubWordList.SubWord[ k ]\children![l]\name!
						else
							subWordChildName = xml.ResultSet.Result.WordList.Word.SubWordList.SubWord[ k ]\children![l]\name!
						
						if subWordChildName == "Furigana"
							if wordNum > 1
								sfurigana =xml.ResultSet.Result.WordList.Word[ i ].SubWordList.SubWord[ k ].Furigana\value!
							else
								sfurigana =xml.ResultSet.Result.WordList.Word.SubWordList.SubWord[ k ].Furigana\value!
							
					if sfurigana !="" and ssurface!=sfurigana
						resultStr = resultStr.."{\\k1}"..ssurface.."|"..sfurigana
					else
						resultStr = resultStr.."{\\k1}"..ssurface
			else
				if hasFuri and surface != furigana
					resultStr = resultStr.."{\\k1}"..surface.."|"..furigana
				else
					resultStr = resultStr.."{\\k1}"..surface
			
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
	
	if #failedlines > 0
		aegisub.debug.out tostring #failedlines .." lines failed\n"
		aegisub.debug.out table.concat(failedlines,",")
		
		
	failedlines
	
rubyAll = (subs) ->
	sel = {}
	for i=1,#subs
		line = subs[i]
		if line.class == "dialogue" and not line.comment and line.text~=""
			table.insert sel,i
	rubySel subs,sel
	
	
aegisub.register_macro "#{script_name}/Apply On Selected Lines", script_description, rubySel
aegisub.register_macro "#{script_name}/Apply On All Lines", script_description, rubyAll