-- Чтение данных из файлов формата DBF
-- Sinilga, 2019
-- Использованы материалы Geoff Leyland (github.com/geoffleyland/lua-dbf)

local DBFReader = {}
local ok_field_types = {
	["C"] = "Character",
	["Y"] = "Currency",
	["N"] = "Numeric",
	["F"] = "Float",
	["D"] = "Date",
	["T"] = "DateTime",
	["B"] = "Double",
	["I"] = "Integer",
	["L"] = "Logical",
	["M"] = "Memo",
	["G"] = "General",
	["P"] = "Picture",
	["+"] = "Autoincrement (dBase Level 7)",
	["O"] = "Double (dBase Level 7)",
	["@"] = "Timestamp (dBase Level 7)",
	["V"] = "Varchar type (Visual Foxpro)",
}
local number_field_types = {"Y","N","F","B","I","L","O"}
local ok_record_types = { [" "]=true, ["*"]=true }
local Pages = {
	[1]=437, [2]=850, [3]=1252, [4]=10000, [8]=865, [9]=437, [10]=850, [11]=437, [13]=437, [14]=850, [15]=437, 
	[16]=850, [17]=437, [18]=850, [19]=932, [20]=850, [21]=437, [22]=850, [23]=865, [24]=437, [25]=437, [26]=850, 
	[27]=437, [28]=863, [29]=850, [31]=852, [34]=852, [35]=852, [36]=860, [37]=850, [38]=866, [55]=850, [64]=852, 
	[77]=936, [78]=949, [79]=950, [80]=874, [87]=866, [88]=1252, [89]=1252, [100]=852, [101]=866, [102]=865, 
	[103]=861, [104]=895, [105]=620, [106]=737, [107]=857, [108]=863, [120]=950, [121]=949, [122]=936, [123]=932, 
	[124]=874, [134]=737, [135]=852, [136]=857, [150]=10007, [151]=10029, [152]=10006, [200]=1250, [201]=1251, 
	[202]=1254, [203]=1253, [204]=1257
} 


------------------------------------------------------------------------------

local function read_header(self)
	local f = self.fh
	local tmp = {f:read(32):byte(1,32)}
	self.VersionID = tmp[1]
	local date = DateTime()
	date.Year = tmp[2] + 1900
	date.Month = tmp[3]
	date.Day = tmp[4]
	self.LastUpdate = date
	self.HeaderLength = tmp[10]*256 + tmp[9]
	self.RecordsCount =  ((tmp[8]*256 + tmp[7])*256 + tmp[6])*256 + tmp[5]
	self.FirstRecordPosition = tmp[10]*256 + tmp[9]
	self.RecordLength = tmp[12]*256 + tmp[11]
	self.TableFlag = tmp[29]
	self.CodePage = tmp[30]
	self.FieldsCount = (self.HeaderLength - 1) / 32 - 1

	local filesize = IO.File.GetInfo(self.FileName).Size
	local datasize = self.FirstRecordPosition + self.RecordsCount * self.RecordLength+1
	if filesize ~= datasize then
		return false
	end
	
	fields = {}
	local total_length = 1  -- for skipping
	for i = 1, self.FieldsCount do
		local name = f:read(11):match("%Z*")
		local tp = f:read(1)
		if not ok_field_types[tp] then
		      continue
		end
		f:read(4)
		local length = f:read(1):byte()
		f:read(15)
		fields[i] = { Name=name, Type=tp, Length=length,IsNum = table.getkey(number_field_types,tp) }
		total_length = total_length + length
	end
	f:read(1)
	fields.total_length = total_length
	
	return fields
end

local function new(fname)
	local obj = {}
	setmetatable(obj, {["__index"] = DBFReader})
	obj.FileName = fname
	obj.fh = io.open(fname,"rb")
	if not obj.fh then
		return nil
	end
	local fields = read_header(obj)
	if fields then
		obj.Fields = fields
		return obj
	else
		return false
	end	
end

