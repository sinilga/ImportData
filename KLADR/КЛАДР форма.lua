local Options = {
	boxes = {},
	Level = 2,					-- уровень объектов для загрузки 
							-- (1 - регионы/2-районы и города областного подчинения/
							-- 3- другие населенные пункты)
	
	VocBase = CroApp.GetBank():GetBase("BJ"),	-- BJ - мнемокод словарной базы
	FileHandle = nil,
	MaxRecords = nil,
}

function btnBrowse_Click( control, event )
	local fn = FileOpenDialog("csv", "", "", "Select file", OfnExplorer+OfnEnableSizing,"csv-files|*.csv|all files|*.*||")
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
		[Me.cbDistr] = 2, 
		[Me.cbCity] = 3, 
	}
	SetLevel(Options.Level)
	for ctrl,_ in pairs(Options.boxes) do
		ctrl.Click = function(control)
			Options.Level = Options.boxes[control]
			SetLevel(Options.Level)
		end
	end
	Me.pnlProgressPos.Resize = function( event )
		Me.pnlEdge.X = Me.pnlEdge.Parent.Width-1
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

function Load()
	local fh = Options.FileHandle
	local base = Options.VocBase
	ClearBase(base)
	Options.Root = base:AddRecord()
	Options.RecordsCount = base.RecordsCount
	Options.RS = {}
	Me.labProgress.Visible = true
	timer = Me:CreateTimer(do_step,1,true)
end

do -- загрузка данных в словарную базу

local tail = ""

function do_step()
	timer:Stop()
	local fh = Options.FileHandle
	local ticks = DateTime.TicksNow
	repeat
		local txt = fh:read(1024*50)
		if Options.MaxRecords and 
			Options.VocBase.RecordsCount >= Options.MaxRecords or 
			not txt then 
			if #Options.RS > 0 then
				local ok, err = Options.VocBase:AddRecordsBlock(Options.RS,true,false)
				Options.RS = {}
			end	
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
	if attr[3]:match("%D") then return end
	
	local level = nil
	local code = {attr[3]:match("^(%d%d)(%d%d%d)(%d%d%d)(%d%d%d)%d%d$")}
	for i=1,#code do code[i] = tonumber(code[i]) end
	if code[1] > 0 and code[2] == 0 and code[3] == 0 and code[4] == 0 then
	--	region
		level = 1
	elseif code[1] > 0 and code[2] > 0 and code[3] == 0 and code[4] == 0 then
	--	distr
		level = 2
	elseif code[1] > 0 and code[2] == 0 and code[3] > 0 and code[4] == 0 then
	--	central city
		level = 2
	else
		level = 3
	end
	if (not Options.MaxRecords or base.RecordsCount + Options.RecordsCount < Options.MaxRecords) and 
		level <= Options.Level then
		local rec = Record(base)
		rec:SetValue(10,attr[3])
		rec:SetValue(20,attr[1].." "..attr[2])
		rec:SetValue(50,attr[4])
		rec:SetValue(51,attr[7])
		
		Options.RecordsCount = Options.RecordsCount + 1
		if #Options.RS < 100 then
			table.insert(Options.RS,rec)
		else
			local ok, err = base:AddRecordsBlock(Options.RS,true,false)
			Options.RS = {}
		end
	end	
end 

end	-- /загрузка данных в словарную базу



do	-- построение иерархии в словаре

local rs
local idx
local base

function MakeHier()
	base = Options.VocBase
	idx = 1
	rs = Options.VocBase.RecordSet	
	rs:Remove(Options.Root.SN)
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
			local code = rec:GetValue(10)
			local pcode = {code:sub(1,2)..("0"):rep(9).."??",code:sub(1,5)..("0"):rep(6).."??",code:sub(1,8)..("0"):rep(3).."??"}
			local k = #pcode
			repeat
				local pred = CroApp.GetBank():StringRequest("ОТ "..base.Code.."01 10 РВ ".. pcode[k].." И 0 НР "..rec.SN)
				if pred.Count > 0 then
					base:AddLink(rec.SN,30,base.Code,pred:ToTable()[1])
					break
				end
				k = k - 1
			until k < 1 
			if k < 1 then 
				base:AddLink(rec.SN,30,base.Code,Options.Root.SN)
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
