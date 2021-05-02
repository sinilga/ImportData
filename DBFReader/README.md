# DBFReader
Модуль, реализующий функции чтения из DBF-файлов.
### Свойства
- *number* **VersionID** -  
  сигнатура версии DBF
  
- *DateTime* **LastUpdate** -  
  дата последнего обновления файла
  
- *number* **HeaderLength** -  
  длина заголовка
  
- *number* **RecordsCount** -  
  количество записей в файле
  
- *number* **FirstRecordPosition** -  
  смещение области данных
  
- *number* **RecordLength** -  
  длина записи  
	
- *number* **CodePage** -  
  идентификатор кодовой таблицы

- *number* **FieldsCount** -  
  количество полей

- *table* **Fields** - 
массив таблиц, каждая из которых описывает одно поле DBF-файла и содержит следующие поля:  
	*string* **Name** - имя поля;  
	*string* **Type** - тип поля;  
	*number* **Length** - длина значения.  

### Методы
- **new**(*string* file_name) -  
конструктор класса. Открывает файл file_name и создает объект класса `DBFReader`. По окончании работы файл файл должен быть закрыт методом `close`.
``` lua
dbf = DBFReader(file_name)
...
dbf:close()
```

- **read**() -  
читает очередную запись из файла, возвращает таблицу "ключ-значение". Ключ - имя поля.
```lua
dbf = DBFReader(file_name)
repeat 
	local rec = dbf:read()
	...
until not rec
dbf:close()
```

- **skip**(*number* n) -  
пропускает указанное количество записей (читает данные из файла не возвращая значений).
```lua
dbf = DBFReader(file_name)
dbf:skip(10)
dbf:close()
```

- **lines**() - итератор по записям.
```lua
dbf = DBFReader(file_name)
for rec in dbf:lines() do
...
end
dbf:close()
```

- **close**() - закрывает файл

### Пример использования
```lua
function dbf2csv(src_file,dest_file)
	dbf = DBFReader(src_file)
	if not dbf then
		return
	end
	writefile(dest_file,"")
	repeat
		local rec = dbf:read()
		if not rec then
			break
		end
		local t = {}
		for i=1,#Fields do
			local fname = Fields[i].Name
			local val = rec[fname] or ""
			table.insert(t,val)
		end	
		appendfile(dest_file,table.concat(t,";").."\n")
	until not rec
	dbf:close()
end
```
### См.также
- [Структура DBF-файла](http://www.autopark.ru/ASBProgrammerGuide/DBFSTRUC.HTM)
- [Geoff Leyland lua-dbf](https://github.com/geoffleyland/lua-dbf), 
- [Alexey Melnichuk gist](https://gist.github.com/moteus/33a68673cfa52eeccc6e132e55e960eb)
