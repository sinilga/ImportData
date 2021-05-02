Options = {
	boxes = {	},
	Level = 4,
	VocBase = CroApp.GetBank():GetBase("FS"),
	FileHandle = nil,
	MaxRecords = nil,
	Order = {},
}

function btnBrowse_Click( control, event )
	local fn = FileOpenDialog()
	if fn then
		fn = fn[1]
		Me.txtFileName.Text = fn
		local n = IO.File.GetInfo(fn).Size
		Me.labFileSize.Text = ("%.1f KB"):format(n/1024)
	end	
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

function btnLoad_Click( control, event )
	local fh = io.open(Me.txtFileName.Text,"r")
	Options.FileHandle = fh
	Options.FileSize = IO.File.GetInfo(Me.txtFileName.Text).Size
	Load(fh)
end

do 

local timer = nil
local tail = ""

function Load()
	local fh = Options.FileHandle
	local base = Options.VocBase
	Options.RecordsCount = base.RecordsCount
	Options.RS = {}
	local firstline = fh:read()
	if not firstline then
		return 
	end
	Options.Order = {}
	firstline = firstline:split(";")
	for i=1,#firstline do
		Options.Order[firstline[i]] = i
	end
	Me.labProgress.Visible = true
	timer = Me:CreateTimer(do_step,1,true)
end

function do_step()
	timer:Stop()
	local fh = Options.FileHandle
	local ticks = DateTime.TicksNow
	repeat
		local txt = fh:read(1024*100)
		if Options.MaxRecords and 
		   Options.VocBase.RecordsCount >= Options.MaxRecords or 
		   not txt then 
			timer:delete()
			fh:close()
			Me.pnlProgressPos.Width = 0
			Me.labProgress.Visible = false
			MakeHier()
			return 
		end
		tail = load_chank(tail..txt)	
	until DateTime.TicksNow - ticks > 200
	local pos = fh:seek()
	Me.labProgress.Text = ("Загрузка данных: %.1f%%"):format(100*pos/Options.FileSize)
	Me.pnlProgressPos.Width = Me.pnlProgressPos.Parent.Width * pos/Options.FileSize
	timer:Start()
end

function load_chank(txt)
	for line in txt:gmatch("(.-)[\r\n]+") do
		proc_item(line)
	end
	local ret = txt:match(".+[\r\n]+(.+)")
	return ret
end

function proc_item(item)
	local base = Options.VocBase
	local attr = item:split(";")
	local status = attr[Options.Order["CURRSTATUS"]]
	if status ~= "0" then
		return
	end
	local level = attr[Options.Order["AOLEVEL"]]
	if (not Options.MaxRecords or Options.RecordsCount <= Options.MaxRecords) and 
	   (not level or level <= tostring(Options.Level)) then 
		local rec = Record(base)
		local code = Options.Order["PLAINCODE"] and attr[Options.Order["PLAINCODE"]] or ""
		local offname = Options.Order["OFFNAME"] and attr[Options.Order["OFFNAME"]] or ""
		local shortname = Options.Order["SHORTNAME"] and attr[Options.Order["SHORTNAME"]] or ""
		local name = offname.." "..shortname
		local guid = Options.Order["AOGUID"] and attr[Options.Order["AOGUID"]] or ""
		local pguid = Options.Order["PARENTGUID"] and attr[Options.Order["PARENTGUID"]] or ""
		if name:trim() == "" then
			local stop = 1
		end
		rec:SetValue(10,code)
		rec:SetValue(20,name)
		rec:SetValue(52,guid)
		rec:SetValue(53,pguid)

		Options.RecordsCount = Options.RecordsCount + 1
		base:AddRecord(rec)
	end	
end 

end

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
			MsgBox("Done")
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
