// This file contains your Data Connector logic
section Wildberries;

[DataSource.Kind="Wildberries", Publish="Wildberries.Publish"]
shared Wildberries.Data = Value.ReplaceType(Wildberries.Func, FuncType);

FuncType = type function (
      
    reportType  as (type text meta 
    [
        Documentation.FieldCaption = "Выберите тип отчёта:",
        Documentation.SampleValues = {"Продажи"},
        Documentation.AllowedValues = { "Остатки", "Поставки", "Заказы", "Продажи","Реализация" }
    ]),
     

    dateFrom as (type text meta 
    [
        Documentation.FieldCaption = "Дата начала:",
        Documentation.SampleValues = {"2024-02-28"}
    ])


    )
    as table meta [
        Documentation.Name = "Забираем данные из WildBerries",
        Documentation.LongDescription =  "",
        Documentation.Examples = {
        [
            
        ]
        }
    ];



Wildberries.Func =    (reportType as text, dateFrom as text)=>

let 
    start = dateFunc(dateFrom),
    end = dateFunc("yesterday"),
    apiKey = Extension.CurrentCredential()[Key],    

    orders = let
        	web = Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v1/supplier/orders", 
		[Headers=[Authorization= apiKey , #"Content-Type"="application/json"], Query=[#"dateFrom"=start]])),
	        columnList = List.Distinct(Record.FieldNames(web{0})),
	        recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
	        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList),
	        dubli = Table.Distinct(tableFromRecords, columnList),
	        textType = Table.TransformColumns(dubli, {{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}, {"date", each Text.BeforeDelimiter(_, "T"), 
		type text},{"cancelDate", each Text.BeforeDelimiter(_, "T"), type text}}),
	        dateType = Table.TransformColumnTypes(textType,{{"date", type date}, {"lastChangeDate", type date}, {"cancelDate", type date}})       
         in dateType,


    sales = let
                web = Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v1/supplier/sales", 
		[Headers=[Authorization= apiKey , #"Content-Type"="application/json"], Query=[#"dateFrom"= start]])),
        	columnList =  List.Distinct(Record.FieldNames(web{0})),
        	recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
	        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList), 
	        dubli = Table.Distinct(tableFromRecords, columnList),
	        textType = Table.TransformColumns(dubli, {{"date", each Text.BeforeDelimiter(_, "T"), type text}, {"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
	        saleIds = Table.TransformColumnTypes(textType,{{"saleID", type text}}),
	        status = Table.AddColumn(saleIds, "Статус", each Text.Start([saleID], 1), type text),
	        #"Замененное значение" = Table.ReplaceValue(status,"S","Продажа",Replacer.ReplaceText,{"Статус"}),
	        #"Замененное значение1" = Table.ReplaceValue(#"Замененное значение","R","Возврат",Replacer.ReplaceText,{"Статус"}),
	        #"Замененное значение2" = Table.ReplaceValue(#"Замененное значение1","A","Сторно продаж",Replacer.ReplaceText,{"Статус"}),
	        #"Замененное значение3" = Table.ReplaceValue(#"Замененное значение2","B","Сторно возврата",Replacer.ReplaceText,{"Статус"}),
	        #"Замененное значение4" = Table.ReplaceValue(#"Замененное значение3","D","Доплата",Replacer.ReplaceText,{"Статус"}),
	        dateType = Table.TransformColumnTypes(#"Замененное значение4",{{"date", type date}, {"lastChangeDate", type date}})        
	    in dateType,

    realized = let
        web = Json.Document(Web.Contents("https://statistics-api.wildberries.ru/api/v5/supplier/reportDetailByPeriod", 
        [Headers=[Authorization= apiKey , #"Content-Type"="application/json"], Query=[#"dateFrom"=start, #"dateTo"=end]])),
        columnList =  List.Distinct(Record.FieldNames(web{0})),
        recordsFromList = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        tableFromRecords = Table.ExpandRecordColumn(recordsFromList, "Column1", columnList, columnList),   
        dubli = Table.Distinct(tableFromRecords, columnList),
        textType = Table.TransformColumns(dubli, {{"order_dt", each Text.BeforeDelimiter(_, "T"), type text}, {"sale_dt", each Text.BeforeDelimiter(_, "T"), type text}, 
	{"rr_dt", each Text.BeforeDelimiter(_, "T"), type text}}),
        dateType = Table.TransformColumnTypes(textType,{{"order_dt", type date}, {"rr_dt", type date}, {"sale_dt", type date}})        
    in dateType,
        
  postavki = 
    let
        web=Json.Document(Web.Contents("https://statistics-api.wildberries.ru/", [RelativePath = "api/v1/supplier/incomes",  
	Headers=[Authorization = apiKey ,#"Content-Type"="application/json"], Query=[#"dateFrom"=start]])),
        columns = List.Distinct(List.Combine(List.Transform(web, each Record.FieldNames(_)))),
        #"Преобразовано в таблицу" = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", columns, columns),
        #"Измененный тип" = Table.TransformColumnTypes(#"Развернутый элемент Column1",{{"date", type text}, {"lastChangeDate", type text}, {"dateClose", type text}}),
        split = Table.TransformColumns(#"Измененный тип", {{"date", each Text.BeforeDelimiter(_, "T"), type text},{"dateClose", each Text.BeforeDelimiter(_, "T"),
	 type text},{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
        #"Измененный тип1" = Table.TransformColumnTypes(split,{{"lastChangeDate", type date}, {"date", type date}, {"dateClose", type date}})
    in
        #"Измененный тип1",

    ostatki=
    let
        web=Json.Document(Web.Contents("https://statistics-api.wildberries.ru/", [RelativePath = "api/v1/supplier/stocks", Headers=[Authorization= apiKey , #"Content-Type"="application/json"], Query=[#"dateFrom"=start]])),
        columns = List.Distinct(List.Combine(List.Transform(web, each Record.FieldNames(_)))),
        #"Преобразовано в таблицу" = Table.FromList(web, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        #"Развернутый элемент Column1" = Table.ExpandRecordColumn(#"Преобразовано в таблицу", "Column1", columns, columns),
        #"Извлеченный текст перед разделителем" = Table.TransformColumns(#"Развернутый элемент Column1", {{"lastChangeDate", each Text.BeforeDelimiter(_, "T"), type text}}),
        #"Измененный тип" = Table.TransformColumnTypes(#"Извлеченный текст перед разделителем",{{"lastChangeDate", type date}, {"Discount", type number}}),
        #"Разделенный столбец" = Table.TransformColumns(#"Измененный тип", {{"Discount", each _ / 100, type number}}),
        #"Измененный тип1" = Table.TransformColumnTypes(#"Разделенный столбец",{{"Discount", Percentage.Type}})
    in
        #"Измененный тип1",

    report = 
    if reportType = "Остатки" then ostatki else
    if reportType = "Поставки" then postavki else
    if reportType = "Заказы" then orders else
    if reportType = "Продажи" then sales else
    if reportType = "Реализация" then realized else 
    "Отчёт не выбран",
    
    reporterror = try report

in 
    try reporterror[Error] otherwise reporterror[Value];


    


    dateFunc = (dat)=>
        if dat = "yesterday" then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()) , -1),"yyyy-MM-dd") 
        else if dat = "today" then Date.ToText(Date.From(DateTime.LocalNow()),"yyyy-MM-dd")
        else if (try Number.From(Text.BeforeDelimiter(dat,"daysAgo")) otherwise 0) >0 then Date.ToText(Date.AddDays(Date.From(DateTime.LocalNow()),-1*Number.From(Text.BeforeDelimiter(dat,"daysAgo"))),"yyyy-MM-dd") 
        else dat;    




Wildberries = [
    TestConnection = (dataSourcePath) => 
        { "Wildberries.Data", 
        Json.Document(dataSourcePath)[reportType], 
        Json.Document(dataSourcePath)[dateFrom]
        },
    Authentication = [
        
         Key = []
   
    ],
    Label = "Wildberries Connection"
];



Wildberries.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { "Wildberries Connector", "Wildberries Help" },
    LearnMoreUrl = "",
    SourceImage = Wildberries.Icons,
    SourceTypeImage = Wildberries.Icons
];



Wildberries.Icons = [
    Icon16 = { Extension.Contents("Wildberries16.png"), Extension.Contents("Wildberries20.png"), Extension.Contents("Wildberries24.png"), Extension.Contents("Wildberries32.png") },
    Icon32 = { Extension.Contents("Wildberries32.png"), Extension.Contents("Wildberries40.png"), Extension.Contents("Wildberries48.png"), Extension.Contents("Wildberries64.png") }
];
