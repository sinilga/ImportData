local Options = {
	boxes = {	},
	Level = 1,
	VocBase = CroApp.GetBank():GetBase("FS"),
	FileHandle = nil,
	MaxRecords = nil,
}

function btnBrowse_Click( control, event )
	local fn = FileOpenDialog()
	if fn then
		fn = fn[1]
	end	
	Me.txtFileName.Text = fn
	local n = IO.File.GetInfo(fn).Size
	Me.labFileSize.Text = ("%.1f KB"):format(n/1024)
end

function Форма_Load( form )
	Options.boxes = {
		[Me.cbArea] = 1, 
		[Me.cbDistr] = 4, 
		[Me.cbCity] = 6, 
		[Me.cbStreet] = 7,
	}
	SetLevel(Options.Level)
	for ctrl,_ in pairs(Options.boxes) do
		ctrl.Click = function(control)
			Options.Level = Options.boxes[control]
			SetLevel(Options.Level)
		end
	end
	Me.pnlProgressPos.Width = 0
	Me.labProgress.Visible = false
end

function SetLevel(lev)
	for key,val in pairs(Options.boxes) do
		if key.Check ~= (val <= lev) then
			key.Check = (val <= lev)
		end	
	end
end

function ClearBase(base)
	local rs = base.RecordSet
	base:DeleteRecords(rs,true)
end

function btnLoad_Click( control, event )
	local fh = io.open(Me.txtFileName.Text,"r")
	Options.FileHandle = fh
	Options.FileSize = IO.File.GetInfo(Me.txtFileName.Text).Size
	Load(fh)
end

do	-- загрузка данных

local timer 
local chunk = ""
local st, ed, fpos, bytes

function Load()
	local fh = Options.FileHandle
	local base = Options.VocBase
	ClearBase(base)
	Options.RecordsCount = base.RecordsCount
	Me.labProgress.Visible = true
	chunk = ""
	bytes, st, ed = 0, 1, 0
	timer = Me:CreateTimer(do_step,1,true)
end


function do_step()
	timer:Stop()
	local fh = Options.FileHandle
	local ticks = DateTime.TicksNow
	repeat
		_, ed, item = chunk:find("(%b<>)",st)
		if item then
			st = ed + 1
			proc_item(item)
		else
			chunk = chunk:sub(st)
			local txt = fh:read(1024*100)
			if txt then
				bytes = bytes + #txt
				chunk = chunk..txt
				st = 1
			else
				timer:delete()
				fh:close()
				Me.pnlProgressPos.Width = 0
				Me.labProgress.Visible = false
				MakeHier()
				return 
			end	
		end	
	until DateTime.TicksNow - ticks > 200
	fpos = bytes - #chunk + st
	Me.labProgress.Text = ("Загрузка данных: %.1f%%"):format(100*fpos/Options.FileSize)
	Me.pnlProgressPos.Width = Me.pnlProgressPos.Parent.Width * fpos/Options.FileSize
	timer:Start()
end

function proc_item(item)
	local base = Options.VocBase
	local name, astr = item:match("([%w_]+)%s(.+)/>")
	if not name or name:upper() ~= "OBJECT" then 
		return
	end
	local attr = {}
	for key,val in astr:gmatch([[([%w_]+)="(.-)"]]) do
		attr[key] = val:decode("utf-8")
	end
	if attr["CURRSTATUS"] and attr["CURRSTATUS"] ~= "0"  then
		return
	end
	if (Options.MaxRecords and Options.RecordsCount >= Options.MaxRecords) then
		return
	end
	if attr["AOLEVEL"] and attr["AOLEVEL"] > tostring(Options.Level) then 
		return
	end
	local rec = Record(base)
	rec:SetValue(10,attr["PLAINCODE"])
	rec:SetValue(20,attr["OFFNAME"].." "..attr["SHORTNAME"])
	rec:SetValue(50,attr["POSTALCODE"])
	rec:SetValue(51,attr["OKATO"])
	rec:SetValue(52,attr["AOGUID"])
	rec:SetValue(53,attr["PARENTGUID"])
	base:AddRecord(rec)
	Options.RecordsCount = Options.RecordsCount + 1
end 

end	-- загрузка данных

do	-- построение иерархии в словаре

local rs
local idx
local base
local timer 
local rootSN

function MakeHier()
	base = Options.VocBase
	local root = CroApp.GetBank():StringRequest("ОТ "..base.Code.."01 10 РП И 20 РП")
	if root.Count > 0 then
		rootSN = root:ToTable()[1]
	else
		local rec = base:AddRecord()
		rootSN = rec.SN
	end	
	idx = 1
	rs = Options.VocBase.RecordSet	
	rs:Remove(rootSN)
	Me.labProgress.Visible = true
	timer = Me:CreateTimer(set_parent,1,true)
end

function set_parent()
	timer:Stop()
	local ticks = DateTime.TicksNow
	repeat
		if idx > rs.Count then
			timer:delete()
			Me.pnlProgressPos.Width = Me.pnlProgressPos.Parent.Width
			Me.labProgress.Visible = false
			MsgBox("Done "..Options.RecordsCount)
			Me.pnlProgressPos.Width = 0
			return
		end
		local rec = rs:GetRecordByIndex(idx)
		if rec then
			local pguid = rec:GetValue(53)
			if not pguid or pguid == "" then
				base:AddLink(rec.SN,30,base.Code,rootSN)
			else
				local pred = CroApp.GetBank():StringRequest("ОТ "..base.Code.."01 52 ТР `".. pguid.."` И 0 НР "..rec.SN)
				if pred.Count > 0 then
					base:AddLink(rec.SN,30,base.Code,pred:ToTable()[1])
				else
					base:AddLink(rec.SN,30,base.Code,rootSN)
				end
			end	
		end
		idx = idx + 1
	until DateTime.TicksNow - ticks > 200
	local pos = idx/rs.Count
	Me.labProgress.Text = ("Построение иерархии: %.1f%%"):format(100*pos)
	Me.pnlProgressPos.Width = Me.pnlProgressPos.Parent.Width * pos
	timer:Start()
end

end	-- /построение иерархии в словаре