local function decode_val(self,field,val)
	if not val or val == "" then
		return number_field_types[field.Type] and 0 or ""
	end
	if field.Type == "B" and (self.VersionID == 48 or self.VersionID == 49) then -- Binary
		val = "memo "..val 
	elseif field.Type == "B" then -- Double
		val = val --!IEEE 754
	elseif field.Type == "I" then -- integer
		local tmp = {val:byte(1,#val)} 
		val = 0
		for i=1,#tmp do				-- big-endian 
			val = val*256 + tmp[i]
		end
		if tmp[1] > 127 then		-- дополнительный код
			val = -1*(math.pow(256,#tmp)-val) 
		end
	elseif field.Type == "O" then -- Double
		local c = "" -- !IEEE754 8B
		local q = ""
		val = tonumber(val)
	elseif field.Type == "Y" then -- Currency (litle-endian 8B)
		local tmp = {val:byte(1,#val)}
		val = 0
		for i=#tmp,1,-1 do
			val = val*256 + tmp[i]
		end
	elseif field.Type == "+" then -- Autoincrement (dBASE 7)
		local tmp = {val:byte(1,#val)} --! big-endian
		val = 0
		for i=1,#tmp do
			val = val*256 + tmp[i]
		end
		if tmp[1] > 127 then		-- дополнительный код
			val = -1*(math.pow(256,#tmp)-val) 
		end
	elseif field.Type == "F" then -- float
		val = tonumber(val)
	elseif field.Type == "N" then -- numeric
		val = tonumber(val)
	elseif field.Type == "C" then -- Character
		if self.CodePage == 0 then
			val = val:decode(866)
		elseif self.CodePage ~= 201 then
			val = val:decode(Pages[self.CodePage])
		end
		val = val:match("^%s*(.-)%s*$")
	elseif field.Type == "D" then -- date "ГГГГММДД"
		val = val:gsub("(%d%d%d%d)(%d%d)(%d%d)","%3.%2.%1")
	elseif field.Type == "G" then -- general
		val = "memo "..val
	elseif field.Type == "M" then -- memo
		val = "memo "..val
	elseif field.Type == "L" then -- logical
		val = val:match("[TtYy]") and "true" or val:match("FfNn") and "false" or ""
	elseif field.Type == "P" then -- picture
		val = "picture "..val
	elseif field.Type == "Q" then -- Varbinary
		val = "memo "..val
	elseif field.Type == "V" then -- Varchar
		val = "memo "..val
	elseif field.Type == "WQ" then -- Blob
		val = "memo "..val
	elseif field.Type == "T" and #val == 14 then -- date time
		val = val:gsub("(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)","%3.%2.%1 %4:%5:%6")
	elseif field.Type == "T" and #val == 8 or field.Type == "@" then
		local tmp = { val:byte(1,#val) }
		local jdn = ((tmp[4]*256+tmp[3])*256+tmp[2])*256+tmp[1]
		local msec = ((tmp[8]*256+tmp[7])*256+tmp[6])*256+tmp[5]
		local t1 = jdn + 32082
		local t2 = math.floor((4*t1+3)/1461)
		local t3 = t1 - math.floor(1461*t2/4)
		local t4 = math.floor((5*t3+2)/153)
		local day = t3 - math.floor((153*t4 + 2)/5) + 1
		local month = t4 + 3 - 12*math.floor(t4/10)  
		local year = t2 - 4800 + math.floor(t4/10)
		local sec = msec/1000
		local hour = math.floor(sec/3600)
		sec = sec%3600
		local min = math.floor(sec/60)
		sec = sec%60
		val = ("%d.%d.%d %d:%d:%d"):format(day,month,year,hour,min,sec)
	else
	end
	return val
end

local function read_record(self)
	local f = self.fh
	local fields = self.Fields
	local id = f:read(1)
	if not id then
		return
	end
	if not ok_record_types[id] then 
		return 
	end
	local r = {}
	for _, field in ipairs(fields) do
		local data = f:read(field.Length)
		if not data then
			return
		end
		data = decode_val(self,field,data)
		r[field.Name] = data
	end
	return r
end

local function skip_record(self,n)
	n = tonumber(n) or 1
	for i=1,n do
		self.fh:read(self.Fields.total_length)
	end	
end

local function close(self)
	self.fh:close()
end

local function lines(self)
	return function() 
		return self:read() 
	end
end

DBFReader = {
	new = new,
	read = read_record,
	skip = skip_record,
	lines = lines,
	close = close,
}

setmetatable(DBFReader,{ ["__call"] = function(self,...) return new(...) end } )
------------------------------------------------------------------------------
return DBFReader
------------------------------------------------------------------------------
